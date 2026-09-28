import { execFile, spawn } from "child_process"
import { promisify } from "util"
import fs from "fs"
import { readFile } from "fs/promises"
import os from "os"
import path from "path"
import { layoutAccount } from "@/lib/launch-layout"
import { scriptsDir } from "@/lib/install-root"

const execFileAsync = promisify(execFile)

const HOSTS: Record<string, string> = {
  "101": "192.168.0.101",
  "102": "192.168.0.102",
  "103": "192.168.0.103",
}

const SCREENS: Record<string, string> = {
  TV1: "101",
  TV2: "101",
  TV3: "101",
  TV4: "101",
  TV5: "101",
  TV6: "101",
  TV7: "101",
  TV8: "101",
  TV9: "102",
  TV10: "102",
  TV11: "102",
  TV12: "102",
  TV14: "102",
  TV15: "102",
  TV16: "102",
  TV17: "102",
  TV13: "103",
  TV18: "103",
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

function psString(value: string) {
  return `'${value.replaceAll("'", "''")}'`
}

export function thumbPath(screen: string) {
  const computer = SCREENS[screen]
  const host = computer ? HOSTS[computer] : ""
  if (!host || !/^TV\d+$/.test(screen)) return ""
  return path.join(layoutsRoot(host), "thumbs", `${screen}.jpg`)
}

const thumbCache = new Map<string, Buffer>()
const thumbFresh = new Map<string, number>()
const thumbJobs = new Map<string, Promise<Buffer | null>>()
let remoteReads = 0
const remoteWait: Array<() => void> = []

function withRemoteSlot<T>(job: () => Promise<T>) {
  return new Promise<T>((resolve, reject) => {
    const run = () => {
      remoteReads += 1
      job().then(resolve, reject).finally(() => {
        remoteReads -= 1
        const next = remoteWait.shift()
        if (next) next()
      })
    }
    if (remoteReads < 2) run()
    else remoteWait.push(run)
  })
}

export async function readThumb(screen: string) {
  const file = thumbPath(screen)
  if (!file) return null
  const cached = thumbCache.get(screen)
  const age = Date.now() - (thumbFresh.get(screen) ?? 0)
  if (cached && age < 4000) return cached
  let job = thumbJobs.get(screen)
  if (!job) {
    const remote = file.startsWith("\\\\")
    const load = async () => {
      try {
        const bytes = await readFile(file)
        thumbCache.set(screen, bytes)
        thumbFresh.set(screen, Date.now())
        return bytes
      } catch {
        return cached ?? null
      }
    }
    job = (remote ? withRemoteSlot(load) : load()).finally(() => {
      thumbJobs.delete(screen)
    })
    thumbJobs.set(screen, job)
  }
  if (cached) return cached
  return job
}

async function captureFresh(host: string) {
  try {
    const text = await fs.promises.readFile(path.join(layoutsRoot(host), "thumbs", "alive.txt"), "utf8")
    const time = Date.parse(text.trim())
    return Number.isFinite(time) && Date.now() - time < 5000
  } catch {
    return false
  }
}

async function publishCapture(host: string) {
  const root = layoutsRoot(host)
  await fs.promises.mkdir(root, { recursive: true }).catch(() => undefined)
  try {
    await fs.promises.access(root)
  } catch {
    return
  }
  for (const name of ["Capture-Thumbs.ps1", "Start-Thumbs.bat"]) {
    const source = path.join(scriptsDir(), name)
    const dest = path.join(root, name)
    try {
      const [from, to] = await Promise.all([fs.promises.stat(source), fs.promises.stat(dest)])
      if (to.mtimeMs >= from.mtimeMs) continue
    } catch {
      // The destination is missing, so copy it.
    }
    await fs.promises.copyFile(source, dest)
  }
}

function startLocalCapture() {
  const child = spawn(
    "powershell.exe",
    ["-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", "C:\\layouts\\Capture-Thumbs.ps1"],
    { detached: true, stdio: "ignore", windowsHide: true },
  )
  child.unref()
}

async function startRemoteCapture(host: string, user: string, password: string) {
  const script = `
$ErrorActionPreference = 'Continue'
$HostName = ${psString(host)}
$User = ${psString(user)}
$Pass = ${psString(password)}
$share = "\\\\$HostName\\c$"
$net = & net.exe use $share "/user:$User" $Pass 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -and $net -notmatch 'already in use|multiple connections') { exit 1 }
$tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\layouts\\Launch-InSession.ps1 -Bat C:\\layouts\\Start-Thumbs.bat'
& schtasks.exe /Create /S $HostName /U $User /P $Pass /RU SYSTEM /SC ONCE /ST 00:00 /RL HIGHEST /TN WallThumbs /TR $tr /F | Out-Null
if ($LASTEXITCODE -ne 0) { exit 1 }
& schtasks.exe /Run /S $HostName /U $User /P $Pass /TN WallThumbs | Out-Null
exit 0
`
  await execFileAsync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], {
    windowsHide: true,
    timeout: 25000,
  })
}

export async function ensureThumbCaptures() {
  const account = layoutAccount()
  await Promise.all(
    Object.values(HOSTS).map(async (host) => {
      try {
        await publishCapture(host)
      } catch {
        return
      }
      if (await captureFresh(host)) return
      try {
        if (machineIs(host)) startLocalCapture()
        else if (account.password) await startRemoteCapture(host, account.user, account.password)
      } catch {
        // The tile stays blank until this computer can reach that desktop.
      }
    }),
  )
}
