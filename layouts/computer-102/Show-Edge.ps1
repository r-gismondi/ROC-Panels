# Opens one Microsoft Edge window per section on computer 192.168.0.102.
# Each window uses its own profile so an Edge already open on this PC is left alone.
# Outer window bounds match the colored layout test.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Independent", "DualFocus1", "DualFocus2", "DualFocus3", "Full")]
    [string]$Preset
)

$ErrorActionPreference = "Stop"

function Find-Edge {
    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $null
}

if (-not ("PanelWin" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct PanelRect {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
public static class PanelWin {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out PanelRect lpRect);
    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out PanelRect pvAttribute, int cbAttribute);
}
"@
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Stop-RecordedEdge([string]$PidFile) {
    if (-not (Test-Path -LiteralPath $PidFile)) {
        return
    }
    foreach ($line in @(Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue)) {
        $oldId = 0
        if (-not [int]::TryParse([string]$line.Trim(), [ref]$oldId)) {
            continue
        }
        if ($oldId -le 0) {
            continue
        }
        & taskkill.exe /PID $oldId /T /F 2>$null | Out-Null
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

function Set-ExactBounds([IntPtr]$Hwnd, [int]$X, [int]$Y, [int]$W, [int]$H) {
    [void][PanelWin]::ShowWindow($Hwnd, 9)
    [void][PanelWin]::SetWindowPos($Hwnd, [IntPtr]::Zero, $X, $Y, $W, $H, 0x0044)
    Start-Sleep -Milliseconds 200
    $window = New-Object PanelRect
    $visible = New-Object PanelRect
    $gotWindow = [PanelWin]::GetWindowRect($Hwnd, [ref]$window)
    $hr = [PanelWin]::DwmGetWindowAttribute($Hwnd, 9, [ref]$visible, 16)
    if ($gotWindow -and $hr -eq 0) {
        $padL = $visible.Left - $window.Left
        $padT = $visible.Top - $window.Top
        $padR = $window.Right - $visible.Right
        $padB = $window.Bottom - $visible.Bottom
        [void][PanelWin]::SetWindowPos(
            $Hwnd,
            [IntPtr]::Zero,
            ($X - $padL),
            ($Y - $padT),
            ($W + $padL + $padR),
            ($H + $padT + $padB),
            0x0044
        )
    }
}

function Wait-EdgeWindow([string]$Title, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $hit = Get-Process -Name msedge -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "$Title*" } |
            Select-Object -First 1
        if ($hit) {
            return $hit
        }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

$edge = Find-Edge
if (-not $edge) {
    Write-Error "Microsoft Edge was not found."
    exit 1
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$layoutPid = Join-Path $root "panel2-layout.pid"
if (Test-Path -LiteralPath $layoutPid) {
    $oldLayout = (Get-Content -LiteralPath $layoutPid -ErrorAction SilentlyContinue | Select-Object -First 1)
    $layoutId = 0
    if ([int]::TryParse(([string]$oldLayout).Trim(), [ref]$layoutId) -and $layoutId -gt 0) {
        Stop-Process -Id $layoutId -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $layoutPid -Force -ErrorAction SilentlyContinue
}

$pidFile = Join-Path $root "edge-layout.pids"
Stop-RecordedEdge $pidFile
Start-Sleep -Milliseconds 400

$profileRoot = Join-Path $root "edge-profiles"
for ($try = 0; $try -lt 5; $try++) {
    if (-not (Test-Path -LiteralPath $profileRoot)) {
        break
    }
    Remove-Item -LiteralPath $profileRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $profileRoot) {
        Start-Sleep -Milliseconds 400
    }
}
$pageRoot = Join-Path $root "pages"
New-Item -ItemType Directory -Force -Path $pageRoot | Out-Null

function Zone($title, $x, $y, $w, $h, $color) {
    [pscustomobject]@{ Title = $title; X = $x; Y = $y; W = $w; H = $h; Color = $color }
}

$presets = @{
    Independent = @(
        (Zone "TV9"  0    0   960  540 "#1a6cff")
        (Zone "TV10" 960  0   960  540 "#12c2a3")
        (Zone "TV14" 0    540 960  540 "#7a5cff")
        (Zone "TV15" 960  540 960  540 "#d06bff")
        (Zone "TV11" 1920 0   960  540 "#f0a202")
        (Zone "TV12" 2880 0   960  540 "#3ec8ff")
        (Zone "TV16" 1920 540 960  540 "#ff6b8a")
        (Zone "TV17" 2880 540 960  540 "#9be36a")
    )
    DualFocus1 = @(
        (Zone "TV9  TV10`nTV14 TV15" 0    0 1920 1080 "#1a6cff")
        (Zone "TV11`nTV16"           1920 0 960  1080 "#f0a202")
        (Zone "TV12`nTV17"           2880 0 960  1080 "#12c2a3")
    )
    DualFocus2 = @(
        (Zone "TV9  TV10`nTV14 TV15" 0    0 1920 1080 "#1a6cff")
        (Zone "TV11 TV12`nTV16 TV17" 1920 0 1920 1080 "#f0a202")
    )
    DualFocus3 = @(
        (Zone "TV9`nTV14"            0    0 960  1080 "#1a6cff")
        (Zone "TV10 TV11`nTV15 TV16" 960  0 1920 1080 "#f0a202")
        (Zone "TV12`nTV17"           2880 0 960  1080 "#12c2a3")
    )
    Full = @(
        (Zone "TV9 TV10 TV11 TV12`nTV14 TV15 TV16 TV17" 0 0 3840 1080 "#1a6cff")
    )
}

$index = 0
$opened = 0
foreach ($zone in $presets[$Preset]) {
    $index += 1
    $single = ($zone.Title -replace "`r?`n", " / ")
    $htmlTitle = "$single Edge"
    $heading = ($zone.Title -replace "`r?`n", "<br>")
    $htmlPath = Join-Path $pageRoot ("{0}-{1}.html" -f $Preset, $index)
    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>$htmlTitle</title>
<style>
  html, body { margin: 0; height: 100%; background: $($zone.Color); color: #fff; font-family: "Segoe UI", sans-serif; }
  body { display: flex; align-items: center; justify-content: center; text-align: center; }
  h1 { font-size: 56px; line-height: 1.1; margin: 0 0 12px; }
  p { font-size: 28px; margin: 6px 0; }
</style>
</head>
<body>
  <div>
    <h1>$heading</h1>
    <p>Microsoft Edge</p>
    <p>$($zone.X), $($zone.Y)</p>
    <p>$($zone.W) x $($zone.H)</p>
  </div>
</body>
</html>
"@
    Write-Utf8NoBom $htmlPath $html

    $profile = Join-Path $profileRoot ("{0}-{1}" -f $Preset, $index)
    $defaultDir = Join-Path $profile "Default"
    New-Item -ItemType Directory -Force -Path $defaultDir | Out-Null
    Write-Utf8NoBom (Join-Path $profile "First Run") ""
    $prefs = '{"browser":{"has_seen_welcome_page":true},"distribution":{"skip_first_run_ui":true},"profile":{"exit_type":"Normal"},"session":{"restore_on_startup":5}}'
    Write-Utf8NoBom (Join-Path $defaultDir "Preferences") $prefs

    $uri = ([Uri]$htmlPath).AbsoluteUri
    Write-Output "Opening $single at $($zone.X),$($zone.Y) $($zone.W)x$($zone.H)"
    $argLine = "--user-data-dir=`"$profile`" --no-first-run --disable-fre --no-default-browser-check --disable-sync --disable-extensions --hide-crash-restore-bubble --disable-session-crashed-bubble --new-window --window-position=$($zone.X),$($zone.Y) --window-size=$($zone.W),$($zone.H) `"$uri`""
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $edge
    $startInfo.Arguments = $argLine
    $startInfo.UseShellExecute = $true
    $started = New-Object System.Diagnostics.Process
    $started.StartInfo = $startInfo
    [void]$started.Start()
    Add-Content -Path $pidFile -Value $started.Id -Encoding Ascii

    $windowProcess = Wait-EdgeWindow $htmlTitle 20
    if (-not $windowProcess) {
        $started.Refresh()
        if ($started.MainWindowHandle -ne [IntPtr]::Zero) {
            $windowProcess = $started
        }
    }
    if (-not $windowProcess) {
        Write-Output "Could not place $single. The Edge window did not appear."
        continue
    }
    Add-Content -Path $pidFile -Value $windowProcess.Id -Encoding Ascii
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $windowProcess.Refresh()
        if ($windowProcess.MainWindowHandle -ne [IntPtr]::Zero) {
            Set-ExactBounds $windowProcess.MainWindowHandle $zone.X $zone.Y $zone.W $zone.H
        }
        Start-Sleep -Milliseconds 350
    }
    Write-Output "Placed $single"
    $opened += 1
}

Write-Output "Opened $opened Edge window(s). Edge-Close.bat closes only these test windows."
if ($opened -eq 0) {
    exit 1
}
exit 0
