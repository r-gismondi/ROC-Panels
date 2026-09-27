import { execFile } from "child_process"
import { promisify } from "util"
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

  const helper = path.join(process.cwd(), "scripts", "Launch-InSession.ps1")
  const script = `
$ErrorActionPreference = 'Continue'
$HostName = ${psString(command.host)}
$User = ${psString(user)}
$Pass = ${psString(password)}
$Bat = ${psString(command.path)}
$Helper = ${psString(helper)}
$Label = ${psString(command.label)}
function Out-Line($Text) { Write-Output $Text }
if (@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object IPAddress) -contains $HostName) {
  Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','start','""',$Bat -WorkingDirectory (Split-Path $Bat)
  if ($Label -eq 'Close') { Out-Line "Closed Edge on this computer ($HostName)." } else { Out-Line "Opened $Label on this computer ($HostName)." }
  exit 0
}
$share = "\\\\$HostName\\c$"
$net = & net.exe use $share "/user:$User" $Pass 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Out-Line "Could not open $share"; Out-Line $net; exit 1 }
Copy-Item -LiteralPath $Helper -Destination "\\\\$HostName\\c$\\layouts\\Launch-InSession.ps1" -Force
& schtasks.exe /End /S $HostName /U $User /P $Pass /TN WallLayout 2>$null | Out-Null
$tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\layouts\\Launch-InSession.ps1 -Bat ' + $Bat
$create = & schtasks.exe /Create /S $HostName /U $User /P $Pass /RU SYSTEM /SC ONCE /ST 00:00 /RL HIGHEST /TN WallLayout /TR $tr /F 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Out-Line $create; exit 1 }
$run = & schtasks.exe /Run /S $HostName /U $User /P $Pass /TN WallLayout 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Out-Line $run; exit 1 }
Start-Sleep -Seconds 2
$resultPath = "\\\\$HostName\\c$\\layouts\\launch-result.txt"
if (Test-Path -LiteralPath $resultPath) { Get-Content -LiteralPath $resultPath -Raw } else { Out-Line "Started $Label on $HostName. No result was written yet." }
exit 0
`
  try {
    const { stdout } = await execFileAsync(
      "powershell.exe",
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
      { windowsHide: true, timeout: 45000 },
    )
    const message = redact(stdout.trim(), password)
    if (command.label === "Close") {
      if (!message || message.startsWith("Opened on session") || message.startsWith("Opened Close")) {
        return { ok: true, message: `Closed Edge on ${command.host}.` }
      }
      if (/could not|missing|no signed-in/i.test(message)) return { ok: false, message }
    }
    return { ok: true, message: message || `Opened ${command.label} on ${command.host}.` }
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
