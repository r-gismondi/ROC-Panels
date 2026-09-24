# Opens one borderless Microsoft Edge window per section on computer 192.168.0.102.
# The page fills the rectangle with no title bar and no gap between sections.
# F11 is not used: it would take a whole monitor and cover the other sections.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Independent", "DualFocus1", "DualFocus2", "DualFocus3", "Full")]
    [string]$Preset
)

$ErrorActionPreference = "Stop"

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
public struct PanelPoint {
    public int X;
    public int Y;
}
public static class PanelWin {
    const int GWL_STYLE = -16;
    const int GWL_EXSTYLE = -20;

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")]
    public static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out PanelRect lpRect);
    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out PanelRect lpRect);
    [DllImport("user32.dll")]
    public static extern bool ClientToScreen(IntPtr hWnd, ref PanelPoint lpPoint);
    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    static extern int GetWindowLong32(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    public static void MakeBorderless(IntPtr hwnd, int x, int y, int w, int h) {
        int style = GetWindowLong32(hwnd, GWL_STYLE);
        style &= ~0x00C00000; // caption
        style &= ~0x00040000; // thick frame
        style &= ~0x00080000; // sys menu
        style &= ~0x00020000; // minimize box
        style &= ~0x00010000; // maximize box
        style |= unchecked((int)0x80000000); // popup
        style |= 0x10000000; // visible
        SetWindowLong32(hwnd, GWL_STYLE, style);

        int ex = GetWindowLong32(hwnd, GWL_EXSTYLE);
        ex &= ~0x00000100;
        ex &= ~0x00000200;
        ex &= ~0x00000001;
        ex &= ~0x00020000;
        SetWindowLong32(hwnd, GWL_EXSTYLE, ex);

        int doNotRound = 1;
        DwmSetWindowAttribute(hwnd, 33, ref doNotRound, 4);
        int noFrame = 1;
        DwmSetWindowAttribute(hwnd, 2, ref noFrame, 4);
        int noBorder = unchecked((int)0xFFFFFFFE);
        DwmSetWindowAttribute(hwnd, 34, ref noBorder, 4);

        SetWindowPos(hwnd, new IntPtr(-1), x, y, w, h, 0x0020 | 0x0040);
    }

    public static void ClipInto(IntPtr child, IntPtr parent, int width, int height) {
        int style = GetWindowLong32(child, GWL_STYLE);
        style &= ~unchecked((int)0x80000000);
        style &= ~0x00C00000;
        style &= ~0x00040000;
        style |= 0x40000000;
        style |= 0x10000000;
        SetWindowLong32(child, GWL_STYLE, style);
        SetParent(child, parent);
        var origin = new PanelPoint();
        ClientToScreen(child, ref origin);
        PanelRect window;
        GetWindowRect(child, out window);
        int bar = origin.Y - window.Top;
        if (bar < 8) bar = 33;
        MoveWindow(child, -8, -bar - 8, width + 16, height + bar + 16, true);
    }
}
"@
}
[void][PanelWin]::SetProcessDPIAware()

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
    } catch {
    }
    $ErrorActionPreference = $previous
}

function Get-EdgeWindow([string]$Title) {
    return Get-Process -Name msedge -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "$Title*" } |
        Select-Object -First 1
}

function Wait-ProfileWindow([string]$Profile, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $procs = Get-CimInstance Win32_Process -Filter "Name = 'msedge.exe'" -ErrorAction SilentlyContinue
        foreach ($proc in @($procs)) {
            if ($proc.CommandLine -and $proc.CommandLine -like "*$Profile*") {
                $live = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
                if ($live -and $live.MainWindowHandle -ne 0 -and $live.MainWindowTitle) {
                    return $live
                }
            }
        }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

function Move-EdgeWindow([IntPtr]$Hwnd, [int]$X, [int]$Y, [int]$W, [int]$H) {
    if ($Hwnd -eq [IntPtr]::Zero) {
        return
    }
    $drawW = $W
    $drawH = $H
    if (($X + $W) -lt 3840) { $drawW += 2 }
    if (($Y + $H) -lt 1080) { $drawH += 2 }
    [void][PanelWin]::MakeBorderless($Hwnd, $X, $Y, $drawW, $drawH)
}

function Get-EdgeRectText([IntPtr]$Hwnd) {
    try {
        $rect = New-Object PanelRect
        $ok = [PanelWin]::GetWindowRect($Hwnd, [ref]$rect)
        if (-not $ok) {
            return "position unread"
        }
        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        return "$($rect.Left),$($rect.Top) ${width}x${height}"
    } catch {
        return "position unread"
    }
}

function Hold-EdgeWindow($Process, [string]$Title, [int]$X, [int]$Y, [int]$W, [int]$H, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if ($Title) {
            $hit = Get-EdgeWindow $Title
            if ($hit) { $Process = $hit }
        }
        if ($Process) {
            $Process.Refresh()
        }
        if ($Process -and $Process.MainWindowHandle -ne [IntPtr]::Zero) {
            Move-EdgeWindow $Process.MainWindowHandle $X $Y $W $H
        }
        Start-Sleep -Milliseconds 300
    }
    return $Process
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

Stop-LayoutEdge $root
Start-Sleep -Milliseconds 600

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
$pidFile = Join-Path $root "edge-layout.pids"
if (Test-Path -LiteralPath $pidFile) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

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

$placed = @()
$index = 0
foreach ($zone in $presets[$Preset]) {
    $index += 1
    $single = ($zone.Title -replace "`r?`n", " / ")
    $profile = Join-Path $profileRoot ("{0}-{1}" -f $Preset, $index)
    $defaultDir = Join-Path $profile "Default"
    New-Item -ItemType Directory -Force -Path $defaultDir | Out-Null
    Write-Utf8NoBom (Join-Path $profile "First Run") ""
    $right = $zone.X + $zone.W
    $bottom = $zone.Y + $zone.H
    $prefs = @"
{"browser":{"has_seen_welcome_page":true},"homepage":"https://ccv2.mtllc.us/landing","homepage_is_newtabpage":false,"session":{"restore_on_startup":4,"startup_urls":["https://ccv2.mtllc.us/landing"]},"distribution":{"skip_first_run_ui":true},"profile":{"exit_type":"Normal"}}
"@
    Write-Utf8NoBom (Join-Path $defaultDir "Preferences") $prefs

    $uri = "https://ccv2.mtllc.us/landing"
    Write-Output "Opening $single"
    $argLine = "--user-data-dir=`"$profile`" --no-first-run --disable-fre --no-default-browser-check --disable-sync --disable-extensions --hide-crash-restore-bubble --disable-session-crashed-bubble --disable-features=msEdgeStartupBoost --window-position=$($zone.X),$($zone.Y) --window-size=$($zone.W),$($zone.H) --app=`"$uri`""
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $edge
    $startInfo.Arguments = $argLine
    $startInfo.UseShellExecute = $true
    $started = New-Object System.Diagnostics.Process
    $started.StartInfo = $startInfo
    [void]$started.Start()
    Add-Content -Path $pidFile -Value $started.Id -Encoding Ascii

    $windowProcess = Wait-ProfileWindow $profile 25
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
    Start-Sleep -Seconds 2
    $windowProcess = Wait-ProfileWindow $profile 20
    if (-not $windowProcess) {
        Write-Output "Could not place $single. The page window did not appear."
        continue
    }
    $actual = Get-EdgeRectText $windowProcess.MainWindowHandle
    Write-Output "Placed $single at $actual"
    $placed += $profile
}

if ($placed.Count -eq 0) {
    Write-Output "Opened 0 Edge windows."
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$script:hosts = @()
$zones = @($presets[$Preset])
for ($i = 0; $i -lt $zones.Count; $i++) {
    $zone = $zones[$i]
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $drawW = $zone.W
    $drawH = $zone.H
    if (($zone.X + $zone.W) -lt 3840) { $drawW += 8 }
    if (($zone.Y + $zone.H) -lt 1080) { $drawH += 8 }
    $form.Bounds = New-Object System.Drawing.Rectangle $zone.X, $zone.Y, $drawW, $drawH
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($zone.Color)
    $form.TopMost = $false
    $form.ShowInTaskbar = $false
    $form.KeyPreview = $true
    $form.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            [System.Windows.Forms.Application]::Exit()
        }
    })
    $script:hosts += $form
}

$script:zones = $zones
$script:placed = $placed
function Update-Clips {
    for ($i = 0; $i -lt $script:zones.Count; $i++) {
        if ($i -ge $script:placed.Count) { continue }
        $found = Wait-ProfileWindow $script:placed[$i] 3
        if (-not $found) { continue }
        $drawW = $script:zones[$i].W
        $drawH = $script:zones[$i].H
        if (($script:zones[$i].X + $drawW) -lt 3840) { $drawW += 8 }
        if (($script:zones[$i].Y + $drawH) -lt 1080) { $drawH += 8 }
        [void][PanelWin]::MakeBorderless($found.MainWindowHandle, $script:zones[$i].X, $script:zones[$i].Y, $drawW, $drawH)
    }
}

Update-Clips
Add-Content -Path $pidFile -Value $PID -Encoding Ascii
Write-Output "Opened $($placed.Count) pages with no bars. Press Esc or run Edge-Close.bat."
[System.Windows.Forms.Application]::Run()
Stop-LayoutEdge $root
