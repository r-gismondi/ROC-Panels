# Opens one Chrome Remote Desktop session in Edge, in Full mode and Tabbed mode.
# The session is brought in front of the console and stretched over the whole screen,
# so the console caption buttons cannot show around it.
# The X on the Tabbed mode bar only hides the bar, so an X that disconnects is kept on top of it.
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Url
)

$ErrorActionPreference = "Stop"
$sessionPattern = '^https://remotedesktop\.google\.com/access/session/[0-9a-fA-F-]+$'
if ($Url -notmatch $sessionPattern) { exit 1 }

New-Item -ItemType Directory -Force -Path "C:\layouts" | Out-Null
$requestPath = "C:\layouts\remote-session.request"
$logPath = "C:\layouts\remote-session.log"

$mutex = New-Object System.Threading.Mutex($false, "WallRemoteSession")
$ownsMutex = $false
try {
    $ownsMutex = $mutex.WaitOne(0)
} catch {
    $ownsMutex = $true
}
if (-not $ownsMutex) {
    [System.IO.File]::WriteAllText($requestPath, ($Name + "`t" + $Url))
    exit 0
}

function Write-Log([string]$Text) {
    try { Add-Content -LiteralPath $logPath -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $Text) -Encoding utf8 } catch {}
}

try {
try { Set-Content -LiteralPath $logPath -Value "" -Encoding utf8 } catch {}
if (Test-Path -LiteralPath $requestPath) { Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class RemoteWin {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    public delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct KBDLLHOOKSTRUCT {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId")] static extern uint WindowThread(IntPtr hWnd, IntPtr processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] static extern void SwitchToThisWindow(IntPtr hWnd, bool fAltTab);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string lpModuleName);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    const int GWL_STYLE = -16;
    const int GWL_EXSTYLE = -20;
    const int WS_CAPTION = 0x00C00000;
    const int WS_THICKFRAME = 0x00040000;
    const int WS_MINIMIZEBOX = 0x00020000;
    const int WS_MAXIMIZEBOX = 0x00010000;
    const int WS_SYSMENU = 0x00080000;
    const int WS_BORDER = 0x00800000;
    const int WS_EX_DLGMODALFRAME = 0x00000001;
    const int WS_EX_WINDOWEDGE = 0x00000100;
    const int WS_EX_CLIENTEDGE = 0x00000200;
    const int WS_EX_STATICEDGE = 0x00020000;
    const uint SWP_NOSIZE = 0x0001;
    const uint SWP_NOMOVE = 0x0002;
    const uint SWP_NOACTIVATE = 0x0010;
    const uint SWP_FRAMECHANGED = 0x0020;
    const uint SWP_SHOWWINDOW = 0x0040;
    const byte VK_MENU = 0x12;
    const uint KEYEVENTF_KEYUP = 0x0002;
    static EnumProc _keep;
    static bool _unlocked;
    static HookProc _hookProc;
    static IntPtr _hook;
    static IntPtr _lockWindow;

    public static List<string> EdgeWindows() {
        var list = new List<string>();
        var edgeByProcess = new Dictionary<uint, bool>();
        _keep = (h, l) => {
            if (!IsWindowVisible(h)) return true;
            var title = new StringBuilder(512);
            GetWindowText(h, title, title.Capacity);
            if (title.Length == 0) return true;
            uint procId;
            GetWindowThreadProcessId(h, out procId);
            bool edge;
            if (!edgeByProcess.TryGetValue(procId, out edge)) {
                try {
                    edge = string.Equals(Process.GetProcessById((int)procId).ProcessName, "msedge", StringComparison.OrdinalIgnoreCase);
                } catch {
                    edge = false;
                }
                edgeByProcess[procId] = edge;
            }
            if (edge) list.Add(h.ToInt64().ToString() + "\t" + title.ToString());
            return true;
        };
        EnumWindows(_keep, IntPtr.Zero);
        return list;
    }

    public static int[] Rect(IntPtr hwnd) {
        RECT r;
        if (!GetWindowRect(hwnd, out r)) return new int[] { 0, 0, 0, 0 };
        return new int[] { r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top };
    }

    public static bool Covers(IntPtr hwnd, int x, int y, int w, int h) {
        if (IsIconic(hwnd)) return false;
        RECT r;
        if (!GetWindowRect(hwnd, out r)) return false;
        return r.Left <= x && r.Top <= y && r.Right >= x + w && r.Bottom >= y + h;
    }

    public static bool ClientCovers(IntPtr hwnd, int x, int y, int w, int h) {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd) || IsIconic(hwnd)) return false;
        RECT client;
        if (!GetClientRect(hwnd, out client)) return false;
        var origin = new POINT();
        if (!ClientToScreen(hwnd, ref origin)) return false;
        return origin.X <= x && origin.Y <= y && origin.X + client.Right >= x + w && origin.Y + client.Bottom >= y + h;
    }

    public static void KeepOnTop(IntPtr hwnd) {
        SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }

    public static void DropFromTop(IntPtr hwnd) {
        SetWindowPos(hwnd, new IntPtr(-2), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }

    public static bool HasCaption(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return false;
        return (GetWindowLong(hwnd, GWL_STYLE) & WS_CAPTION) != 0;
    }

    public static bool IsForeground(IntPtr hwnd) {
        return hwnd != IntPtr.Zero && GetForegroundWindow() == hwnd;
    }

    public static void Cover(IntPtr hwnd, int x, int y, int w, int h) {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return;
        int style = GetWindowLong(hwnd, GWL_STYLE);
        int next = style & ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU | WS_BORDER);
        if (next != style) SetWindowLong(hwnd, GWL_STYLE, next);
        int ex = GetWindowLong(hwnd, GWL_EXSTYLE);
        int exNext = ex & ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE);
        if (exNext != ex) SetWindowLong(hwnd, GWL_EXSTYLE, exNext);
        if (IsIconic(hwnd) || IsZoomed(hwnd)) ShowWindow(hwnd, 9);
        SetWindowPos(hwnd, new IntPtr(-1), x, y, w, h, SWP_SHOWWINDOW | SWP_FRAMECHANGED);
        RECT window;
        RECT client;
        if (!GetWindowRect(hwnd, out window) || !GetClientRect(hwnd, out client)) return;
        var origin = new POINT();
        if (!ClientToScreen(hwnd, ref origin)) return;
        int insetLeft = origin.X - window.Left;
        int insetTop = origin.Y - window.Top;
        int insetRight = window.Right - (origin.X + client.Right);
        int insetBottom = window.Bottom - (origin.Y + client.Bottom);
        if (insetLeft < 0) insetLeft = 0;
        if (insetTop < 0) insetTop = 0;
        if (insetRight < 0) insetRight = 0;
        if (insetBottom < 0) insetBottom = 0;
        if (insetLeft == 0 && insetTop == 0 && insetRight == 0 && insetBottom == 0) return;
        SetWindowPos(hwnd, new IntPtr(-1), x - insetLeft, y - insetTop, w + insetLeft + insetRight, h + insetTop + insetBottom, SWP_SHOWWINDOW | SWP_FRAMECHANGED);
    }

    public static void Minimize(IntPtr hwnd) { ShowWindow(hwnd, 6); }

    public static void Focus(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return;
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
        SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        IntPtr fg = GetForegroundWindow();
        uint current = GetCurrentThreadId();
        uint fore = fg == IntPtr.Zero ? 0 : WindowThread(fg, IntPtr.Zero);
        uint target = WindowThread(hwnd, IntPtr.Zero);
        bool attachedFore = false;
        bool attachedTarget = false;
        if (fore != 0 && fore != current) attachedFore = AttachThreadInput(fore, current, true);
        if (target != 0 && target != current && target != fore) attachedTarget = AttachThreadInput(target, current, true);
        BringWindowToTop(hwnd);
        ShowWindow(hwnd, 5);
        SetForegroundWindow(hwnd);
        if (GetForegroundWindow() != hwnd && !_unlocked) {
            keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
            SetForegroundWindow(hwnd);
            keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            _unlocked = true;
        }
        if (GetForegroundWindow() != hwnd) SwitchToThisWindow(hwnd, true);
        if (attachedTarget) AttachThreadInput(target, current, false);
        if (attachedFore) AttachThreadInput(fore, current, false);
    }

    public static void Close(IntPtr hwnd) { PostMessage(hwnd, 0x0010, IntPtr.Zero, IntPtr.Zero); }

    public static void PressF11() {
        keybd_event(0x7A, 0, 0, UIntPtr.Zero);
        keybd_event(0x7A, 0, 2, UIntPtr.Zero);
    }

    public static void ClickScreen(int x, int y) {
        SetCursorPos(x, y);
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    }

    public static void LockFullscreenKeys(IntPtr hwnd) {
        _lockWindow = hwnd;
        if (_hook != IntPtr.Zero) return;
        _hookProc = (nCode, wParam, lParam) => {
            if (nCode >= 0 && (wParam == (IntPtr)0x0100 || wParam == (IntPtr)0x0104)) {
                var info = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                bool blocks = info.vkCode == 0x1B || info.vkCode == 0x7A;
                if (blocks && (_lockWindow == IntPtr.Zero || GetForegroundWindow() == _lockWindow)) return (IntPtr)1;
            }
            return CallNextHookEx(_hook, nCode, wParam, lParam);
        };
        _hook = SetWindowsHookEx(13, _hookProc, GetModuleHandle(null), 0);
    }

    public static void UnlockFullscreenKeys() {
        _lockWindow = IntPtr.Zero;
        if (_hook == IntPtr.Zero) return;
        UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
    }

    public static void KeepBelow(IntPtr hwnd, IntPtr above) {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd) || above == IntPtr.Zero || !IsWindow(above)) return;
        SetWindowPos(hwnd, above, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }

    public static void NoActivate(IntPtr hwnd) {
        int ex = GetWindowLong(hwnd, -20);
        SetWindowLong(hwnd, -20, ex | 0x08000000 | 0x00000080 | 0x00000008);
    }
}
'@ -Language CSharp

[void][RemoteWin]::SetProcessDPIAware()
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$bounds = $screen.Bounds

$edge = $null
foreach ($candidate in @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
)) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { $edge = $candidate; break }
}
if (-not $edge) {
    Write-Log "Microsoft Edge was not found."
    exit 1
}

$AE = [System.Windows.Automation.AutomationElement]
$CT = [System.Windows.Automation.ControlType]
$typeConditions = [System.Windows.Automation.Condition[]]@(
    @($CT::Button, $CT::CheckBox, $CT::RadioButton, $CT::MenuItem, $CT::ListItem, $CT::TabItem, $CT::Hyperlink) |
        ForEach-Object { [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, $_) }
)
$controlCondition = [System.Windows.Automation.OrCondition]::new($typeConditions)
$pageCondition = [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, $CT::Document)
$cache = New-Object System.Windows.Automation.CacheRequest
$cache.Add($AE::NameProperty)
$cache.Add($AE::ControlTypeProperty)
$cache.Add($AE::BoundingRectangleProperty)

$barBlack = [System.Drawing.Color]::FromArgb(32, 33, 36)
$closeRed = [System.Drawing.Color]::FromArgb(196, 43, 28)
# Fully transparent windows do not take clicks; this is the faintest one that does.
$ghostOpacity = 0.01

$script:Name = $Name
$script:Url = $Url
$script:hwnd = [IntPtr]::Zero
$script:known = @{}
$script:launchedAt = Get-Date
$script:foundAt = $null
$script:focused = $false
$script:focusLogged = $false
$script:f11Sent = $false
$script:framed = $false
$script:lastCover = [datetime]::MinValue
$script:fullDone = $false
$script:fullOn = $false
$script:visualFull = $false
$script:menuClosed = $false
$script:lastFullClick = [datetime]::MinValue
$script:lastMenuClick = [datetime]::MinValue
$script:menuTries = 0
$script:lockLogged = $false
$script:tabbedDone = $false
$script:barX = $null
$script:barColor = $barBlack
$script:disconnect = $null
$script:lastScan = [datetime]::MinValue
$script:lastNames = ""
$script:hot = $false
$script:ghost = $false
$script:leaving = $false

function Get-EdgeWindows {
    foreach ($line in [RemoteWin]::EdgeWindows()) {
        $parts = $line -split "`t", 2
        [PSCustomObject]@{ Hwnd = [IntPtr]::new([int64]$parts[0]); Title = $parts[1] }
    }
}

function Test-Console([string]$Title) {
    return $Title.StartsWith("Remote Operation Center")
}

function Get-ConsoleWindow {
    foreach ($row in @(Get-EdgeWindows)) {
        if (Test-Console $row.Title) { return $row.Hwnd }
    }
    return [IntPtr]::Zero
}

# The session is slid in just under the X; raising it over the X even briefly makes the X flicker.
function Set-SessionOrder {
    if (-not $form.Visible) {
        [RemoteWin]::KeepOnTop($script:hwnd)
        return
    }
    [RemoteWin]::KeepOnTop($form.Handle)
    $under = $form.Handle
    if ($lock.Visible) {
        [RemoteWin]::KeepBelow($lock.Handle, $under)
        $under = $lock.Handle
    }
    [RemoteWin]::KeepBelow($script:hwnd, $under)
}

function Update-SessionFrame {
    $console = Get-ConsoleWindow
    if ($console -ne [IntPtr]::Zero -and [RemoteWin]::HasCaption($console)) {
        [RemoteWin]::Cover($console, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
    }
    $age = if ($script:foundAt) { ((Get-Date) - $script:foundAt).TotalSeconds } else { 0 }
    if (-not [RemoteWin]::IsForeground($script:hwnd)) {
        if (-not $script:focused -or $age -lt 8) { [RemoteWin]::Focus($script:hwnd) }
        if ([RemoteWin]::IsForeground($script:hwnd)) {
            $script:focused = $true
            Write-Log "Session is in front."
        } elseif (-not $script:focusLogged -and $age -gt 8) {
            $script:focusLogged = $true
            Write-Log "The session window stayed behind the console."
        }
    } else {
        if (-not $script:focused) { Write-Log "Session is in front." }
        $script:focused = $true
        Set-SessionOrder
    }
    # Fit the frame only after this window is in front, so F11 cannot hit the console.
    if (-not [RemoteWin]::IsForeground($script:hwnd)) { return }
    $needsCover = -not $script:framed -or -not [RemoteWin]::ClientCovers($script:hwnd, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
    if (-not $needsCover -or ((Get-Date) - $script:lastCover).TotalMilliseconds -lt 1000) { return }
    $script:framed = $true
    $script:lastCover = Get-Date
    [RemoteWin]::Cover($script:hwnd, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
    $still = -not [RemoteWin]::ClientCovers($script:hwnd, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
    if ($still -and -not $script:f11Sent) {
        $script:f11Sent = $true
        [RemoteWin]::PressF11()
        Write-Log "Sent F11 to the session window."
    } else {
        $rect = [RemoteWin]::Rect($script:hwnd)
        Write-Log "Placed the session window over the screen at $($rect[0]),$($rect[1]) $($rect[2])x$($rect[3])."
    }
}

function Start-Session {
    $script:known = @{}
    foreach ($row in @(Get-EdgeWindows)) { $script:known[$row.Hwnd.ToInt64()] = $true }
    $script:hwnd = [IntPtr]::Zero
    $script:launchedAt = Get-Date
    $script:foundAt = $null
    $script:focused = $false
    $script:focusLogged = $false
    $script:f11Sent = $false
    $script:framed = $false
    $script:lastCover = [datetime]::MinValue
    $script:fullDone = $false
    $script:fullOn = $false
    $script:visualFull = $false
    $script:menuClosed = $false
    $script:lastFullClick = [datetime]::MinValue
    $script:lastMenuClick = [datetime]::MinValue
    $script:menuTries = 0
    $script:lockLogged = $false
    $script:tabbedDone = $false
    $script:barX = $null
    $script:barColor = $barBlack
    $script:disconnect = $null
    $script:lastScan = [datetime]::MinValue
    $script:lastNames = ""
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $edge
    $start.Arguments = "--app=`"$($script:Url)`" --new-window --start-fullscreen --force-renderer-accessibility"
    $start.UseShellExecute = $true
    [void][System.Diagnostics.Process]::Start($start)
    Write-Log "Opening $($script:Name) at $($script:Url)"
}

function Find-SessionWindow {
    $fresh = @(Get-EdgeWindows | Where-Object { -not $script:known.ContainsKey($_.Hwnd.ToInt64()) -and -not (Test-Console $_.Title) })
    if ($fresh.Count -eq 0) { return [IntPtr]::Zero }
    $named = @($fresh | Where-Object { $_.Title -match 'Remote Desktop' })
    if ($named.Count -gt 0) { return $named[0].Hwnd }
    return $fresh[0].Hwnd
}

function Get-SessionControls {
    $window = $AE::FromHandle($script:hwnd)
    $page = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $pageCondition)
    if (-not $page) { return }
    $scope = $cache.Activate()
    try {
        $found = $page.FindAll([System.Windows.Automation.TreeScope]::Descendants, $controlCondition)
    } finally {
        $scope.Dispose()
    }
    foreach ($element in $found) {
        [PSCustomObject]@{
            Element = $element
            Name = [string]$element.Cached.Name
            Type = $element.Cached.ControlType.ProgrammaticName -replace '^ControlType\.', ''
            Rect = $element.Cached.BoundingRectangle
        }
    }
}

function Set-ControlOn($row) {
    $pattern = $null
    if ($row.Element.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) {
        if ($pattern.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) { $pattern.Toggle() }
        return $true
    }
    if ($row.Element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
        if (-not $pattern.Current.IsSelected) { $pattern.Select() }
        return $true
    }
    if ($row.Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke()
        return $true
    }
    return $false
}

function Get-ScreenColor([int]$X, [int]$Y) {
    $bitmap = New-Object System.Drawing.Bitmap 1, 1
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($X, $Y, 0, 0, (New-Object System.Drawing.Size 1, 1))
        return $bitmap.GetPixel(0, 0)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Update-SessionControls {
    $rows = @(Get-SessionControls)
    $names = ($rows | ForEach-Object { "$($_.Type) '$($_.Name)'" }) -join "; "
    if ($names -ne $script:lastNames) {
        $script:lastNames = $names
        Write-Log "Controls: $names"
    }
    $script:disconnect = $rows | Where-Object { $_.Name -match '^\s*disconnect' } | Select-Object -First 1

    $settling = $script:foundAt -and ((Get-Date) - $script:foundAt).TotalSeconds -lt 90
    Update-FullScreen $rows
    if ($settling -and -not $script:tabbedDone) {
        $tabbed = $rows | Where-Object { $_.Name -match '^\s*tabbed' } | Select-Object -First 1
        if ($tabbed -and (Set-ControlOn $tabbed)) {
            $script:tabbedDone = $true
            Write-Log "Tabbed mode on: $($tabbed.Type) '$($tabbed.Name)'"
            return
        }
    }

    $win = [RemoteWin]::Rect($script:hwnd)
    $band = $win[1] + [Math]::Max(96, [int]($win[3] * 0.12))
    $closers = @($rows | Where-Object {
        $_.Type -eq 'Button' -and -not $_.Rect.IsEmpty -and $_.Rect.Width -gt 0 -and $_.Rect.Width -le 160 -and
        $_.Rect.Top -lt $band -and $_.Name -notmatch 'disconnect' -and
        $_.Name.Trim() -ne 'Close' -and
        $_.Name -match '^\s*(close|hide|dismiss|collapse)\b|^\s*[xX\u00D7\u2715\u2716]\s*$'
    } | Sort-Object { $_.Rect.Right } -Descending)
    if ($closers.Count -gt 0) {
        $rect = $closers[0].Rect
        if (-not $script:barX -or [Math]::Abs($script:barX.Left - $rect.Left) -gt 2 -or [Math]::Abs($script:barX.Top - $rect.Top) -gt 2) {
            $script:barX = $rect
            $side = [Math]::Max([Math]::Max($rect.Width, $rect.Height) + 8, 40)
            try { $script:barColor = Get-ScreenColor ([int]($rect.Left + $rect.Width / 2 - $side / 2 - 4)) ([int]($rect.Top + $rect.Height / 2)) } catch {}
            $form.Invalidate()
            Write-Log "Bar X: '$($closers[0].Name)' at $([int]$rect.Left),$([int]$rect.Top) $([int]$rect.Width)x$([int]$rect.Height)"
        }
    }
}

function Test-FullName([string]$Name, [switch]$Exit) {
    $full = $Name -match 'full[\s-]*screen'
    $leaving = $Name -match 'exit'
    if ($Exit) { return $full -and $leaving }
    return $full -and -not $leaving
}

function Test-OnScreen($rect) {
    if ($null -eq $rect -or $rect.IsEmpty -or $rect.Width -lt 8 -or $rect.Height -lt 8) { return $false }
    return $rect.Left -lt $bounds.Right -and $rect.Right -gt $bounds.Left -and $rect.Top -lt $bounds.Bottom -and $rect.Bottom -gt $bounds.Top
}

function Invoke-ScreenClickAt([int]$X, [int]$Y) {
    [RemoteWin]::Focus($script:hwnd)
    [RemoteWin]::ClickScreen($X, $Y)
}

function Find-MenuHandle {
    $window = $AE::FromHandle($script:hwnd)
    $page = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $pageCondition)
    if (-not $page) { return $null }
    $kinds = @($CT::Button, $CT::Custom, $CT::Group, $CT::Image, $CT::Hyperlink)
    $conditions = [System.Windows.Automation.Condition[]]@(
        $kinds | ForEach-Object { [System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty, $_) }
    )
    $found = $page.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.OrCondition]::new($conditions))
    $right = $bounds.Right - 140
    $mid = $bounds.Top + ($bounds.Height / 2)
    $best = $null
    $bestDist = [double]::MaxValue
    foreach ($element in $found) {
        $rect = $element.Current.BoundingRectangle
        if ($rect.IsEmpty -or $rect.Width -lt 8 -or $rect.Width -gt 96 -or $rect.Height -lt 8 -or $rect.Height -gt 180) { continue }
        if ($rect.Left -lt $right -or $rect.Right -gt $bounds.Right + 8 -or $rect.Top -lt $bounds.Top -or $rect.Bottom -gt $bounds.Bottom) { continue }
        $name = [string]$element.Current.Name
        if ($name -match 'disconnect|full[\s-]*screen|hide tabs|close') { continue }
        $dist = [Math]::Abs(($rect.Top + $rect.Height / 2) - $mid)
        if ($name -match 'option|menu|arrow|chevron|expand|panel|show|open') { $dist -= 800 }
        if ($dist -lt $bestDist) { $bestDist = $dist; $best = $rect }
    }
    return $best
}

function Open-SessionMenu {
    $script:lastMenuClick = Get-Date
    $handle = Find-MenuHandle
    if ($handle) {
        Invoke-ScreenClickAt ([int][Math]::Round($handle.Left + $handle.Width / 2)) ([int][Math]::Round($handle.Top + $handle.Height / 2))
        Write-Log "Opened the session menu."
        return
    }
    Invoke-ScreenClickAt ($bounds.Right - 12) ([int]($bounds.Top + $bounds.Height / 2))
    Write-Log "Opened the session menu from the screen edge."
}

function Update-FullScreen($rows) {
    $ready = @($rows | Where-Object { $_.Name -eq 'Hide tabs' -or $_.Type -eq 'TabItem' -or (Test-FullName $_.Name) -or (Test-FullName $_.Name -Exit) })
    if ($ready.Count -eq 0) { return }
    $exit = $rows | Where-Object { Test-FullName $_.Name -Exit } | Select-Object -First 1
    $enter = $rows | Where-Object { (Test-FullName $_.Name) -and (Test-OnScreen $_.Rect) } | Select-Object -First 1
    $hide = $rows | Where-Object { $_.Name -eq 'Hide tabs' -and (Test-OnScreen $_.Rect) } | Select-Object -First 1
    $panelOpen = @($rows | Where-Object { $_.Name -match 'Pin options panel' }).Count -gt 0
    if ($exit) { $script:fullOn = $true }
    if ($enter) { $script:fullOn = $false; $script:menuTries = 0 }
    $tabVisible = [bool]$hide -or @($rows | Where-Object { $_.Type -eq 'TabItem' -and (Test-OnScreen $_.Rect) }).Count -gt 0
    # Tabbed mode keeps the tab strip on screen in full screen, so the strip only decides where the X goes.
    $script:visualFull = $script:fullOn -and -not $tabVisible
    if (-not $script:fullOn) { $script:menuClosed = $false }
    $exitOnScreen = $exit -and (Test-OnScreen $exit.Rect)
    if ($exitOnScreen) {
        $rect = $exit.Rect
        if (-not $script:lockLogged) {
            $script:lockLogged = $true
            Write-Log "Blocking exit full screen at $([int]$rect.Left),$([int]$rect.Top) $([int]$rect.Width)x$([int]$rect.Height)"
        }
        $lock.Bounds = New-Object System.Drawing.Rectangle ([int]$rect.Left), ([int]$rect.Top), ([int][Math]::Ceiling($rect.Width)), ([int][Math]::Ceiling($rect.Height))
        if (-not $lock.Visible) { $lock.Show() }
    } elseif ($lock.Visible) {
        $lock.Hide()
    }
    if ($script:fullOn) {
        if (-not $script:fullDone) {
            $script:fullDone = $true
            Write-Log "Full screen is showing."
        }
        [RemoteWin]::LockFullscreenKeys($script:hwnd)
        if ($panelOpen -and -not $script:menuClosed) {
            $closer = $rows | Where-Object { $_.Name.Trim() -eq 'Close' -and (Test-OnScreen $_.Rect) } | Select-Object -First 1
            if ($closer) {
                $script:menuClosed = $true
                Invoke-ScreenClickAt ([int][Math]::Round($closer.Rect.Left + $closer.Rect.Width / 2)) ([int][Math]::Round($closer.Rect.Top + $closer.Rect.Height / 2))
                Write-Log "Closed the session menu."
            }
        }
        return
    }
    $now = Get-Date
    if ($enter -and (($now - $script:lastFullClick).TotalMilliseconds -gt 1000)) {
        $script:lastFullClick = $now
        Invoke-ScreenClickAt ([int][Math]::Round($enter.Rect.Left + $enter.Rect.Width / 2)) ([int][Math]::Round($enter.Rect.Top + $enter.Rect.Height / 2))
        Write-Log "Clicked full screen."
        return
    }
    # The Full-screen button is only reachable while the side menu is open.
    if (($now - $script:lastMenuClick).TotalMilliseconds -gt 1200 -and -not $panelOpen -and $script:menuTries -lt 6) {
        $script:menuTries++
        Open-SessionMenu
    }
}

function Update-CloseButton {
    $win = [RemoteWin]::Rect($script:hwnd)
    $script:ghost = $false
    if ($script:visualFull) {
        $w = $h = 40
        $x = $bounds.Right - $w - 12
        $y = $bounds.Top + 12
    } elseif ($script:barX) {
        # Lie invisibly over the tab bar X, so its own X shows and the click disconnects.
        $rect = $script:barX
        $script:ghost = $true
        $x = [int][Math]::Floor($rect.Left)
        $y = [int][Math]::Floor($rect.Top)
        $w = [int][Math]::Ceiling($rect.Right) - $x
        $h = [int][Math]::Ceiling($rect.Bottom) - $y
    } else {
        $w = $h = 48
        $x = $win[0] + $win[2] - $w
        $y = $win[1]
    }
    if ($form.Left -ne $x -or $form.Top -ne $y -or $form.Width -ne $w -or $form.Height -ne $h) {
        $form.Bounds = New-Object System.Drawing.Rectangle $x, $y, $w, $h
        $form.Invalidate()
    }
    if ($script:ghost) {
        if ($fade.Enabled) { $fade.Stop() }
        if ($form.Opacity -ne $ghostOpacity) { $form.Opacity = $ghostOpacity }
    } elseif ($form.Visible -and $form.Opacity -lt 1.0 -and -not $fade.Enabled) {
        $fade.Start()
    }
}

function Read-Request {
    if (-not (Test-Path -LiteralPath $requestPath)) { return }
    $text = ""
    try { $text = [System.IO.File]::ReadAllText($requestPath) } catch { return }
    Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
    $parts = $text -split "`t", 2
    if ($parts.Count -ne 2) { return }
    $nextUrl = $parts[1].Trim()
    if ($nextUrl -notmatch $sessionPattern) { return }
    if ($nextUrl -eq $script:Url -and $script:hwnd -ne [IntPtr]::Zero) {
        [RemoteWin]::Focus($script:hwnd)
        return
    }
    if ($script:hwnd -ne [IntPtr]::Zero) { [RemoteWin]::Close($script:hwnd) }
    $form.Hide()
    [RemoteWin]::UnlockFullscreenKeys()
    try { if ($lock.Visible) { $lock.Hide() } } catch {}
    $script:Name = $parts[0].Trim()
    $script:Url = $nextUrl
    Start-Session
}

function Show-Console {
    $console = Get-ConsoleWindow
    if ($console -eq [IntPtr]::Zero) { return }
    [RemoteWin]::Focus($console)
    if ([RemoteWin]::HasCaption($console) -and [RemoteWin]::IsForeground($console)) {
        [RemoteWin]::PressF11()
        Write-Log "Restored the console to full screen."
        return
    }
    if (-not [RemoteWin]::Covers($console, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)) {
        [RemoteWin]::Cover($console, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
    }
}

function Stop-Host {
    $script:leaving = $true
    $timer.Stop()
    $fade.Stop()
    [RemoteWin]::UnlockFullscreenKeys()
    try { if ($lock.Visible) { $lock.Hide() } } catch {}
    Show-Console
    try { $form.Close() } catch {}
    try { $lock.Close() } catch {}
    $context.ExitThread()
}

function Stop-Session {
    if ($script:leaving) { return }
    $script:leaving = $true
    $timer.Stop()
    Write-Log "Disconnecting $($script:Name)"
    $form.Hide()
    if ($script:disconnect) {
        try {
            $pattern = $null
            if ($script:disconnect.Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) { $pattern.Invoke() }
        } catch {}
    }
    if ($script:hwnd -ne [IntPtr]::Zero) {
        [RemoteWin]::Close($script:hwnd)
        $deadline = (Get-Date).AddSeconds(3)
        while ([RemoteWin]::IsWindow($script:hwnd) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
        if ([RemoteWin]::IsWindow($script:hwnd)) {
            [RemoteWin]::DropFromTop($script:hwnd)
            [RemoteWin]::Minimize($script:hwnd)
        }
    }
    Stop-Host
}

$context = New-Object System.Windows.Forms.ApplicationContext

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Text = "Disconnect remote desktop"
$form.BackColor = $barBlack
$form.Opacity = 0
$form.Bounds = New-Object System.Drawing.Rectangle ($bounds.Right - 48), $bounds.Top, 48, 48
$form.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Add_HandleCreated({ [RemoteWin]::NoActivate($form.Handle) })
$form.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear($(if ($script:hot) { $closeRed } else { $script:barColor }))
    $size = [double]$form.ClientSize.Width
    $pad = [Math]::Round($size * 0.32)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([float][Math]::Max(2.0, $size / 18.0))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    try {
        $g.DrawLine($pen, [float]$pad, [float]$pad, [float]($size - $pad), [float]($size - $pad))
        $g.DrawLine($pen, [float]($size - $pad), [float]$pad, [float]$pad, [float]($size - $pad))
    } finally {
        $pen.Dispose()
    }
})
$form.Add_MouseEnter({ $script:hot = $true; $form.Invalidate() })
$form.Add_MouseLeave({ $script:hot = $false; $form.Invalidate() })
$form.Add_MouseDown({ $script:hot = $true; $form.Invalidate() })
$form.Add_Click({ Stop-Session })

$lock = New-Object System.Windows.Forms.Form
$lock.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$lock.ShowInTaskbar = $false
$lock.TopMost = $true
$lock.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$lock.Text = "Keep full screen"
$lock.Opacity = $ghostOpacity
$lock.BackColor = $barBlack
$lock.Add_HandleCreated({ [RemoteWin]::NoActivate($lock.Handle) })

$fade = New-Object System.Windows.Forms.Timer
$fade.Interval = 16
$fade.Add_Tick({
    $form.Opacity = [Math]::Min(1.0, $form.Opacity + 0.1)
    if ($form.Opacity -ge 1.0) { $fade.Stop() }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    if ($script:leaving) { return }
    try {
        Read-Request
        if ($script:hwnd -eq [IntPtr]::Zero) {
            $found = Find-SessionWindow
            if ($found -ne [IntPtr]::Zero) {
                $script:hwnd = $found
                $script:foundAt = Get-Date
                Write-Log "Session window $($found.ToInt64())"
                Update-SessionFrame
            } elseif (((Get-Date) - $script:launchedAt).TotalSeconds -gt 30) {
                Write-Log "The session window did not open."
                Stop-Host
            }
            return
        }
        if (-not [RemoteWin]::IsWindow($script:hwnd)) {
            Write-Log "The session window closed."
            Stop-Host
            return
        }

        Update-SessionFrame

        $scanMs = 400
        if (((Get-Date) - $script:lastScan).TotalMilliseconds -ge $scanMs) {
            $script:lastScan = Get-Date
            try { Update-SessionControls } catch { Write-Log "Scan: $($_.Exception.Message)" }
        }

        Update-CloseButton
        if (-not $form.Visible) {
            $form.Opacity = $(if ($script:ghost) { $ghostOpacity } else { 0 })
            $form.Show()
            [RemoteWin]::Focus($script:hwnd)
            if (-not $script:ghost) { $fade.Start() }
        }
        Set-SessionOrder
    } catch {
        Write-Log "Tick: $($_.Exception.Message)"
    }
})

Start-Session
$timer.Start()
[System.Windows.Forms.Application]::Run($context)
} catch {
    Write-Log "Error: $($_.Exception.Message)"
    throw
} finally {
    if (Test-Path -LiteralPath $requestPath) { Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue }
    if ($ownsMutex) {
        try { $mutex.ReleaseMutex() | Out-Null } catch {}
        $mutex.Dispose()
    }
}
