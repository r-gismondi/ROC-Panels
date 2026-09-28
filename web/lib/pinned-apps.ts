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
Add-Type -AssemblyName System.Drawing
if (-not ('RocBrowse' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
public static class RocBrowse {
  public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  const uint SWP_NOSIZE = 0x0001;
  const uint SWP_NOMOVE = 0x0002;
  const uint SWP_SHOWWINDOW = 0x0040;
  const byte VK_MENU = 0x12;
  const uint KEYEVENTF_KEYUP = 0x0002;
  static bool unlocked;
  static EnumProc enumProc;
  static IntPtr found;
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  public static IntPtr FindTitle(string title) {
    found = IntPtr.Zero;
    uint pid = (uint)Process.GetCurrentProcess().Id;
    enumProc = (h, l) => {
      uint windowPid;
      GetWindowThreadProcessId(h, out windowPid);
      if (windowPid != pid) return true;
      var text = new StringBuilder(512);
      GetWindowText(h, text, text.Capacity);
      if (text.ToString() != title) return true;
      found = h;
      return false;
    };
    EnumWindows(enumProc, IntPtr.Zero);
    return found;
  }
  public static void Focus(IntPtr hwnd) {
    if (hwnd == IntPtr.Zero) return;
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    IntPtr fg = GetForegroundWindow();
    uint fgThread = GetWindowThreadProcessId(fg, IntPtr.Zero);
    uint thisThread = GetCurrentThreadId();
    bool attached = false;
    if (fg != IntPtr.Zero && fgThread != thisThread) attached = AttachThreadInput(fgThread, thisThread, true);
    BringWindowToTop(hwnd);
    SetForegroundWindow(hwnd);
    if (GetForegroundWindow() != hwnd && !unlocked) {
      keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
      keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
      unlocked = true;
      BringWindowToTop(hwnd);
      SetForegroundWindow(hwnd);
    }
    if (attached) AttachThreadInput(fgThread, thisThread, false);
  }
}
'@
}
$owner = New-Object System.Windows.Forms.Form
$owner.TopMost = $true
$owner.ShowInTaskbar = $false
$owner.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$owner.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$owner.Size = New-Object System.Drawing.Size(1, 1)
$owner.Opacity = 0.01
$owner.Show()
[RocBrowse]::Focus($owner.Handle)
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = 'Programs (*.exe;*.lnk)|*.exe;*.lnk'
$dialog.Title = 'Choose a program'
$dialog.CheckFileExists = $true
$state = @{ tries = 0 }
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 80
$onTick = {
  $state.tries++
  $hwnd = [RocBrowse]::FindTitle('Choose a program')
  if ($hwnd -ne [IntPtr]::Zero) {
    [RocBrowse]::Focus($hwnd)
    if ([RocBrowse]::GetForegroundWindow() -eq $hwnd) { $timer.Stop() }
  }
  if ($state.tries -ge 25) { $timer.Stop() }
}.GetNewClosure()
$timer.add_Tick($onTick)
$timer.Start()
try {
  $result = $dialog.ShowDialog($owner)
} finally {
  $timer.Stop()
  $timer.Dispose()
  $owner.Close()
  $owner.Dispose()
}
if ($result -ne [System.Windows.Forms.DialogResult]::OK) { exit 2 }
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
