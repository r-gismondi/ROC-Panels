import { execFile, spawn } from "child_process"
import crypto from "crypto"
import { promisify } from "util"
import fs from "fs"
import os from "os"
import path from "path"
import { installRoot, scriptsDir } from "@/lib/install-root"

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
$task = 'cmd.exe /c C:\\layouts\\Start-Watch.bat'
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
  return file
}

function fileHash(file: string) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex")
}

function watcherIdentity() {
  const launch = fileHash(path.join(scriptsDir(), "Watch-Launch.ps1"))
  const start = fileHash(path.join(scriptsDir(), "Start-Watch.bat"))
  return `${launch} ${start}`
}

function watcherIsCurrent(host: string) {
  try {
    const text = fs.readFileSync(path.join(layoutsRoot(host), "watcher-script.txt"), "utf8").trim().toLowerCase()
    return text === watcherIdentity()
  } catch {
    return false
  }
}

async function waitUntilGone(file: string, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (!fs.existsSync(file)) return true
    await new Promise((resolve) => setTimeout(resolve, 100))
  }
  return !fs.existsSync(file)
}

function publishWatcher(host: string) {
  const root = layoutsRoot(host)
  fs.mkdirSync(root, { recursive: true })
  for (const name of ["Watch-Launch.ps1", "Start-Watch.bat", "Launch-InSession.ps1", "Capture-Thumbs.ps1", "Start-Thumbs.bat"]) {
    fs.copyFileSync(path.join(scriptsDir(), name), path.join(root, name))
  }
}

function startLocalWatcher() {
  const child = spawn("cmd.exe", ["/c", "C:\\layouts\\Start-Watch.bat"], {
    detached: true,
    stdio: "ignore",
    windowsHide: true,
  })
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
  if (watcherIsCurrent(host) && (await watcherFresh(host))) {
    scheduleRemoteLogon(host, user, password)
    return
  }
  publishWatcher(host)
  watcherReadyUntil.delete(host)
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
          "cmd.exe /c C:\\layouts\\Start-Watch.bat",
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
    if (watcherIsCurrent(host) && (await watcherFresh(host))) {
      scheduleRemoteLogon(host, user, password)
      return
    }
    await new Promise((resolve) => setTimeout(resolve, 200))
  }
  throw new Error(`The layout watcher on ${host} did not start.`)
}

function readEnvValue(file: string, key: string) {
  try {
    const text = fs.readFileSync(file, "utf8")
    const match = text.match(new RegExp(`^${key}=(.*)$`, "m"))
    return match?.[1]?.trim() || ""
  } catch {
    return ""
  }
}

export function layoutAccount() {
  let user = process.env.LAYOUT_USER || ""
  let password = process.env.LAYOUT_PASSWORD || ""
  const configPath = path.join(installRoot(), "pedestal.config.json")
  try {
    const config = JSON.parse(fs.readFileSync(configPath, "utf8")) as { layoutUser?: string; layoutPassword?: string }
    if (!user && config.layoutUser) user = config.layoutUser
    if (!password && config.layoutPassword) password = config.layoutPassword
  } catch {
    // The development server keeps the account in .env.local.
  }
  const envFiles = [path.join(process.cwd(), ".env.local"), path.join(installRoot(), "web", ".env.local")]
  for (const file of envFiles) {
    if (!user) user = readEnvValue(file, "LAYOUT_USER")
    if (!password) password = readEnvValue(file, "LAYOUT_PASSWORD")
  }
  return { user: user || "Administrator", password }
}

function layoutStateFile(computer: string) {
  return path.join(installRoot(), "layout-state", `${computer}.txt`)
}

function rememberLayout(computer: string, preset: string) {
  const allowed = ALLOWED[computer]
  if (!allowed?.includes(preset)) return
  const file = layoutStateFile(computer)
  fs.mkdirSync(path.dirname(file), { recursive: true })
  const temporary = `${file}.${process.pid}.tmp`
  fs.writeFileSync(temporary, preset, "ascii")
  fs.renameSync(temporary, file)
}

export function readLayoutState() {
  const layouts: Record<string, string> = { "101": "", "102": "", "103": "" }
  for (const computer of Object.keys(layouts)) {
    try {
      const text = fs.readFileSync(layoutStateFile(computer), "utf8").trim()
      if (ALLOWED[computer]?.includes(text)) layouts[computer] = text
    } catch {
      // This computer has not accepted a layout command yet.
    }
  }
  return layouts
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
  const account = layoutAccount()
  const user = account.user
  const password = account.password
  if (!password) return { ok: false, message: "Set layoutPassword in pedestal.config.json, then start the console again." }

  try {
    const known = (watcherReadyUntil.get(command.host) ?? 0) > Date.now() && watcherIsCurrent(command.host)
    if (known) void watcherFresh(command.host).catch(() => watcherReadyUntil.delete(command.host))
    else await ensureWatcher(command.host, user, password)
    if (preset !== "close") {
      const close = layoutCommand(computer, "close")
      if (!close) return { ok: false, message: "That preset is not on this computer." }
      const ticket = queueLaunch(command.host, close.path)
      const closed = await waitUntilGone(ticket, 20000)
      if (!closed) return { ok: false, message: `Edge on ${command.host} did not close.` }
      await new Promise((resolve) => setTimeout(resolve, 700))
    }
    queueLaunch(command.host, command.path)
    rememberLayout(computer, preset)
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
  const viewerPath = "C:\\Program Files\\RealVNC\\VNC Viewer\\vncviewer.exe"
  const shortcut = path.join("C:\\Program Files\\RealVNC\\VNC Viewer", `${host}.lnk`)
  if (!fs.existsSync(viewerPath) || !fs.existsSync(shortcut)) {
    return { ok: false, message: `The VNC shortcut for ${host} was not found.` }
  }
  const sessionScript = path.join(scriptsDir(), "Show-VncSession.ps1")
  const session = spawn(
    "powershell.exe",
    ["-NoProfile", "-STA", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", sessionScript, "-ComputerName", name, "-Address", host],
    { stdio: ["ignore", "pipe", "pipe"], windowsHide: true },
  )
  session.stdout.resume()
  session.stderr.resume()
  session.unref()
  const button = path.join(scriptsDir(), "Show-KeyboardButton.ps1")
  const keyboard = spawn(
    "powershell.exe",
    ["-NoProfile", "-STA", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", button],
    { stdio: ["ignore", "pipe", "pipe"], windowsHide: true },
  )
  keyboard.stdout.resume()
  keyboard.stderr.resume()
  keyboard.unref()
  return { ok: true, message: `${name} is open on this screen. Use Close to come back.` }
}
