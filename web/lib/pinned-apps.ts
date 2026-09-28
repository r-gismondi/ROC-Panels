import { execFile } from "child_process"
import crypto from "crypto"
import { promisify } from "util"
import fs from "fs"
import path from "path"
import { installRoot } from "@/lib/install-root"
import { launchProgram, type LaunchResult } from "@/lib/launch-layout"

const execFileAsync = promisify(execFile)

export type PinnedApp = { id: string; name: string; path: string }

function pinsFile() {
  return path.join(installRoot(), "pinned-apps.json")
}

export function readPins(): PinnedApp[] {
  try {
    const parsed = JSON.parse(fs.readFileSync(pinsFile(), "utf8")) as unknown
    if (!Array.isArray(parsed)) return []
    return parsed.filter((item): item is PinnedApp => {
      if (!item || typeof item !== "object") return false
      const pin = item as PinnedApp
      return typeof pin.id === "string" && typeof pin.name === "string" && typeof pin.path === "string"
    })
  } catch {
    return []
  }
}

function writePins(pins: PinnedApp[]) {
  const file = pinsFile()
  fs.mkdirSync(path.dirname(file), { recursive: true })
  const temporary = `${file}.${process.pid}.tmp`
  fs.writeFileSync(temporary, JSON.stringify(pins, null, 2), "utf8")
  fs.renameSync(temporary, file)
}

const BROWSE_SCRIPT = `
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = 'Programs (*.exe;*.lnk)|*.exe;*.lnk'
$dialog.Title = 'Choose a program'
$dialog.CheckFileExists = $true
if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 2 }
$picked = $dialog.FileName
$display = [System.IO.Path]::GetFileNameWithoutExtension($picked)
$target = $picked
if ([System.IO.Path]::GetExtension($picked) -eq '.lnk') {
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($picked)
  $target = [string]$shortcut.TargetPath
}
if (-not $target -or [System.IO.Path]::GetExtension($target) -ne '.exe') { Write-Error 'Choose a program.'; exit 1 }
if (-not (Test-Path -LiteralPath $target)) { Write-Error 'That program was not found.'; exit 1 }
[Console]::Out.WriteLine($target)
[Console]::Out.WriteLine($display)
`

export async function browseForProgram(): Promise<{ ok: true; pins: PinnedApp[]; selectedId: string; canceled?: boolean } | { ok: false; message: string }> {
  if (process.platform !== "win32") return { ok: false, message: "Run this page on the touchscreen to choose a program." }
  let stdout = ""
  try {
    const result = await execFileAsync(
      "powershell.exe",
      ["-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-Command", BROWSE_SCRIPT],
      { windowsHide: true, timeout: 120000 },
    )
    stdout = result.stdout
  } catch (error) {
    const failed = error as { code?: number | string; stdout?: string; stderr?: string }
    if (failed.code === 2 || failed.code === "2") return { ok: true, pins: readPins(), selectedId: "", canceled: true }
    const detail = `${failed.stderr ?? ""}`.trim()
    if (/Choose a program/i.test(detail)) return { ok: false, message: "Choose a program." }
    if (/was not found/i.test(detail)) return { ok: false, message: "That program was not found." }
    return { ok: false, message: "The program list could not be opened." }
  }
  const lines = stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
  const exe = lines[0] ?? ""
  const display = lines[1] || path.basename(exe, path.extname(exe))
  if (!/^[A-Za-z]:\\[^<>:"|?*\r\n]+\.exe$/i.test(exe)) return { ok: false, message: "Choose a program." }
  const pins = readPins()
  const existing = pins.find((pin) => pin.path.toLowerCase() === exe.toLowerCase())
  if (existing) return { ok: true, pins, selectedId: existing.id }
  if (pins.length >= 24) return { ok: false, message: "Remove a program before adding another." }
  const pin = { id: crypto.randomUUID(), name: display.slice(0, 40) || "Program", path: exe }
  const next = [...pins, pin]
  writePins(next)
  return { ok: true, pins: next, selectedId: pin.id }
}

export function removePin(id: string) {
  const next = readPins().filter((pin) => pin.id !== id)
  writePins(next)
  return next
}

export async function launchPinned(id: string, screen: string): Promise<LaunchResult> {
  const pin = readPins().find((item) => item.id === id)
  if (!pin) return { ok: false, message: "Choose a program, then tap a screen." }
  return launchProgram(screen, pin.path, pin.name)
}
