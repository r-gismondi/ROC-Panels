# Opens the CCV2 landing page on computer 192.168.0.101.
# HDMI 1 is the left monitor and HDMI 2 is the right monitor.
# TV1-TV8. TV9-TV18 are not opened here.

param(
    [ValidateSet("Independent", "Split", "Focus", "FocusSplit", "Full")]
    [string]$Preset,
    [switch]$Close
)

$ErrorActionPreference = "Stop"
$HomeUrl = "https://ccv2.mtllc.us/landing"

if (-not ("PanelWin" -as [type])) {
    $panelDll = "C:\layouts\PanelWin.dll"
    if (-not (Test-Path -LiteralPath $panelDll)) {
        Add-Type -OutputAssembly $panelDll -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public struct PanelRect { public int Left; public int Top; public int Right; public int Bottom; }
public struct PanelPoint { public int X; public int Y; }
public static class PanelWin {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hwnd, string subApp, string subId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr child, string cls, string title);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out PanelRect lpRect);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out PanelRect lpRect);
    [StructLayout(LayoutKind.Sequential)]
    public struct PanelPlacement {
        public int length;
        public int flags;
        public int showCmd;
        public PanelPoint minPosition;
        public PanelPoint maxPosition;
        public PanelRect normalPosition;
    }
    [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr hWnd, ref PanelPlacement lpwndpl);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref PanelPoint lpPoint);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent, EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
    [DllImport("user32.dll")] public static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    public static void CloseWindow(IntPtr hwnd) { PostMessage(hwnd, 0x0010, IntPtr.Zero, IntPtr.Zero); }
    public static IntPtr[] VisibleWindows() {
        var found = new System.Collections.Generic.List<IntPtr>();
        EnumWindows((h, l) => { if (IsWindowVisible(h)) found.Add(h); return true; }, IntPtr.Zero);
        return found.ToArray();
    }
    public static string TextOf(IntPtr hwnd) {
        var buffer = new System.Text.StringBuilder(512);
        GetWindowText(hwnd, buffer, buffer.Capacity);
        return buffer.ToString();
    }
    public static uint PidOf(IntPtr hwnd) {
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        return pid;
    }
    [DllImport("user32.dll", EntryPoint = "GetWindowLong")] static extern int GetWindowLong32(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")] static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);
    public static bool IsWindow(IntPtr hwnd) {
        PanelRect window;
        return GetWindowRect(hwnd, out window);
    }
    public static string RectOf(IntPtr hwnd) {
        PanelRect window;
        if (!GetWindowRect(hwnd, out window)) return "unread";
        return window.Left + "," + window.Top + " " + (window.Right - window.Left) + "x" + (window.Bottom - window.Top);
    }
    public static IntPtr PageWidget(IntPtr hwnd) {
        IntPtr best = IntPtr.Zero;
        int bestArea = 0;
        EnumChildWindows(hwnd, (child, l) => {
            var name = new System.Text.StringBuilder(256);
            GetClassName(child, name, name.Capacity);
            if (name.ToString() == "Chrome_RenderWidgetHostHWND") {
                PanelRect widget;
                if (GetWindowRect(child, out widget)) {
                    int area = (widget.Right - widget.Left) * (widget.Bottom - widget.Top);
                    if (area > bestArea) {
                        bestArea = area;
                        best = child;
                    }
                }
            }
            return true;
        }, IntPtr.Zero);
        return best;
    }
    public static void Place(IntPtr hwnd, int x, int y, int w, int h) {
        ShowWindow(hwnd, 9);
        int ex = GetWindowLong32(hwnd, -20);
        if ((ex & 0x00000008) != 0) {
            ex &= ~0x00000008;
            SetWindowLong32(hwnd, -20, ex);
        }
        PanelRect window;
        GetWindowRect(hwnd, out window);
        int left = 0;
        int top = 0;
        int right = 0;
        int bottom = 0;
        IntPtr widget = PageWidget(hwnd);
        if (widget != IntPtr.Zero) {
            PanelRect page;
            GetWindowRect(widget, out page);
            left = page.Left - window.Left;
            top = page.Top - window.Top;
            right = window.Right - page.Right;
            bottom = window.Bottom - page.Bottom;
            if (left < 0) left = 0;
            if (top < 0) top = 0;
            if (right < 0) right = 0;
            if (bottom < 0) bottom = 0;
        } else {
            PanelPoint origin = new PanelPoint();
            ClientToScreen(hwnd, ref origin);
            top = origin.Y - window.Top + 48;
            left = 8;
            right = 8;
            bottom = 8;
            if (top < 48) top = 88;
        }
        if (h >= 1080) {
            SetWindowPos(hwnd, new IntPtr(-2), x, y, w, h, 0x0020 | 0x0040);
            return;
        }
        int posX = x - left;
        int posY = y - top;
        int posW = w + left + right;
        int posH = h + top + bottom;
        PanelPlacement placement = new PanelPlacement();
        placement.length = Marshal.SizeOf(typeof(PanelPlacement));
        placement.showCmd = 1;
        placement.normalPosition.Left = posX;
        placement.normalPosition.Top = posY;
        placement.normalPosition.Right = posX + posW;
        placement.normalPosition.Bottom = posY + posH;
        SetWindowPlacement(hwnd, ref placement);
        SetWindowPos(hwnd, new IntPtr(-2), posX, posY, posW, posH, 0x0020 | 0x0040);
        SetWindowRgn(hwnd, CreateRectRgn(left, top, left + w, top + h), true);
    }
    public static void PrepareHost(IntPtr host) {
        int style = GetWindowLong32(host, -16);
        style |= 0x02000000;
        SetWindowLong32(host, -16, style);
    }
    static void Measure(IntPtr hwnd, out int left, out int top, out int right, out int bottom) {
        left = 0;
        top = 0;
        right = 0;
        bottom = 0;
        PanelRect window;
        GetWindowRect(hwnd, out window);
        IntPtr widget = PageWidget(hwnd);
        if (widget != IntPtr.Zero) {
            PanelRect page;
            GetWindowRect(widget, out page);
            left = page.Left - window.Left;
            top = page.Top - window.Top;
            right = window.Right - page.Right;
            bottom = window.Bottom - page.Bottom;
            if (left < 0) left = 0;
            if (top < 0) top = 0;
            if (right < 0) right = 0;
            if (bottom < 0) bottom = 0;
        }
    }
    public static void Fit(IntPtr hwnd, IntPtr host, int x, int y, int w, int h) {
        int style = GetWindowLong32(hwnd, -16);
        bool alreadyChild = (style & 0x40000000) != 0;
        if (!alreadyChild) {
            SetWindowRgn(hwnd, IntPtr.Zero, false);
            style &= ~0x00C00000;
            style &= ~0x00040000;
            style &= ~0x00080000;
            style &= ~0x00020000;
            style &= ~0x00010000;
            style &= ~0x00800000;
            style |= 0x10000000;
            style &= ~unchecked((int)0x80000000);
            style |= 0x40000000;
            SetWindowLong32(hwnd, -16, style);
            SetParent(hwnd, host);
        }
        int left, top, right, bottom;
        Measure(hwnd, out left, out top, out right, out bottom);
        if (h >= 1080) {
            if (top < 40) top = 48;
            int childW = w + left + right;
            int childH = h + top + bottom;
            PanelRect hostRect;
            bool hostOk = GetWindowRect(host, out hostRect)
                && hostRect.Left == x && hostRect.Top == y
                && (hostRect.Right - hostRect.Left) == w
                && (hostRect.Bottom - hostRect.Top) == h;
            if (!hostOk) SetWindowPos(host, new IntPtr(-2), x, y, w, h, 0x0014);
            PanelRect window;
            int wantLeft = x - left;
            int wantTop = y - top;
            bool childOk = GetWindowRect(hwnd, out window)
                && window.Left == wantLeft && window.Top == wantTop
                && (window.Right - window.Left) == childW
                && (window.Bottom - window.Top) == childH;
            if (!childOk) MoveWindow(hwnd, -left, -top, childW, childH, true);
            return;
        }
        if (alreadyChild) return;
        if (top < 40) top = 40;
        int hostW = w + left + right;
        int hostH = h + top + bottom;
        SetWindowPos(host, new IntPtr(-2), x - left, y - top, hostW, hostH, 0x0040);
        SetWindowRgn(host, CreateRectRgn(left, top, left + w, top + h), true);
        MoveWindow(hwnd, 0, 0, hostW, hostH, true);
    }
}
"@
    }
    Add-Type -Path $panelDll
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

function Get-EdgeHwnds {
    $list = @()
    foreach ($hwnd in @([PanelWin]::VisibleWindows())) {
        $procId = [PanelWin]::PidOf($hwnd)
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        $title = [PanelWin]::TextOf($hwnd)
        if ($proc -and $proc.ProcessName -eq "msedge" -and $title) {
            $list += $hwnd
        }
    }
    return $list
}

function Close-RecordedWindows([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        $value = 0L
        if ([int64]::TryParse(([string]$line).Trim(), [ref]$value) -and $value -ne 0) {
            [void][PanelWin]::CloseWindow([IntPtr]$value)
        }
    }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$hwndFile = Join-Path $root "edge-layout.hwnds"
$hostPidFile = Join-Path $root "edge-host.pid"
function Stop-HostProcess([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $old = 0
    $text = (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ([int]::TryParse(([string]$text).Trim(), [ref]$old) -and $old -gt 0 -and $old -ne $PID) {
        Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}
function Stop-LayoutConsoles {
    $self = $PID
    $parent = 0
    $current = Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue
    if ($current) { $parent = [int]$current.ParentProcessId }
    $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -ne $self -and
        $_.ProcessId -ne $parent -and
        $_.Name -match '^(cmd|powershell|pwsh)\.exe$' -and
        $_.CommandLine -and
        $_.CommandLine -notlike '*Watch-Launch.ps1*' -and
        ($_.CommandLine -like '*\layouts\*' -or $_.CommandLine -like '*Show-Edge.ps1*')
    })
    foreach ($proc in $procs) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($parent -gt 0) {
        $parentProc = Get-CimInstance Win32_Process -Filter "ProcessId = $parent" -ErrorAction SilentlyContinue
        if ($parentProc -and $parentProc.CommandLine -like '*\layouts\*') {
            Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList "-NoProfile", "-Command", "Start-Sleep -Milliseconds 400; Stop-Process -Id $parent -Force -ErrorAction SilentlyContinue" | Out-Null
        }
    }
}
function Set-Taskbar([bool]$Visible) {
    foreach ($name in @("Shell_TrayWnd", "Shell_SecondaryTrayWnd")) {
        $tray = [PanelWin]::FindWindow($name, $null)
        if ($tray -ne [IntPtr]::Zero) { [void][PanelWin]::ShowWindow($tray, $(if ($Visible) { 5 } else { 0 })) }
    }
}
if ($Close) {
    Close-RecordedWindows $hwndFile
    Stop-HostProcess $hostPidFile
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Set-Taskbar $true
    Stop-LayoutConsoles
    exit 0
}
Stop-HostProcess $hostPidFile
if (-not $Preset) { Write-Error "Pick a preset."; exit 1 }

$edge = Find-Edge
if (-not $edge) { Write-Error "Microsoft Edge was not found."; exit 1 }

Stop-LayoutEdge $root
Close-RecordedWindows $hwndFile
Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 200
Set-Taskbar $false

function Zone($title, $x, $y, $w, $h) {
    [pscustomobject]@{ Title = $title; X = $x; Y = $y; W = $w; H = $h }
}

$presets = @{
    Independent = @(
        (Zone "TV5" 0    540 960  540)
        (Zone "TV6" 960  540 960  540)
        (Zone "TV7" 1920 540 960  540)
        (Zone "TV8" 2880 540 960  540)
        (Zone "TV1" 0    0   960  540)
        (Zone "TV2" 960  0   960  540)
        (Zone "TV3" 1920 0   960  540)
        (Zone "TV4" 2880 0   960  540)
    )
    Split = @(
        (Zone "TV1 TV2 TV5 TV6" 0 0 1920 1080)
        (Zone "TV3 TV4 TV7 TV8" 1920 0 1920 1080)
    )
    Focus = @(
        (Zone "TV1 TV5" 0 0 960 1080)
        (Zone "TV2 TV3 TV6 TV7" 960 0 1920 1080)
        (Zone "TV4 TV8" 2880 0 960 1080)
    )
    FocusSplit = @(
        (Zone "TV5" 0 540 960 540)
        (Zone "TV8" 2880 540 960 540)
        (Zone "TV2 TV3 TV6 TV7" 960 0 1920 1080)
        (Zone "TV1" 0 0 960 540)
        (Zone "TV4" 2880 0 960 540)
    )
    Full = @(
        (Zone "All" 0 0 3840 1080)
    )
}

$opened = @()
$known = @{}
foreach ($existing in @(Get-EdgeHwnds)) { $known[$existing.ToInt64()] = $true }
foreach ($zone in $presets[$Preset]) {
    $drawW = $zone.W
    $drawH = $zone.H
    if (($zone.X + $zone.W) -lt 3840) { $drawW += 2 }
    if ($zone.H -lt 1080 -and ($zone.Y + $zone.H) -lt 1080) { $drawH += 8 }
    elseif (($zone.Y + $zone.H) -lt 1080) { $drawH += 2 }
    Write-Output "Opening $($zone.Title)"
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $edge
    $startInfo.Arguments = "--disable-features=Windows10CustomTitlebar --app=`"$HomeUrl`" --new-window"
    $startInfo.UseShellExecute = $true
    $started = New-Object System.Diagnostics.Process
    $started.StartInfo = $startInfo
    [void]$started.Start()
    $hwnd = [IntPtr]::Zero
    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-Date) -lt $deadline -and $hwnd -eq [IntPtr]::Zero) {
        Start-Sleep -Milliseconds 300
        foreach ($candidate in @(Get-EdgeHwnds)) {
            if (-not $known.ContainsKey($candidate.ToInt64())) {
                $hwnd = $candidate
                $known[$candidate.ToInt64()] = $true
                break
            }
        }
    }
    if ($hwnd -eq [IntPtr]::Zero) {
        Write-Output "No window for $($zone.Title)"
        continue
    }
    [void][PanelWin]::Place($hwnd, $zone.X, $zone.Y, $drawW, $drawH)
    Add-Content -Path $hwndFile -Value $hwnd.ToInt64() -Encoding Ascii
    $opened += [pscustomobject]@{ Hwnd = $hwnd; X = $zone.X; Y = $zone.Y; W = $drawW; H = $drawH }
    Write-Output "Placed $($zone.Title)"
    Start-Sleep -Milliseconds 150
}

if ($opened.Count -eq 0) { Write-Output "Opened 0 windows."; exit 1 }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Set-Content -Path $hostPidFile -Value $PID
$script:hostsLeft = 0
foreach ($item in $opened) {
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.Location = New-Object System.Drawing.Point $item.X, $item.Y
    $form.ClientSize = New-Object System.Drawing.Size $item.W, $item.H
    $form.BackColor = [System.Drawing.Color]::Black
    $form.ShowInTaskbar = $false
    $form.TopMost = $false
    $form.Text = "Section"
    $form.Show()
    [void][PanelWin]::PrepareHost($form.Handle)
    [void][PanelWin]::Fit($item.Hwnd, $form.Handle, $item.X, $item.Y, $item.W, $item.H)
    $item | Add-Member -NotePropertyName Host -NotePropertyValue $form.Handle -Force
    $script:hostsLeft += 1
    $form.Add_FormClosed({
        $script:hostsLeft -= 1
        if ($script:hostsLeft -le 0) { [System.Windows.Forms.Application]::ExitThread() }
    })
}
$script:fitPasses = 0
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    $script:fitPasses += 1
    foreach ($item in $opened) {
        if ($item.H -ge 1080 -and [PanelWin]::IsWindow($item.Hwnd)) {
            [void][PanelWin]::Fit($item.Hwnd, $item.Host, $item.X, $item.Y, $item.W, $item.H)
        }
    }
    if ($script:fitPasses -ge 3) { $timer.Stop() }
})
$timer.Start()
Write-Output "Opened $($opened.Count) pages. Leave this window open. Edge-Close.bat closes them."
[System.Windows.Forms.Application]::Run()
exit 0
