import { execFile, spawn } from "child_process"
import { promisify } from "util"
import fs from "fs"
import os from "os"
import path from "path"

const execFileAsync = promisify(execFile)

const HOSTS: Record<string, string> = {
  "101": "192.168.0.101",
  "102": "192.168.0.102",
  "103": "192.168.0.103",
}

const BATS: Record<string, string> = {
  independent: "Edge-Independent.bat",
  split: "Edge-Split.bat",
  focus: "Edge-Focus.bat",
  "focus-split": "Edge-Focus-Split.bat",
  full: "Edge-Full.bat",
  close: "Edge-Close.bat",
}

const ALLOWED: Record<string, string[]> = {
  "101": ["independent", "split", "focus", "focus-split", "full", "close"],
  "102": ["independent", "split", "focus", "focus-split", "full", "close"],
  "103": ["independent", "full", "close"],
}

export type LaunchResult = { ok: true; message: string } | { ok: false; message: string }

export function layoutCommand(computer: string, preset: string) {
  const host = HOSTS[computer]
  const allowed = ALLOWED[computer]
  const bat = BATS[preset]
  if (!host || !allowed || !bat || !allowed.includes(preset)) return null
  const label = preset === "close" ? "Close" : preset === "focus-split" ? "Focus split" : preset.charAt(0).toUpperCase() + preset.slice(1)
  return { host, bat, path: `C:\\layouts\\computer-${computer}\\${bat}`, label }
}

function redact(text: string, password: string) {
  if (!password) return text
  return text.split(password).join("***")
}

function machineIs(host: string) {
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const entry of entries ?? []) {
      if (entry.family === "IPv4" && entry.address === host) return true
    }
  }
  return false
}

function layoutsRoot(host: string) {
  return machineIs(host) ? "C:\\layouts" : `\\\\${host}\\c$\\layouts`
}

const watcherReadyUntil = new Map<string, number>()
const logonScheduled = new Set<string>()

function scheduleRemoteLogon(host: string, user: string, password: string) {
  if (machineIs(host) || logonScheduled.has(host)) return
  logonScheduled.add(host)
  const script = `
$ErrorActionPreference = 'Continue'
$HostName = ${psString(host)}
$User = ${psString(user)}
$Pass = ${psString(password)}
$task = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\\layouts\\Watch-Launch.ps1'
& schtasks.exe /Create /S $HostName /U $User /P $Pass /SC ONLOGON /RL HIGHEST /TN WallLayoutWatch /TR $task /F | Out-Null
exit 0
`
  void execFileAsync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], {
    windowsHide: true,
    timeout: 60000,
  }).catch(() => {
    logonScheduled.delete(host)
  })
}

async function watcherFresh(host: string) {
  const readyUntil = watcherReadyUntil.get(host) ?? 0
  if (readyUntil > Date.now()) return true
  const file = path.join(layoutsRoot(host), "watcher-alive.txt")
  let first = ""
  try {
    first = fs.readFileSync(file, "utf8")
  } catch {
    return false
  }
  await new Promise((resolve) => setTimeout(resolve, 1500))
  let second = ""
  try {
    second = fs.readFileSync(file, "utf8")
  } catch {
    return false
  }
  if (second === first) return false
  watcherReadyUntil.set(host, Date.now() + 60000)
  return true
}

function queueLaunch(host: string, bat: string) {
  const dir = path.join(layoutsRoot(host), "queue")
  fs.mkdirSync(dir, { recursive: true })
  const file = path.join(dir, `${Date.now()}-${process.pid}.txt`)
  fs.writeFileSync(`${file}.tmp`, bat, "ascii")
  fs.renameSync(`${file}.tmp`, file)
}

function publishWatcher(host: string) {
  const root = layoutsRoot(host)
  fs.mkdirSync(root, { recursive: true })
  for (const name of ["Watch-Launch.ps1", "Start-Watch.bat", "Launch-InSession.ps1"]) {
    fs.copyFileSync(path.join(process.cwd(), "scripts", name), path.join(root, name))
  }
}

function startLocalWatcher() {
  const child = spawn(
    "powershell.exe",
    ["-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", "C:\\layouts\\Watch-Launch.ps1"],
    { detached: true, stdio: "ignore", windowsHide: true },
  )
  child.unref()
}

async function startRemoteWatcher(host: string, user: string, password: string) {
  const script = `
$ErrorActionPreference = 'Continue'
$HostName = ${psString(host)}
$User = ${psString(user)}
$Pass = ${psString(password)}
function Out-Line($Text) { Write-Output $Text }
$share = "\\\\$HostName\\c$"
$net = & net.exe use $share "/user:$User" $Pass 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -and $net -notmatch 'already in use|multiple connections') { Out-Line "Could not open $share"; Out-Line $net; exit 1 }
& schtasks.exe /End /S $HostName /U $User /P $Pass /TN WallLayout 2>$null | Out-Null
$tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\layouts\\Launch-InSession.ps1 -Bat C:\\layouts\\Start-Watch.bat'
$create = & schtasks.exe /Create /S $HostName /U $User /P $Pass /RU SYSTEM /SC ONCE /ST 00:00 /RL HIGHEST /TN WallLayout /TR $tr /F 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Out-Line $create; exit 1 }
$run = & schtasks.exe /Run /S $HostName /U $User /P $Pass /TN WallLayout 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Out-Line $run; exit 1 }
exit 0
`
  const { stdout } = await execFileAsync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], {
    windowsHide: true,
    timeout: 60000,
  })
  const message = redact(stdout.trim(), password)
  if (message) throw new Error(message)
}

async function ensureWatcher(host: string, user: string, password: string) {
  if (await watcherFresh(host)) {
    scheduleRemoteLogon(host, user, password)
    return
  }
  publishWatcher(host)
  if (machineIs(host)) {
    try {
      await execFileAsync(
        "schtasks.exe",
        [
          "/Create",
          "/SC",
          "ONLOGON",
          "/RL",
          "HIGHEST",
          "/TN",
          "WallLayoutWatch",
          "/TR",
          "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\\layouts\\Watch-Launch.ps1",
          "/F",
        ],
        { windowsHide: true, timeout: 15000 },
      )
    } catch {
      // The desktop process below still handles this session when the logon task cannot be saved.
    }
    startLocalWatcher()
  } else {
    await startRemoteWatcher(host, user, password)
  }
  const deadline = Date.now() + (machineIs(host) ? 8000 : 20000)
  while (Date.now() < deadline) {
    if (await watcherFresh(host)) {
      scheduleRemoteLogon(host, user, password)
      return
    }
    await new Promise((resolve) => setTimeout(resolve, 200))
  }
  throw new Error(`The layout watcher on ${host} did not start.`)
}

export async function launchLayout(computer: string, preset: string): Promise<LaunchResult> {
  const command = layoutCommand(computer, preset)
  if (!command) return { ok: false, message: "That preset is not on this computer." }
  if (process.platform !== "win32") {
    return {
      ok: false,
      message: "Run this page on a Windows computer on the wall network. Preset buttons launch the Edge layouts from there.",
    }
  }
  const user = process.env.LAYOUT_USER || "Administrator"
  const password = process.env.LAYOUT_PASSWORD || ""
  if (!password) return { ok: false, message: "Set LAYOUT_PASSWORD to the wall Administrator password, then restart this page." }

  try {
    const known = (watcherReadyUntil.get(command.host) ?? 0) > Date.now()
    if (known) void watcherFresh(command.host).catch(() => watcherReadyUntil.delete(command.host))
    else await ensureWatcher(command.host, user, password)
    queueLaunch(command.host, command.path)
    const message = command.label === "Close" ? `Closed Edge on ${command.host}.` : `Opened ${command.label} on ${command.host}.`
    return { ok: true, message }
  } catch (error) {
    const failed = error as { code?: string; stdout?: string; stderr?: string; message?: string }
    if (failed.code === "ENOENT") return { ok: false, message: "PowerShell was not found." }
    const message = redact(`${failed.stdout ?? ""}\n${failed.stderr ?? ""}`.trim() || failed.message || "The layout did not start.", password)
    return { ok: false, message }
  }
}

function psString(value: string) {
  return `'${value.replaceAll("'", "''")}'`
}

const ADDRESS_SCREENS: Record<string, string[]> = {
  "101": ["TV1", "TV2", "TV3", "TV4", "TV5", "TV6", "TV7", "TV8"],
  "102": ["TV9", "TV10", "TV11", "TV12", "TV14", "TV15", "TV16", "TV17"],
  "103": ["TV13", "TV18"],
}

function validAddress(url: string) {
  return /^https?:\/\/[^\s"'<>\\]+$/.test(url) && url.length <= 2000
}

export function readAddresses(computer: string) {
  const host = HOSTS[computer]
  const screens = ADDRESS_SCREENS[computer]
  const found: Record<string, string> = {}
  if (!host || !screens) return found
  const dir = path.join(layoutsRoot(host), `computer-${computer}`, "addresses")
  for (const screen of screens) {
    try {
      const text = fs.readFileSync(path.join(dir, `${screen}.txt`), "utf8").trim()
      if (validAddress(text)) found[screen] = text
    } catch {
      // This screen is still on the landing page.
    }
  }
  return found
}

export async function setLayoutAddress(computer: string, screen: string, url: string): Promise<LaunchResult> {
  const host = HOSTS[computer]
  const screens = ADDRESS_SCREENS[computer]
  if (!host || !screens || !screens.includes(screen) || !validAddress(url)) {
    return { ok: false, message: "Use an http or https address on a screen of that computer." }
  }
  if (process.platform !== "win32") {
    return { ok: false, message: "Run this page on a Windows computer on the wall network." }
  }
  const root = path.join(layoutsRoot(host), `computer-${computer}`)
  const requests = path.join(root, "url-requests")
  const results = path.join(root, "url-results")
  const resultFile = path.join(results, `${screen}.txt`)
  const requestFile = path.join(requests, `${screen}.txt`)
  try {
    fs.mkdirSync(requests, { recursive: true })
    fs.mkdirSync(results, { recursive: true })
    fs.rmSync(resultFile, { force: true })
    fs.writeFileSync(`${requestFile}.tmp`, url, "utf8")
    fs.renameSync(`${requestFile}.tmp`, requestFile)
  } catch {
    return { ok: false, message: `Could not reach the layout on ${host}.` }
  }
  const started = Date.now()
  let sawWorking = false
  while (Date.now() - started < 20000) {
    await new Promise((resolve) => setTimeout(resolve, 200))
    let text = ""
    try {
      text = fs.readFileSync(resultFile, "utf8").trim()
    } catch {
      text = ""
    }
    if (!text) {
      if (!sawWorking && Date.now() - started > 2500) {
        return { ok: false, message: `Confirm a layout on ${host}, then set the address.` }
      }
      continue
    }
    if (text === "working") {
      sawWorking = true
      continue
    }
    if (text === "ok") {
      const number = screen.replace("TV", "")
      return { ok: true, message: `Screen ${number} on ${host} now shows ${url}.` }
    }
    if (text.startsWith("error ")) return { ok: false, message: text.slice(6) }
    return { ok: false, message: "The screen did not open that address." }
  }
  return { ok: false, message: "The screen did not open that address." }
}

const VNC_NAMES: Record<string, string> = {
  "101": "Computer 1",
  "102": "Computer 2",
  "103": "Computer 3",
}

export function openVnc(computer: string): LaunchResult {
  const host = HOSTS[computer]
  const name = VNC_NAMES[computer]
  if (!host || !name) return { ok: false, message: "That computer is not on this stand." }
  if (process.platform !== "win32") {
    return { ok: false, message: "Run this page on the touchscreen computer to open VNC." }
  }
  const shortcut = path.join("C:\\Program Files\\RealVNC\\VNC Viewer", `${host}.lnk`)
  if (!fs.existsSync(shortcut)) return { ok: false, message: `The VNC shortcut for ${host} was not found.` }
  const viewer = spawn("explorer.exe", [shortcut], { detached: true, stdio: "ignore", windowsHide: true })
  viewer.unref()
  const button = path.join(process.cwd(), "scripts", "Show-KeyboardButton.ps1")
  const keyboard = spawn(
    "powershell.exe",
    ["-NoProfile", "-STA", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", button],
    { stdio: ["ignore", "pipe", "pipe"], windowsHide: true },
  )
  keyboard.stdout.resume()
  keyboard.stderr.resume()
  keyboard.unref()
  return { ok: true, message: `Opened VNC to ${name} (${host}).` }
}
