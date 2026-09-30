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
$LayoutScreens = @("TV1", "TV2", "TV3", "TV4", "TV5", "TV6", "TV7", "TV8")

if (-not ("PanelWin" -as [type])) {
    $panelDll = "C:\layouts\PanelWin3.dll"
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
        SetWindowPos(hwnd, new IntPtr(-2), x, y, w, h, 0x0020 | 0x0040);
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
        if (top < 8) top = 48;
        int childW = w + left + right;
        int spill = bottom;
        if (y + h < 1080) spill = 0;
        int childH = h + top + spill;
        SetWindowRgn(host, IntPtr.Zero, false);
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

function Get-ZoneUrl([string]$Title) {
    if (-not $root) { return $HomeUrl }
    $dir = Join-Path $root "addresses"
    $names = @($Title -split '\s+' | Where-Object { $_ -and $_ -ne "All" })
    if ($Title -eq "All" -and $LayoutScreens) { $names = @($LayoutScreens) }
    $best = ""
    $bestTime = [datetime]::MinValue
    foreach ($name in $names) {
        $file = Join-Path $dir "$name.txt"
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $item = Get-Item -LiteralPath $file
        if ($item.LastWriteTime -lt $bestTime) { continue }
        $text = ""
        try { $text = ([System.IO.File]::ReadAllText($file)).Trim() } catch { continue }
        if ($text -match '^https?://\S+$') {
            $best = $text
            $bestTime = $item.LastWriteTime
        }
    }
    if ($best) { return $best }
    return $HomeUrl
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
        $_.CommandLine -notlike '*Capture-Thumbs.ps1*' -and
        $_.CommandLine -notlike '*Start-Thumbs.bat*' -and
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
    Write-Output "Opening $($zone.Title)"
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $edge
    $zoneUrl = Get-ZoneUrl $zone.Title
    $startInfo.Arguments = "--disable-features=Windows10CustomTitlebar --remote-debugging-port=9333 --remote-allow-origins=* --app=`"$zoneUrl`" --new-window"
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
    $opened += [pscustomobject]@{ Title = $zone.Title; Hwnd = $hwnd; X = $zone.X; Y = $zone.Y; W = $drawW; H = $drawH; Kind = "edge" }
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
if (-not ("PanelDesktop" -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class PanelDesktop {
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
    public static bool Covers(int x, int y, int w, int h) {
        int left = GetSystemMetrics(76);
        int top = GetSystemMetrics(77);
        int right = left + GetSystemMetrics(78);
        int bottom = top + GetSystemMetrics(79);
        return x >= left && y >= top && x + w <= right && y + h <= bottom;
    }
}
'@
}
function Test-HostHome($item) {
    $text = [PanelWin]::RectOf($item.Host)
    if ($text -eq "unread") { return $false }
    $parts = @($text -split '[ ,x]')
    if ($parts.Count -lt 4) { return $false }
    $dx = [Math]::Abs([int]$parts[0] - $item.X)
    $dy = [Math]::Abs([int]$parts[1] - $item.Y)
    $dw = [Math]::Abs([int]$parts[2] - $item.W)
    $dh = [Math]::Abs([int]$parts[3] - $item.H)
    return ($dx -le 8) -and ($dy -le 8) -and ($dw -le 8) -and ($dh -le 8)
}
function Test-AppHome($item) {
    $text = [PanelWin]::RectOf($item.Hwnd)
    if ($text -eq "unread") { return $false }
    $parts = @($text -split '[ ,x]')
    if ($parts.Count -lt 4) { return $false }
    $dx = [Math]::Abs([int]$parts[0] - $item.X)
    $dy = [Math]::Abs([int]$parts[1] - $item.Y)
    $dw = [Math]::Abs([int]$parts[2] - $item.W)
    $dh = [Math]::Abs([int]$parts[3] - $item.H)
    return ($dx -le 8) -and ($dy -le 8) -and ($dw -le 8) -and ($dh -le 8)
}
function Test-LayoutDesktop {
    foreach ($item in $opened) {
        if (-not [PanelDesktop]::Covers($item.X, $item.Y, $item.W, $item.H)) { return $false }
    }
    return $true
}
$script:fitPasses = 0
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    $script:fitPasses += 1
    # While a monitor is off, Windows parks its windows on a screen that is still on.
    # Leave them there until every tile is on a connected display again, then put them back.
    $ready = Test-LayoutDesktop
    foreach ($item in $opened) {
        if ($item.Kind -ne "app") { continue }
        if (-not [PanelWin]::IsWindow($item.Hwnd)) { continue }
        [void][PanelWin]::ShowWindow($item.Host, 0)
        if ($script:fitPasses -le 3 -or $ready) {
            if (-not (Test-AppHome $item)) { [void][PanelWin]::Place($item.Hwnd, $item.X, $item.Y, $item.W, $item.H) }
        }
    }
    $needsRestore = $false
    if ($script:fitPasses -gt 3) {
        if (-not $ready) { return }
        foreach ($item in $opened) {
            if ($item.Kind -eq "app") { continue }
            if (-not (Test-HostHome $item)) { $needsRestore = $true; break }
        }
        if (-not $needsRestore) { return }
    }
    foreach ($item in $opened) {
        if ($item.Kind -eq "app") { continue }
        if (-not [PanelWin]::IsWindow($item.Hwnd)) { continue }
        if ($needsRestore) { [void][PanelWin]::ShowWindow($item.Host, 9) }
        [void][PanelWin]::Fit($item.Hwnd, $item.Host, $item.X, $item.Y, $item.W, $item.H)
    }
})
$timer.Start()
$script:urlBusy = $false
function New-CdpTimeout([int]$Milliseconds) {
    $source = New-Object System.Threading.CancellationTokenSource
    $source.CancelAfter($Milliseconds)
    return $source
}
function Send-CdpMessage($Socket, [string]$Payload) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
    $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (, $bytes)
    $cancel = New-CdpTimeout 1500
    try {
        $null = $Socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cancel.Token).GetAwaiter().GetResult()
    } finally { $cancel.Dispose() }
}
function Receive-CdpMessage($Socket) {
    $buffer = New-Object byte[] 131072
    $stream = New-Object System.IO.MemoryStream
    $cancel = New-CdpTimeout 1500
    try {
        do {
            $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (, $buffer)
            $result = $Socket.ReceiveAsync($segment, $cancel.Token).GetAwaiter().GetResult()
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { break }
            if ($result.Count -gt 0) { [void]$stream.Write($buffer, 0, $result.Count) }
        } while (-not $result.EndOfMessage)
        return [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
    } finally { $cancel.Dispose() }
}
function Open-CdpSocket([string]$Url) {
    $socket = New-Object System.Net.WebSockets.ClientWebSocket
    $cancel = New-CdpTimeout 1500
    try {
        $socket.ConnectAsync([Uri]$Url, $cancel.Token).GetAwaiter().GetResult() | Out-Null
        return $socket
    } catch {
        try { $socket.Dispose() } catch {}
        throw
    } finally { $cancel.Dispose() }
}
function Invoke-Cdp($Socket, [int]$Id, [string]$Method, $Params) {
    $body = @{ id = $Id; method = $Method }
    if ($null -ne $Params) { $body.params = $Params }
    Send-CdpMessage $Socket ($body | ConvertTo-Json -Compress -Depth 6)
    $deadline = (Get-Date).AddSeconds(2)
    while ((Get-Date) -lt $deadline) {
        $text = Receive-CdpMessage $Socket
        if (-not $text) { continue }
        $message = $text | ConvertFrom-Json
        if ($message.id -eq $Id) { return $message }
    }
    return $null
}
function Find-ZonePage($Hwnd) {
    $text = [PanelWin]::RectOf($Hwnd)
    if ($text -notmatch '^(-?\d+),(-?\d+)\s+(\d+)x(\d+)$') { return $null }
    $left = [int]$Matches[1]
    $top = [int]$Matches[2]
    $width = [int]$Matches[3]
    $height = [int]$Matches[4]
    try {
        $version = Invoke-RestMethod -Uri 'http://127.0.0.1:9333/json/version' -TimeoutSec 2
        $list = @(Invoke-RestMethod -Uri 'http://127.0.0.1:9333/json/list' -TimeoutSec 2)
    } catch { return $null }
    $socket = $null
    try {
        $socket = Open-CdpSocket $version.webSocketDebuggerUrl
        $id = 1
        $hits = @()
        $searchDeadline = (Get-Date).AddSeconds(4)
        foreach ($target in $list) {
            if ((Get-Date) -gt $searchDeadline) { break }
            if ($target.type -ne 'page' -or $target.url -like 'devtools://*') { continue }
            $id++
            $reply = Invoke-Cdp $socket $id 'Browser.getWindowForTarget' @{ targetId = [string]$target.id }
            if (-not $reply -or -not $reply.result) { continue }
            $bounds = $reply.result.bounds
            if (-not $bounds) { continue }
            $close = [Math]::Abs([double]$bounds.left - $left) -le 48 -and [Math]::Abs([double]$bounds.top - $top) -le 48 -and [Math]::Abs([double]$bounds.width - $width) -le 64 -and [Math]::Abs([double]$bounds.height - $height) -le 64
            if ($close) { $hits += $target }
        }
        if ($hits.Count -eq 1) { return $hits[0] }
    } catch {
        return $null
    } finally {
        if ($socket) { try { $socket.Dispose() } catch {} }
    }
    return $null
}
function Open-ZonePage($Target, [string]$Url) {
    $socket = $null
    try {
        $socket = Open-CdpSocket $Target.webSocketDebuggerUrl
        $reply = Invoke-Cdp $socket 1 'Page.navigate' @{ url = $Url }
        if (-not $reply -or $reply.error) { return $false }
        return $true
    } catch {
        return $false
    } finally {
        if ($socket) { try { $socket.Dispose() } catch {} }
    }
}
function Start-ZoneEdge([string]$Url, [string]$Screen) {
    $seen = @{}
    foreach ($existing in @([PanelWin]::VisibleWindows())) { $seen[$existing.ToInt64()] = $true }
    foreach ($existing in @($known.Keys)) { $seen[[int64]$existing] = $true }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $edge
    $startInfo.Arguments = "--disable-features=Windows10CustomTitlebar --remote-debugging-port=9333 --remote-allow-origins=* --app=`"$Url`" --new-window"
    $startInfo.UseShellExecute = $true
    $started = New-Object System.Diagnostics.Process
    $started.StartInfo = $startInfo
    [void]$started.Start()
    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
        foreach ($candidate in @([PanelWin]::VisibleWindows())) {
            if ($seen.ContainsKey($candidate.ToInt64())) { continue }
            $procId = [int][PanelWin]::PidOf($candidate)
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $procId" -ErrorAction SilentlyContinue
            if (-not $proc -or $proc.Name -ne 'msedge.exe') { continue }
            if (-not [PanelWin]::TextOf($candidate)) { continue }
            return $candidate
        }
    }
    return [IntPtr]::Zero
}
New-Item -ItemType Directory -Force -Path (Join-Path $root "url-requests") | Out-Null
$urlTimer = New-Object System.Windows.Forms.Timer
$urlTimer.Interval = 200
$urlTimer.Add_Tick({
    if ($script:urlBusy) { return }
    try {
        $dir = Join-Path $root "url-requests"
        $pending = @(Get-ChildItem -LiteralPath $dir -Filter *.txt -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($pending.Count -eq 0) { return }
        $request = $pending[0]
        $screen = [System.IO.Path]::GetFileNameWithoutExtension($request.Name)
        $resultDir = Join-Path $root "url-results"
        New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
        $resultPath = Join-Path $resultDir ($screen + ".txt")
        $url = ""
        try { $url = ([System.IO.File]::ReadAllText($request.FullName)).Trim() } catch { return }
        Remove-Item -LiteralPath $request.FullName -Force -ErrorAction SilentlyContinue
        $script:urlBusy = $true
        $utf8 = New-Object System.Text.UTF8Encoding $false
        try {
            $validScreen = $screen -match '^TV([1-9]|1[0-8])$'
            $validUrl = ($url.StartsWith("http://") -or $url.StartsWith("https://")) -and $url.Length -le 2000 -and $url -notmatch '[\s''"<>\\]'
            if (-not $validScreen) {
                [System.IO.File]::WriteAllText($resultPath, "error That screen is not in this layout.", $utf8)
                return
            }
            if (-not $validUrl) {
                [System.IO.File]::WriteAllText($resultPath, "error Use an http or https address.", $utf8)
                return
            }
            $match = $null
            foreach ($item in $opened) {
                $names = @($item.Title -split '\s+')
                if ($item.Title -eq "All" -or ($names -contains $screen)) {
                    $match = $item
                    break
                }
            }
            if (-not $match) {
                [System.IO.File]::WriteAllText($resultPath, "error That screen is not open in this layout.", $utf8)
                return
            }
            [System.IO.File]::WriteAllText($resultPath, "working", $utf8)
            $page = $null
            if ($match.Kind -eq "edge" -and $match.Hwnd -and $match.Hwnd -ne [IntPtr]::Zero) { $page = Find-ZonePage $match.Hwnd }
            $openedPage = $page -and (Open-ZonePage $page $url)
            if (-not $openedPage) {
                $hwnd = Start-ZoneEdge $url $screen
                if ($hwnd -eq [IntPtr]::Zero) {
                    [System.IO.File]::WriteAllText($resultPath, "error Edge did not open that address.", $utf8)
                    return
                }
                $match.Kind = "edge"
                [void][PanelWin]::ShowWindow($match.Host, 9)
                [void][PanelWin]::Place($hwnd, $match.X, $match.Y, $match.W, $match.H)
                [void][PanelWin]::Fit($hwnd, $match.Host, $match.X, $match.Y, $match.W, $match.H)
                if ($match.Hwnd -and $match.Hwnd -ne [IntPtr]::Zero) {
                    [void][PanelWin]::CloseWindow($match.Hwnd)
                    [void]$known.Remove($match.Hwnd.ToInt64())
                }
                $match.Hwnd = $hwnd
                $known[$hwnd.ToInt64()] = $true
            }
            $ids = foreach ($item in $opened) { if ($item.Hwnd -and $item.Hwnd -ne [IntPtr]::Zero) { $item.Hwnd.ToInt64().ToString() } }
            Set-Content -LiteralPath $hwndFile -Value $ids -Encoding Ascii
            $saveDir = Join-Path $root "addresses"
            New-Item -ItemType Directory -Force -Path $saveDir | Out-Null
            $saveNames = @($match.Title -split '\s+' | Where-Object { $_ -and $_ -ne "All" })
            if ($saveNames -notcontains $screen) { $saveNames += $screen }
            if ($match.Title -eq "All" -and $LayoutScreens) { $saveNames = @($LayoutScreens) }
            foreach ($name in $saveNames) {
                [System.IO.File]::WriteAllText((Join-Path $saveDir ($name + ".txt")), $url, $utf8)
            }
            [System.IO.File]::WriteAllText($resultPath, "ok", $utf8)
        } catch {
            $reason = $_.Exception.Message
            if (-not $reason) { $reason = "The address did not open." }
            $reason = ($reason -replace '[\r\n]+', ' ')
            [System.IO.File]::WriteAllText($resultPath, "error $reason", $utf8)
        } finally {
            $script:urlBusy = $false
        }
    } catch {}
})
$urlTimer.Start()
function Get-ProcessTree([int]$Root) {
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $ids = @{}
    $ids[$Root] = $true
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($proc in $all) {
            $procId = [int]$proc.ProcessId
            $parent = [int]$proc.ParentProcessId
            if ($ids.ContainsKey($parent) -and -not $ids.ContainsKey($procId)) {
                $ids[$procId] = $true
                $changed = $true
            }
        }
    }
    return $ids
}
function Wait-AppWindow($Started) {
    $seen = @{}
    foreach ($existing in @([PanelWin]::VisibleWindows())) { $seen[$existing.ToInt64()] = $true }
    $deadline = (Get-Date).AddSeconds(25)
    $fallbackAfter = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
        $tree = Get-ProcessTree $Started.Id
        try { $Started.Refresh() } catch {}
        $owned = [IntPtr]::Zero
        foreach ($candidate in @([PanelWin]::VisibleWindows())) {
            $procId = [int][PanelWin]::PidOf($candidate)
            if (-not $tree.ContainsKey($procId)) { continue }
            if (-not [PanelWin]::TextOf($candidate)) { continue }
            if (-not $seen.ContainsKey($candidate.ToInt64())) { return $candidate }
            if ($owned -eq [IntPtr]::Zero) { $owned = $candidate }
        }
        if ($Started.MainWindowHandle -ne [IntPtr]::Zero) {
            $handle = $Started.MainWindowHandle
            if (-not $seen.ContainsKey($handle.ToInt64())) { return $handle }
            if ((Get-Date) -gt $fallbackAfter) { return $handle }
        }
        if ((Get-Date) -gt $fallbackAfter -and $owned -ne [IntPtr]::Zero) { return $owned }
    }
    return [IntPtr]::Zero
}
function Save-ZoneHwnds {
    $ids = foreach ($item in $opened) { if ($item.Hwnd -and $item.Hwnd -ne [IntPtr]::Zero) { $item.Hwnd.ToInt64().ToString() } }
    Set-Content -LiteralPath $hwndFile -Value $ids -Encoding Ascii
}
New-Item -ItemType Directory -Force -Path (Join-Path $root "app-requests") | Out-Null
$appTimer = New-Object System.Windows.Forms.Timer
$appTimer.Interval = 200
$appTimer.Add_Tick({
    if ($script:urlBusy) { return }
    try {
        $dir = Join-Path $root "app-requests"
        $pending = @(Get-ChildItem -LiteralPath $dir -Filter *.txt -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($pending.Count -eq 0) { return }
        $request = $pending[0]
        $screen = [System.IO.Path]::GetFileNameWithoutExtension($request.Name)
        $resultDir = Join-Path $root "app-results"
        New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
        $resultPath = Join-Path $resultDir ($screen + ".txt")
        $exe = ""
        try { $exe = ([System.IO.File]::ReadAllText($request.FullName)).Trim() } catch { return }
        Remove-Item -LiteralPath $request.FullName -Force -ErrorAction SilentlyContinue
        $script:urlBusy = $true
        $utf8 = New-Object System.Text.UTF8Encoding $false
        try {
            $validScreen = $screen -match '^TV([1-9]|1[0-8])$'
            $validExe = $exe -match '^[A-Za-z]:\\[^<>:"|?*\r\n]+\.exe$' -and (Test-Path -LiteralPath $exe)
            if (-not $validScreen) {
                [System.IO.File]::WriteAllText($resultPath, "error That screen is not in this layout.", $utf8)
                return
            }
            if (-not $validExe) {
                [System.IO.File]::WriteAllText($resultPath, "error That program was not found.", $utf8)
                return
            }
            $match = $null
            foreach ($item in $opened) {
                $names = @($item.Title -split '\s+')
                if ($item.Title -eq "All" -or ($names -contains $screen)) {
                    $match = $item
                    break
                }
            }
            if (-not $match) {
                [System.IO.File]::WriteAllText($resultPath, "error That screen is not open in this layout.", $utf8)
                return
            }
            [System.IO.File]::WriteAllText($resultPath, "working", $utf8)
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $exe
            $startInfo.WorkingDirectory = Split-Path -Parent $exe
            $startInfo.UseShellExecute = $true
            $started = New-Object System.Diagnostics.Process
            $started.StartInfo = $startInfo
            [void]$started.Start()
            $hwnd = Wait-AppWindow $started
            if ($hwnd -eq [IntPtr]::Zero) {
                [System.IO.File]::WriteAllText($resultPath, "error The program did not open a window.", $utf8)
                return
            }
            [void][PanelWin]::ShowWindow($match.Host, 0)
            [void][PanelWin]::Place($hwnd, $match.X, $match.Y, $match.W, $match.H)
            if ($match.Hwnd -and $match.Hwnd -ne [IntPtr]::Zero) {
                [void][PanelWin]::CloseWindow($match.Hwnd)
                [void]$known.Remove($match.Hwnd.ToInt64())
            }
            $match.Hwnd = $hwnd
            $match.Kind = "app"
            $known[$hwnd.ToInt64()] = $true
            Save-ZoneHwnds
            [System.IO.File]::WriteAllText($resultPath, "ok", $utf8)
        } catch {
            $reason = $_.Exception.Message
            if (-not $reason) { $reason = "The program did not open." }
            $reason = ($reason -replace '[\r\n]+', ' ')
            [System.IO.File]::WriteAllText($resultPath, "error $reason", $utf8)
        } finally {
            $script:urlBusy = $false
        }
    } catch {}
})
$appTimer.Start()
function Close-OpenedZone($Item) {
    if ($Item.Hwnd -and $Item.Hwnd -ne [IntPtr]::Zero) {
        try { [void][PanelWin]::CloseWindow($Item.Hwnd) } catch {}
        try { [void]$known.Remove($Item.Hwnd.ToInt64()) } catch {}
    }
    $Item.Hwnd = [IntPtr]::Zero
    $Item.Kind = "empty"
    try { if ($Item.Host -and $Item.Host -ne [IntPtr]::Zero) { [void][PanelWin]::ShowWindow($Item.Host, 5) } } catch {}
    Save-ZoneHwnds
}
New-Item -ItemType Directory -Force -Path (Join-Path $root "close-requests") | Out-Null
$closeTimer = New-Object System.Windows.Forms.Timer
$closeTimer.Interval = 200
$closeTimer.Add_Tick({
    if ($script:urlBusy) { return }
    try {
        $dir = Join-Path $root "close-requests"
        $pending = @(Get-ChildItem -LiteralPath $dir -Filter *.txt -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($pending.Count -eq 0) { return }
        $request = $pending[0]
        $screen = [System.IO.Path]::GetFileNameWithoutExtension($request.Name)
        $resultDir = Join-Path $root "close-results"
        New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
        $resultPath = Join-Path $resultDir ($screen + ".txt")
        Remove-Item -LiteralPath $request.FullName -Force -ErrorAction SilentlyContinue
        $script:urlBusy = $true
        $utf8 = New-Object System.Text.UTF8Encoding $false
        try {
            $validScreen = $screen -match '^TV([1-9]|1[0-8])$'
            if (-not $validScreen) {
                [System.IO.File]::WriteAllText($resultPath, "error That screen is not in this layout.", $utf8)
                return
            }
            $match = $null
            foreach ($item in @($script:opened)) {
                $names = @($item.Title -split '\s+')
                if ($item.Title -eq "All" -or ($names -contains $screen)) {
                    $match = $item
                    break
                }
            }
            if (-not $match) {
                [System.IO.File]::WriteAllText($resultPath, "error That screen is not open in this layout.", $utf8)
                return
            }
            [System.IO.File]::WriteAllText($resultPath, "ok", $utf8)
            Close-OpenedZone $match
        } catch {
            $reason = $_.Exception.Message
            if (-not $reason) { $reason = "Edge did not close." }
            $reason = ($reason -replace '[\r\n]+', ' ')
            [System.IO.File]::WriteAllText($resultPath, "error $reason", $utf8)
        } finally {
            $script:urlBusy = $false
        }
    } catch {}
})
$closeTimer.Start()
Write-Output "Opened $($opened.Count) pages. Leave this window open. Edge-Close.bat closes them."
[System.Windows.Forms.Application]::Run()
exit 0
