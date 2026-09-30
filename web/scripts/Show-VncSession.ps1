# Full-screen host for one RealVNC session. Close ends it and returns to the console.
param(
    [Parameter(Mandatory = $true)][string]$ComputerName,
    [Parameter(Mandatory = $true)][string]$Address
)
$Name = $ComputerName

$ErrorActionPreference = "Stop"
if ($Address -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { exit 1 }

New-Item -ItemType Directory -Force -Path "C:\layouts" | Out-Null
$requestPath = "C:\layouts\vnc-session.request"
$viewerPath = "C:\Program Files\RealVNC\VNC Viewer\vncviewer.exe"

$mutex = New-Object System.Threading.Mutex($false, "WallVncSession")
$ownsMutex = $false
try {
    $ownsMutex = $mutex.WaitOne(0)
} catch {
    $ownsMutex = $true
}
if (-not $ownsMutex) {
    [System.IO.File]::WriteAllText($requestPath, ($Name + "`t" + $Address))
    exit 0
}

try {
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

public static class VncHostWin {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);

    [ComImport, Guid("56FDF342-FD6D-11d0-958A-006097C9A090"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ITaskbarList {
        void HrInit();
        void AddTab(IntPtr hwnd);
        void DeleteTab(IntPtr hwnd);
        void ActivateTab(IntPtr hwnd);
        void SetActiveAlt(IntPtr hwnd);
    }

    [ComImport, Guid("56FDF344-FD6D-11d0-958A-006097C9A090")]
    class CTaskbarList {}

    static EnumProc _keep;
    static ITaskbarList _taskbar;
    const int GWL_STYLE = -16;
    const int GWL_EXSTYLE = -20;
    const int WS_CAPTION = 0x00C00000;
    const int WS_THICKFRAME = 0x00040000;
    const int WS_SYSMENU = 0x00080000;
    const int WS_MINIMIZEBOX = 0x00020000;
    const int WS_MAXIMIZEBOX = 0x00010000;
    const int WS_EX_TOOLWINDOW = 0x00000080;
    const int WS_EX_APPWINDOW = 0x00040000;
    const uint SWP_NOSIZE = 0x0001;
    const uint SWP_NOMOVE = 0x0002;
    const uint SWP_NOACTIVATE = 0x0010;
    const uint SWP_FRAMECHANGED = 0x0020;
    const uint SWP_SHOWWINDOW = 0x0040;
    const uint WM_CLOSE = 0x0010;

    public static List<string> List() {
        var list = new List<string>();
        _keep = (h, l) => {
            uint procId;
            GetWindowThreadProcessId(h, out procId);
            try {
                var process = Process.GetProcessById((int)procId);
                if (!string.Equals(process.ProcessName, "vncviewer", StringComparison.OrdinalIgnoreCase)) return true;
            } catch {
                return true;
            }
            var title = new StringBuilder(512);
            GetWindowText(h, title, title.Capacity);
            string text = title.ToString();
            if (text.Length == 0) return true;
            bool visible = IsWindowVisible(h);
            bool iconic = IsIconic(h);
            bool interesting = visible || iconic || text == "RealVNC Viewer" || Regex.IsMatch(text, @"\d{1,3}(\.\d{1,3}){3}");
            if (!interesting) return true;
            RECT rect;
            GetWindowRect(h, out rect);
            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            list.Add(h.ToInt64().ToString() + "\t" + (visible ? "1" : "0") + "\t" + (iconic ? "1" : "0") + "\t" + width.ToString() + "\t" + height.ToString() + "\t" + text);
            return true;
        };
        EnumWindows(_keep, IntPtr.Zero);
        return list;
    }

    public static void KeepOffTaskbar(IntPtr hwnd) {
        if (!IsWindow(hwnd)) return;
        int ex = GetWindowLong(hwnd, GWL_EXSTYLE);
        int updated = (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
        if (updated != ex) SetWindowLong(hwnd, GWL_EXSTYLE, updated);
        try {
            if (_taskbar == null) {
                _taskbar = (ITaskbarList)new CTaskbarList();
                _taskbar.HrInit();
            }
            _taskbar.DeleteTab(hwnd);
        } catch {}
    }

    public static void HideWindow(IntPtr hwnd) {
        if (!IsWindow(hwnd)) return;
        KeepOffTaskbar(hwnd);
        ShowWindow(hwnd, 0);
    }

    public static bool Place(IntPtr hwnd, int x, int y, int w, int h, bool restyle) {
        if (!IsWindow(hwnd)) return false;
        if (restyle) {
            int style = GetWindowLong(hwnd, GWL_STYLE);
            style &= ~WS_CAPTION;
            style &= ~WS_THICKFRAME;
            style &= ~WS_SYSMENU;
            style &= ~WS_MINIMIZEBOX;
            style &= ~WS_MAXIMIZEBOX;
            SetWindowLong(hwnd, GWL_STYLE, style);
            KeepOffTaskbar(hwnd);
            if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
            ShowWindow(hwnd, 0);
            SetWindowPos(hwnd, new IntPtr(-1), x, y, w, h, SWP_FRAMECHANGED);
            ShowWindow(hwnd, 5);
            return true;
        }
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
        if (!IsAt(hwnd, x, y, w, h)) {
            SetWindowPos(hwnd, new IntPtr(-1), x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
            return true;
        }
        return false;
    }

    public static bool IsAt(IntPtr hwnd, int x, int y, int w, int h) {
        if (!IsWindow(hwnd) || IsIconic(hwnd)) return false;
        RECT rect;
        GetWindowRect(hwnd, out rect);
        return Math.Abs(rect.Left - x) <= 8 && Math.Abs(rect.Top - y) <= 8 && Math.Abs((rect.Right - rect.Left) - w) <= 8 && Math.Abs((rect.Bottom - rect.Top) - h) <= 8;
    }

    public static double Ease(double time) {
        if (time <= 0) return 0;
        if (time >= 1) return 1;
        double x1 = 0.22, y1 = 1, x2 = 0.36, y2 = 1;
        double t = time;
        for (int i = 0; i < 8; i++) {
            double mt = 1 - t;
            double x = (3 * mt * mt * t * x1) + (3 * mt * t * t * x2) + (t * t * t);
            double dx = (3 * mt * mt * x1) + (6 * mt * t * (x2 - x1)) + (3 * t * t * (1 - x2));
            if (Math.Abs(dx) < 1e-6) break;
            t -= (x - time) / dx;
            if (t < 0) t = 0;
            else if (t > 1) t = 1;
        }
        double u = 1 - t;
        double y = (3 * u * u * t * y1) + (3 * u * t * t * y2) + (t * t * t);
        if (y < 0) return 0;
        if (y > 1) return 1;
        return y;
    }

    public static void Move(IntPtr hwnd, int x, int y, int w, int h) {
        if (!IsWindow(hwnd)) return;
        SetWindowPos(hwnd, new IntPtr(-1), x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }

    public static void Raise(IntPtr hwnd) {
        if (!IsWindow(hwnd)) return;
        SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }

    public static void Focus(IntPtr hwnd) {
        if (!IsWindow(hwnd)) return;
        SetForegroundWindow(hwnd);
    }

    public static void CloseWindow(IntPtr hwnd) {
        if (!IsWindow(hwnd)) return;
        PostMessage(hwnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }

    public static IntPtr FindTitle(string title) {
        IntPtr found = IntPtr.Zero;
        _keep = (h, l) => {
            if (!IsWindowVisible(h)) return true;
            var text = new StringBuilder(256);
            GetWindowText(h, text, text.Capacity);
            if (text.ToString() == title) {
                found = h;
                return false;
            }
            return true;
        };
        EnumWindows(_keep, IntPtr.Zero);
        return found;
    }
}
'@ -Language CSharp

$script:Name = $Name
$script:Address = $Address
$script:sessionHwnd = [IntPtr]::Zero
$script:styledHwnd = [IntPtr]::Zero
$script:focusedHwnd = [IntPtr]::Zero
$script:seenSession = $false
$script:misses = 0
$script:leaving = $false
$script:startedAt = Get-Date

function Get-VncWindows {
    $rows = @()
    foreach ($line in [VncHostWin]::List()) {
        $parts = $line -split "`t", 6
        $rows += [PSCustomObject]@{
            Hwnd = [IntPtr]::new([int64]$parts[0])
            Visible = $parts[1] -eq "1"
            Iconic = $parts[2] -eq "1"
            Width = [int]$parts[3]
            Height = [int]$parts[4]
            Title = $parts[5]
        }
    }
    return $rows
}

function Start-Viewer {
    if (-not (Test-Path -LiteralPath $viewerPath)) { throw "RealVNC Viewer was not found." }
    Start-Process -FilePath $viewerPath -ArgumentList @(
        "-UseAddressBook",
        "-FullScreen=0",
        "-Scaling=Fit",
        $script:Address
    ) -WorkingDirectory (Split-Path -Parent $viewerPath) -WindowStyle Normal
    $script:startedAt = Get-Date
}

function Close-Viewer {
    $rows = @(Get-VncWindows)
    foreach ($row in $rows) {
        if ($row.Title -like "*$($script:Address)*") { [VncHostWin]::CloseWindow($row.Hwnd) }
    }
    $others = @($rows | Where-Object { $_.Title -match '\d{1,3}(\.\d{1,3}){3}' -and $_.Title -notlike "*$($script:Address)*" })
    if ($others.Count -gt 0) { return }
    foreach ($row in $rows) {
        if ($row.Title -eq "RealVNC Viewer" -or $row.Title -like "*$($script:Address)*") {
            [VncHostWin]::CloseWindow($row.Hwnd)
        }
    }
    Start-Sleep -Milliseconds 400
    $left = @(Get-VncWindows | Where-Object { $_.Title -match '\d{1,3}(\.\d{1,3}){3}' })
    if ($left.Count -eq 0) {
        Get-Process -Name vncviewer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Switch-Target([string]$newName, [string]$newAddress) {
    if ($newAddress -eq $script:Address) { return }
    $previous = $script:Address
    foreach ($row in @(Get-VncWindows)) {
        if ($row.Title -like "*$previous*") { [VncHostWin]::CloseWindow($row.Hwnd) }
    }
    $script:Name = $newName
    $script:Address = $newAddress
    $script:sessionHwnd = [IntPtr]::Zero
    $script:styledHwnd = [IntPtr]::Zero
    $script:focusedHwnd = [IntPtr]::Zero
    $script:seenSession = $false
    $script:misses = 0
    $title.Text = "Connecting to $newName…"
    Start-Viewer
}

$screen = [System.Windows.Forms.Screen]::PrimaryScreen
if (-not $screen) { $screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position) }
$area = $screen.WorkingArea
$navy = [System.Drawing.Color]::FromArgb(7, 26, 77)
$blue = [System.Drawing.Color]::FromArgb(8, 47, 140)
$cyan = [System.Drawing.Color]::FromArgb(125, 211, 252)
$barHeight = 48

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.BackColor = $navy
$form.ForeColor = [System.Drawing.Color]::White
$form.Text = "VNC session"
$script:motionMs = 480
$script:frameX = $area.X
$script:framePairY = $area.Y
$script:frameW = $area.Width
$script:frameContentY = $area.Y + $barHeight
$script:frameContentH = [Math]::Max(1, $area.Height - $barHeight)
$script:viewerTravel = $script:frameContentH
$script:chromeStart = Get-Date
$script:viewerStart = $null
$script:exitStart = $null
$script:exitFromOffset = 0
$script:exitFromOpacity = 0.0
$form.Opacity = 0
$form.Bounds = New-Object System.Drawing.Rectangle $area.X, ($area.Y + $barHeight), $area.Width, $barHeight

$accent = New-Object System.Windows.Forms.Panel
$accent.Dock = [System.Windows.Forms.DockStyle]::Bottom
$accent.Height = 2
$accent.BackColor = $cyan
$form.Controls.Add($accent)

$title = New-Object System.Windows.Forms.Label
$title.Dock = [System.Windows.Forms.DockStyle]::Fill
$title.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$title.Padding = New-Object System.Windows.Forms.Padding 12, 0, 8, 0
$title.BackColor = $navy
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font "Segoe UI", 13
$title.Text = "Connecting to $Name…"
$form.Controls.Add($title)

$close = New-Object System.Windows.Forms.Button
$close.Dock = [System.Windows.Forms.DockStyle]::Right
$close.Width = 96
$close.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$close.FlatAppearance.BorderSize = 0
$close.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(16, 78, 168)
$close.BackColor = $blue
$close.ForeColor = [System.Drawing.Color]::White
$close.Font = New-Object System.Drawing.Font "Segoe UI", 13
$close.Text = "Close"
$close.TabStop = $false
$form.Controls.Add($close)
$close.BringToFront()

$close.Add_Click({
    if ($script:leaving -or $script:exitStart) { return }
    $script:exitFromChrome = 0
    $script:exitFromViewer = 0
    if ($script:chromeStart) {
        $ease = Get-MotionEase $script:chromeStart
        if ($ease -lt 1) { $script:exitFromChrome = [int][Math]::Round((1 - $ease) * $barHeight) }
    }
    if ($script:viewerStart) {
        $ease = Get-MotionEase $script:viewerStart
        if ($ease -lt 1) { $script:exitFromViewer = [int][Math]::Round((1 - $ease) * $script:viewerTravel) }
    } else {
        $script:exitFromViewer = $script:exitFromChrome
    }
    $script:exitFromOpacity = [double]$form.Opacity
    $script:exitStart = Get-Date
    $script:chromeStart = $null
    $script:viewerStart = $null
    try { $timer.Stop() } catch {}
    $script:motionTimer.Start()
})

$form.Add_FormClosing({
    if (-not $script:leaving) {
        $script:leaving = $true
        Close-Viewer
    }
    if (Test-Path -LiteralPath $requestPath) { Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    if ($script:leaving -or $form.IsDisposed) { return }
    try {
        if (Test-Path -LiteralPath $requestPath) {
            $request = [System.IO.File]::ReadAllText($requestPath)
            Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
            $parts = $request -split "`t", 2
            if ($parts.Count -eq 2) { Switch-Target $parts[0].Trim() $parts[1].Trim() }
        }

        $rows = @(Get-VncWindows)
        $splashTitle = "$($script:Address) - RealVNC Viewer"
        $candidates = @($rows | Where-Object { $_.Title -like "*$($script:Address)*" -and $_.Title -ne "RealVNC Viewer" })
        $connected = @($candidates | Where-Object { $_.Title -ne $splashTitle })
        if ($connected.Count -gt 0) {
            $session = $connected | Sort-Object { $_.Width * $_.Height } -Descending | Select-Object -First 1
            foreach ($splash in $candidates) {
                if ($splash.Title -eq $splashTitle) { [VncHostWin]::HideWindow($splash.Hwnd) }
            }
        } else {
            $session = $candidates | Select-Object -First 1
        }

        $maxW = $area.Width
        $maxH = $area.Height - $barHeight
        if ($maxH -lt 1) { $maxH = 1 }
        $winW = $maxW
        $winH = $maxH
        if ($session -and $session.Width -gt 0 -and $session.Height -gt 0) {
            $winW = [Math]::Min($session.Width, $maxW)
            $winH = [Math]::Min($session.Height, $maxH)
        }
        $contentW = $winW
        $contentH = $winH
        $contentX = $area.X + [int][Math]::Floor([Math]::Max(0, $maxW - $contentW) / 2)
        $pairY = $area.Y + [int][Math]::Floor([Math]::Max(0, $area.Height - ($barHeight + $contentH)) / 2)
        $contentY = $pairY + $barHeight
        $script:frameX = $contentX
        $script:framePairY = $pairY
        $script:frameW = $contentW
        $script:frameContentY = $contentY
        $script:frameContentH = [Math]::Max(1, $contentH)
        $opening = $script:chromeStart -or $script:viewerStart -or $script:exitStart
        if (-not $opening) {
            if ($form.Left -ne $contentX -or $form.Top -ne $pairY -or $form.Width -ne $contentW -or $form.Height -ne $barHeight) {
                $form.Bounds = New-Object System.Drawing.Rectangle $contentX, $pairY, $contentW, $barHeight
            }
        }

        if ($session) {
            $script:seenSession = $true
            $script:misses = 0
            $script:sessionHwnd = $session.Hwnd
            $restyle = $script:styledHwnd -ne $session.Hwnd
            $placed = $false
            if ($restyle) {
                $script:viewerStart = Get-Date
                $script:viewerTravel = [Math]::Max($contentH, 1)
                $script:motionTimer.Start()
                $placed = [VncHostWin]::Place($session.Hwnd, $contentX, ($contentY + $script:viewerTravel), $contentW, $contentH, $true)
            } elseif (-not $script:chromeStart -and -not $script:viewerStart -and -not $script:exitStart) {
                $placed = [VncHostWin]::Place($session.Hwnd, $contentX, $contentY, $contentW, $contentH, $false)
            }
            $script:styledHwnd = $session.Hwnd
            if ($placed) {
                foreach ($keyboardTitle in @("VNC Keyboard", "Keyboard")) {
                    $keyboardHwnd = [VncHostWin]::FindTitle($keyboardTitle)
                    if ($keyboardHwnd -ne [IntPtr]::Zero) { [VncHostWin]::Raise($keyboardHwnd) }
                }
            }
            $title.Text = $script:Name
            if ($script:focusedHwnd -ne $session.Hwnd) {
                [VncHostWin]::Focus($session.Hwnd)
                $script:focusedHwnd = $session.Hwnd
            }
        } elseif ($script:seenSession) {
            $script:misses++
            if ($script:misses -ge 8) {
                $script:leaving = $true
                $timer.Stop()
                Close-Viewer
                $form.Close()
                return
            }
        } elseif (((Get-Date) - $script:startedAt).TotalSeconds -gt 20) {
            $title.Text = "Could not open $($script:Name). Close to return."
        }

        foreach ($row in $rows) {
            if ($script:seenSession -and $row.Title -eq "RealVNC Viewer" -and $row.Visible -and $row.Hwnd -ne $script:sessionHwnd) {
                [VncHostWin]::HideWindow($row.Hwnd)
            }
        }
        $dialogs = @($rows | Where-Object {
            $_.Visible -and $_.Title -ne "RealVNC Viewer" -and $_.Title -notlike "*$($script:Address)*"
        })
        foreach ($dialog in $dialogs) { [VncHostWin]::Raise($dialog.Hwnd) }
        [VncHostWin]::Raise($form.Handle)
        foreach ($keyboardTitle in @("Keyboard", "VNC Keyboard")) {
            $keyboardHwnd = [VncHostWin]::FindTitle($keyboardTitle)
            if ($keyboardHwnd -ne [IntPtr]::Zero) { [VncHostWin]::Raise($keyboardHwnd) }
        }
    } catch {
        $title.Text = "Could not open $($script:Name). Close to return."
    }
})

function Get-MotionEase($start) {
    if (-not $start) { return 1.0 }
    $elapsed = ((Get-Date) - $start).TotalMilliseconds
    if ($elapsed -le 0) { return 0.0 }
    $t = $elapsed / $script:motionMs
    if ($t -ge 1) { return 1.0 }
    return [VncHostWin]::Ease([double]$t)
}

function Update-VncMotion {
    if ($script:leaving -or $form.IsDisposed) { return }
    $travel = [Math]::Max($area.Height, 1)
    if ($script:exitStart) {
        $ease = Get-MotionEase $script:exitStart
        $chromeOffset = [int][Math]::Round($script:exitFromChrome + (($travel - $script:exitFromChrome) * $ease))
        $viewerOffset = [int][Math]::Round($script:exitFromViewer + (($travel - $script:exitFromViewer) * $ease))
        $opacity = $script:exitFromOpacity * (1 - $ease)
        if ($opacity -lt 0) { $opacity = 0 }
        if ($opacity -gt 1) { $opacity = 1 }
        $form.Opacity = $opacity
        $form.Bounds = New-Object System.Drawing.Rectangle $script:frameX, ($script:framePairY + $chromeOffset), $script:frameW, $barHeight
        if ($script:styledHwnd -ne [IntPtr]::Zero -and $script:styledHwnd -eq $script:sessionHwnd) {
            [VncHostWin]::Move($script:sessionHwnd, $script:frameX, ($script:frameContentY + $viewerOffset), $script:frameW, $script:frameContentH)
        }
        if ($ease -ge 1) {
            $script:motionTimer.Stop()
            $script:exitStart = $null
            $script:leaving = $true
            try { $form.Hide() } catch {}
            try { Close-Viewer } catch {}
            try { $form.Close() } catch {}
        }
        return
    }

    $moving = [bool]($script:chromeStart -or $script:viewerStart)
    $chromeOffset = 0
    if ($script:chromeStart) {
        $ease = Get-MotionEase $script:chromeStart
        $chromeOffset = [int][Math]::Round((1 - $ease) * $barHeight)
        $opacity = $ease
        if ($opacity -lt 0) { $opacity = 0 }
        if ($opacity -gt 1) { $opacity = 1 }
        $form.Opacity = $opacity
        if ($ease -ge 1) {
            $script:chromeStart = $null
            $chromeOffset = 0
            $form.Opacity = 1
        }
        $form.Bounds = New-Object System.Drawing.Rectangle $script:frameX, ($script:framePairY + $chromeOffset), $script:frameW, $barHeight
    }

    $viewerOffset = $chromeOffset
    if ($script:viewerStart) {
        $ease = Get-MotionEase $script:viewerStart
        $viewerOffset = [int][Math]::Round((1 - $ease) * $script:viewerTravel)
        if ($ease -ge 1) {
            $script:viewerStart = $null
            $viewerOffset = 0
        }
    }
    if ($moving -and $script:styledHwnd -ne [IntPtr]::Zero -and $script:styledHwnd -eq $script:sessionHwnd) {
        [VncHostWin]::Move($script:sessionHwnd, $script:frameX, ($script:frameContentY + $viewerOffset), $script:frameW, $script:frameContentH)
    }
    if (-not $script:chromeStart -and -not $script:viewerStart) {
        $script:motionTimer.Stop()
        if ($form.Left -ne $script:frameX -or $form.Top -ne $script:framePairY -or $form.Width -ne $script:frameW -or $form.Height -ne $barHeight) {
            $form.Bounds = New-Object System.Drawing.Rectangle $script:frameX, $script:framePairY, $script:frameW, $barHeight
        }
        $form.Opacity = 1
    }
}

$script:motionTimer = New-Object System.Windows.Forms.Timer
$script:motionTimer.Interval = 16
$script:motionTimer.Add_Tick({ Update-VncMotion })

$form.Add_Shown({
    $timer.Start()
    $script:motionTimer.Start()
    $existing = @(Get-VncWindows | Where-Object { $_.Title -like "*$($script:Address)*" -and $_.Title -ne "RealVNC Viewer" })
    if ($existing.Count -gt 0) { return }
    try { Start-Viewer } catch { $title.Text = $_.Exception.Message }
})

[System.Windows.Forms.Application]::Run($form)
} catch {
    try { $_ | Out-File -FilePath "C:\layouts\vnc-host-error.txt" -Encoding utf8 } catch {}
    throw
} finally {
    if ($ownsMutex) {
        try { $mutex.ReleaseMutex() | Out-Null } catch {}
        $mutex.Dispose()
    }
}
