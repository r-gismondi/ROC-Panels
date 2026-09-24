# Opens the CCV2 landing page in one Edge window per section.
# No colored cover frames are created.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Independent", "DualFocus1", "DualFocus2", "DualFocus3", "Full")]
    [string]$Preset
)

$ErrorActionPreference = "Stop"
$HomeUrl = "https://ccv2.mtllc.us/landing"

if (-not ("PanelWin" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct PanelRect { public int Left; public int Top; public int Right; public int Bottom; }
public struct PanelPoint { public int X; public int Y; }
public static class PanelWin {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out PanelRect lpRect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref PanelPoint lpPoint);
    [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);
    [DllImport("user32.dll", EntryPoint = "GetWindowLong")] static extern int GetWindowLong32(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")] static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);
    public static int TitleBar(IntPtr hwnd) {
        PanelRect window;
        GetWindowRect(hwnd, out window);
        PanelPoint origin = new PanelPoint();
        ClientToScreen(hwnd, ref origin);
        int bar = origin.Y - window.Top;
        if (bar < 24) bar = 40;
        return bar;
    }
    public static void Place(IntPtr hwnd, int x, int y, int w, int h) {
        int bar = TitleBar(hwnd);
        int style = GetWindowLong32(hwnd, -16);
        style &= ~0x00C00000;
        style &= ~0x00040000;
        style |= unchecked((int)0x80000000);
        style |= 0x10000000;
        SetWindowLong32(hwnd, -16, style);
        SetWindowPos(hwnd, IntPtr.Zero, x, y - bar, w, h + bar, 0x0020 | 0x0040);
        SetWindowRgn(hwnd, CreateRectRgn(0, bar, w, h + bar), true);
    }
}
"@
}
[void][PanelWin]::SetProcessDPIAware()

function Find-Edge {
    foreach ($candidate in @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Stop-LayoutEdge([string]$Root) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name = 'msedge.exe'" -ErrorAction SilentlyContinue
        foreach ($proc in @($procs)) {
            if ($proc.CommandLine -and $proc.CommandLine -like "*$Root\edge-profiles*") {
                & cmd.exe /c "taskkill /PID $($proc.ProcessId) /T /F >nul 2>&1" | Out-Null
            }
        }
    } catch {}
    $ErrorActionPreference = $previous
}

function Find-ProfileWindow([string]$Profile) {
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'msedge.exe'" -ErrorAction SilentlyContinue
    foreach ($proc in @($procs)) {
        if ($proc.CommandLine -and $proc.CommandLine -like "*$Profile*") {
            $live = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
            if ($live -and $live.MainWindowHandle -ne 0 -and $live.MainWindowTitle) { return $live }
        }
    }
    return $null
}

function Wait-ProfileWindow([string]$Profile, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $found = Find-ProfileWindow $Profile
        if ($found) { return $found }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

$edge = Find-Edge
if (-not $edge) { Write-Error "Microsoft Edge was not found."; exit 1 }

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Stop-LayoutEdge $root
Start-Sleep -Milliseconds 500
$profileRoot = Join-Path $root "edge-profiles"
if (Test-Path -LiteralPath $profileRoot) {
    Remove-Item -LiteralPath $profileRoot -Recurse -Force -ErrorAction SilentlyContinue
}
$pidFile = Join-Path $root "edge-layout.pids"
if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue }
Set-Content -Path $pidFile -Value $PID -Encoding Ascii

function Zone($title, $x, $y, $w, $h) {
    [pscustomobject]@{ Title = $title; X = $x; Y = $y; W = $w; H = $h }
}

$presets = @{
    Independent = @(
        (Zone "TV9"  0    0   960  540)
        (Zone "TV10" 960  0   960  540)
        (Zone "TV14" 0    540 960  540)
        (Zone "TV15" 960  540 960  540)
        (Zone "TV11" 1920 0   960  540)
        (Zone "TV12" 2880 0   960  540)
        (Zone "TV16" 1920 540 960  540)
        (Zone "TV17" 2880 540 960  540)
    )
    DualFocus1 = @(
        (Zone "TV9 TV10 TV14 TV15" 0 0 1920 1080)
        (Zone "TV11 TV16" 1920 0 960 1080)
        (Zone "TV12 TV17" 2880 0 960 1080)
    )
    DualFocus2 = @(
        (Zone "TV9 TV10 TV14 TV15" 0 0 1920 1080)
        (Zone "TV11 TV12 TV16 TV17" 1920 0 1920 1080)
    )
    DualFocus3 = @(
        (Zone "TV9 TV14" 0 0 960 1080)
        (Zone "TV10 TV11 TV15 TV16" 960 0 1920 1080)
        (Zone "TV12 TV17" 2880 0 960 1080)
    )
    Full = @(
        (Zone "All" 0 0 3840 1080)
    )
}

$opened = @()
$index = 0
foreach ($zone in $presets[$Preset]) {
    $index += 1
    $profile = Join-Path $profileRoot ("{0}-{1}" -f $Preset, $index)
    New-Item -ItemType Directory -Force -Path (Join-Path $profile "Default") | Out-Null
    Write-Utf8NoBom (Join-Path $profile "First Run") ""
    $drawW = $zone.W
    $drawH = $zone.H
    if (($zone.X + $zone.W) -lt 3840) { $drawW += 8 }
    if (($zone.Y + $zone.H) -lt 1080) { $drawH += 8 }
    Write-Output "Opening $($zone.Title)"
    $argLine = "--user-data-dir=`"$profile`" --no-first-run --disable-fre --no-default-browser-check --disable-sync --hide-crash-restore-bubble --window-position=$($zone.X),$($zone.Y) --window-size=$drawW,$drawH --app=`"$HomeUrl`""
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $edge
    $startInfo.Arguments = $argLine
    $startInfo.UseShellExecute = $true
    $started = New-Object System.Diagnostics.Process
    $started.StartInfo = $startInfo
    [void]$started.Start()
    Add-Content -Path $pidFile -Value $started.Id -Encoding Ascii
    $windowProcess = Wait-ProfileWindow $profile 30
    if (-not $windowProcess) {
        Write-Output "No window for $($zone.Title)"
        continue
    }
    Add-Content -Path $pidFile -Value $windowProcess.Id -Encoding Ascii
    [void][PanelWin]::Place($windowProcess.MainWindowHandle, $zone.X, $zone.Y, $drawW, $drawH)
    $opened += [pscustomobject]@{ Profile = $profile; X = $zone.X; Y = $zone.Y; W = $drawW; H = $drawH }
    Write-Output "Placed $($zone.Title)"
}

if ($opened.Count -eq 0) { Write-Output "Opened 0 windows."; exit 1 }

Start-Sleep -Seconds 2
foreach ($item in ($opened | Sort-Object Y -Descending)) {
    $again = Find-ProfileWindow $item.Profile
    if ($again) {
        [void][PanelWin]::Place($again.MainWindowHandle, $item.X, $item.Y, $item.W, $item.H)
    }
}
Write-Output "Opened $($opened.Count) pages. No colored frames. Edge-Close.bat closes them."
exit 0
