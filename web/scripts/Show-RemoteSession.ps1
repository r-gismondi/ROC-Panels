# Opens one Chrome Remote Desktop session in Edge, in Full mode and Tabbed mode.
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

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    const uint SWP_NOSIZE = 0x0001;
    const uint SWP_NOMOVE = 0x0002;
    const uint SWP_NOACTIVATE = 0x0010;
    const uint SWP_SHOWWINDOW = 0x0040;
    static EnumProc _keep;

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

    public static void KeepOnTop(IntPtr hwnd) {
        SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }

    public static void DropFromTop(IntPtr hwnd) {
        SetWindowPos(hwnd, new IntPtr(-2), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }

    public static void Fill(IntPtr hwnd, int x, int y, int w, int h) {
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
        SetWindowPos(hwnd, new IntPtr(-1), x, y, w, h, SWP_SHOWWINDOW);
    }

    public static void Minimize(IntPtr hwnd) { ShowWindow(hwnd, 6); }

    public static void Focus(IntPtr hwnd) { SetForegroundWindow(hwnd); }

    public static void Close(IntPtr hwnd) { PostMessage(hwnd, 0x0010, IntPtr.Zero, IntPtr.Zero); }

    public static void PressF11() {
        keybd_event(0x7A, 0, 0, UIntPtr.Zero);
        keybd_event(0x7A, 0, 2, UIntPtr.Zero);
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

$script:Name = $Name
$script:Url = $Url
$script:hwnd = [IntPtr]::Zero
$script:known = @{}
$script:launchedAt = Get-Date
$script:foundAt = $null
$script:fullscreenTried = $false
$script:fillTried = $false
$script:fullDone = $false
$script:tabbedDone = $false
$script:barX = $null
$script:barColor = $barBlack
$script:disconnect = $null
$script:lastScan = [datetime]::MinValue
$script:lastNames = ""
$script:hot = $false
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

function Start-Session {
    $script:known = @{}
    foreach ($row in @(Get-EdgeWindows)) { $script:known[$row.Hwnd.ToInt64()] = $true }
    $script:hwnd = [IntPtr]::Zero
    $script:launchedAt = Get-Date
    $script:foundAt = $null
    $script:fullscreenTried = $false
    $script:fillTried = $false
    $script:fullDone = $false
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
    if ($settling -and -not $script:fullDone) {
        $full = $rows | Where-Object { $_.Name -match '^\s*full[\s-]*(mode|screen)' } | Select-Object -First 1
        if ($full -and (Set-ControlOn $full)) {
            $script:fullDone = $true
            Write-Log "Full mode on: $($full.Type) '$($full.Name)'"
            return
        }
    }
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

function Update-CloseButton {
    $win = [RemoteWin]::Rect($script:hwnd)
    if ($script:barX) {
        $rect = $script:barX
        $side = [int][Math]::Ceiling([Math]::Max([Math]::Max($rect.Width, $rect.Height) + 8, 40))
        $x = [int][Math]::Round($rect.Left + $rect.Width / 2 - $side / 2)
        $y = [int][Math]::Round($rect.Top + $rect.Height / 2 - $side / 2)
        if ($y -lt $win[1]) { $y = $win[1] }
    } else {
        $side = 48
        $x = $win[0] + $win[2] - $side
        $y = $win[1]
    }
    if ($form.Left -ne $x -or $form.Top -ne $y -or $form.Width -ne $side -or $form.Height -ne $side) {
        $form.Bounds = New-Object System.Drawing.Rectangle $x, $y, $side, $side
        $form.Invalidate()
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
    $script:Name = $parts[0].Trim()
    $script:Url = $nextUrl
    Start-Session
}

function Show-Console {
    foreach ($row in @(Get-EdgeWindows)) {
        if (Test-Console $row.Title) {
            [RemoteWin]::Focus($row.Hwnd)
            return
        }
    }
}

function Stop-Host {
    $script:leaving = $true
    $timer.Stop()
    $fade.Stop()
    Show-Console
    try { $form.Close() } catch {}
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

        $age = ((Get-Date) - $script:foundAt).TotalSeconds
        if (-not $script:fullscreenTried -and $age -gt 2) {
            $script:fullscreenTried = $true
            if (-not [RemoteWin]::Covers($script:hwnd, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)) {
                [RemoteWin]::Focus($script:hwnd)
                [RemoteWin]::PressF11()
                Write-Log "Sent F11 to fill the screen."
            }
        }
        if (-not $script:fillTried -and $age -gt 4) {
            $script:fillTried = $true
            if (-not [RemoteWin]::Covers($script:hwnd, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)) {
                [RemoteWin]::Fill($script:hwnd, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
                Write-Log "Placed the session window over the screen."
            }
        }

        $scanMs = if ($script:fullDone -and $script:tabbedDone -and $script:barX) { 3000 } else { 1500 }
        if (((Get-Date) - $script:lastScan).TotalMilliseconds -ge $scanMs) {
            $script:lastScan = Get-Date
            try { Update-SessionControls } catch { Write-Log "Scan: $($_.Exception.Message)" }
            [RemoteWin]::KeepOnTop($script:hwnd)
        }

        Update-CloseButton
        if (-not $form.Visible) {
            $form.Opacity = 0
            $form.Show()
            [RemoteWin]::Focus($script:hwnd)
            $fade.Start()
        }
        [RemoteWin]::KeepOnTop($form.Handle)
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
