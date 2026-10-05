# Touch keyboard for a VNC session. Grey palette matches the floating keyboard button.
# Keys are typed into the VNC window, so this panel does not take focus.
param([switch]$Preview)
$ErrorActionPreference = "Stop"
$mutex = New-Object System.Threading.Mutex($false, "WallKeyboardButton")
try {
    if (-not $mutex.WaitOne(0)) { exit 0 }
} catch {
    # An earlier button closed without releasing the mutex. This process owns it now.
}
try {

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

public static class VncKeyboardWin {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION {
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public INPUTUNION U;
    }

    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    static EnumProc _keep;

    public static void NoActivate(IntPtr hwnd) {
        int ex = GetWindowLong(hwnd, -20);
        ex |= 0x08000000;
        ex |= 0x00000080;
        SetWindowLong(hwnd, -20, ex);
    }

    public static void StayOnTop(IntPtr hwnd) {
        SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
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

    public static void FocusSession() {
        IntPtr best = IntPtr.Zero;
        int bestArea = 0;
        _keep = (h, l) => {
            if (!IsWindowVisible(h) || IsIconic(h)) return true;
            uint procId;
            GetWindowThreadProcessId(h, out procId);
            try {
                var process = Process.GetProcessById((int)procId);
                if (!string.Equals(process.ProcessName, "vncviewer", StringComparison.OrdinalIgnoreCase)) return true;
            } catch { return true; }
            var title = new StringBuilder(300);
            GetWindowText(h, title, title.Capacity);
            string text = title.ToString();
            if (text.Length == 0 || text == "RealVNC Viewer") return true;
            if (!Regex.IsMatch(text, @"\d{1,3}(\.\d{1,3}){3}")) return true;
            RECT rect;
            GetWindowRect(h, out rect);
            int area = Math.Abs((rect.Right - rect.Left) * (rect.Bottom - rect.Top));
            if (text.IndexOf("(desktop", StringComparison.OrdinalIgnoreCase) >= 0) area += 100000000;
            if (area > bestArea) { bestArea = area; best = h; }
            return true;
        };
        EnumWindows(_keep, IntPtr.Zero);
        if (best == IntPtr.Zero) return;
        uint unused;
        uint foregroundThread = GetWindowThreadProcessId(GetForegroundWindow(), out unused);
        uint thisThread = GetCurrentThreadId();
        bool attached = foregroundThread != 0 && foregroundThread != thisThread && AttachThreadInput(thisThread, foregroundThread, true);
        ShowWindow(best, 9);
        SetForegroundWindow(best);
        if (attached) AttachThreadInput(thisThread, foregroundThread, false);
    }

    public static void Tap(ushort vk, bool shift) {
        FocusSession();
        INPUT[] inputs = shift ? new INPUT[4] : new INPUT[2];
        int index = 0;
        if (shift) inputs[index++] = Key(0x10, false);
        inputs[index++] = Key(vk, false);
        inputs[index++] = Key(vk, true);
        if (shift) inputs[index++] = Key(0x10, true);
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    static INPUT Key(ushort vk, bool up) {
        INPUT input = new INPUT();
        input.type = 1;
        input.U.ki.wVk = vk;
        input.U.ki.dwFlags = up ? 2u : 0u;
        return input;
    }
}
'@ -Language CSharp

$panelBg = [System.Drawing.Color]::FromArgb(42, 42, 46)
$keyBg = [System.Drawing.Color]::FromArgb(88, 88, 92)
$keyBorder = [System.Drawing.Color]::FromArgb(160, 160, 164)
$keyText = [System.Drawing.Color]::FromArgb(214, 214, 216)
$dragBg = [System.Drawing.Color]::FromArgb(58, 58, 62)
$script:shift = $false
$script:shiftables = @()

function Set-Round([System.Windows.Forms.Control]$control) {
    $control.Add_Resize({
        $w = $this.Width
        $h = $this.Height
        if ($w -lt 8 -or $h -lt 8) { return }
        $radius = 8
        $diameter = $radius * 2
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc($w - $diameter, 0, $diameter, $diameter, 270, 90)
        $path.AddArc($w - $diameter, $h - $diameter, $diameter, $diameter, 0, 90)
        $path.AddArc(0, $h - $diameter, $diameter, $diameter, 90, 90)
        $path.CloseFigure()
        $this.Region = New-Object System.Drawing.Region $path
    })
}

function Update-ShiftLabels {
    foreach ($entry in $script:shiftables) {
        $entry.Button.Text = if ($script:shift) { $entry.Upper } else { $entry.Lower }
    }
    $shiftButton.FlatAppearance.BorderColor = if ($script:shift) { $keyText } else { $keyBorder }
    $shiftButton.BackColor = if ($script:shift) { [System.Drawing.Color]::FromArgb(128, 128, 132) } else { $keyBg }
}

function Send-Char([string]$ch, $useShift) {
    $vk = $null
    $shifted = $false
    $shiftDown = $useShift -eq $true
    if ($ch -match '^[a-zA-Z]$') {
        $vk = [uint16][byte][char]$ch.ToUpper()
        $shifted = $shiftDown -or [char]::IsUpper($ch)
    } elseif ($ch -match '^[0-9]$') {
        $vk = [uint16][byte][char]$ch
    } else {
        switch ($ch) {
            "." { $vk = [uint16]0xBE }
            "-" { $vk = [uint16]0xBD }
            "_" { $vk = [uint16]0xBD; $shifted = $true }
            "/" { $vk = [uint16]0xBF }
            ":" { $vk = [uint16]0xBA; $shifted = $true }
            "?" { $vk = [uint16]0xBF; $shifted = $true }
            "&" { $vk = [uint16]0x37; $shifted = $true }
            "=" { $vk = [uint16]0xBB }
            "#" { $vk = [uint16]0x33; $shifted = $true }
            "%" { $vk = [uint16]0x35; $shifted = $true }
            " " { $vk = [uint16]0x20 }
        }
    }
    if ($null -eq $vk) { return }
    [VncKeyboardWin]::Tap($vk, $shifted)
}

function Send-Text([string]$text) {
    [VncKeyboardWin]::FocusSession()
    foreach ($ch in $text.ToCharArray()) { Send-Char ([string]$ch) $false }
}

function New-Key([string]$text, [scriptblock]$onClick, [double]$fontSize) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.AutoSize = $false
    $button.MinimumSize = New-Object System.Drawing.Size 0, 0
    $button.Dock = [System.Windows.Forms.DockStyle]::None
    $button.Margin = New-Object System.Windows.Forms.Padding 0
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = $keyBorder
    $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(110, 110, 114)
    $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(128, 128, 132)
    $button.BackColor = $keyBg
    $button.ForeColor = $keyText
    $button.Font = New-Object System.Drawing.Font "Segoe UI", $fontSize
    $button.TabStop = $false
    $button.Add_MouseUp({
        param($sender, $eventArgs)
        if ($eventArgs.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        $action = $sender.Tag
        if ($action -is [scriptblock]) {
            & $action
            return
        }
        if ($null -eq $action) { return }
        if ($action.Kind -eq "letter") {
            Send-Char $action.Char ([bool]$script:shift)
            if ($script:shift) {
                $script:shift = $false
                Update-ShiftLabels
            }
        } elseif ($action.Kind -eq "text") {
            Send-Text $action.Char
        } elseif ($action.Kind -eq "char") {
            Send-Char $action.Char $false
        }
    })
    $button.Tag = $onClick
    return $button
}

$script:keyRows = New-Object System.Collections.ArrayList
function Add-KeyRow([string[]]$labels, [bool]$letters, [int[]]$weights) {
    $buttons = New-Object System.Collections.Generic.List[System.Windows.Forms.Button]
    if (-not $weights -or $weights.Count -ne $labels.Count) {
        $weights = @()
        foreach ($ignored in $labels) { $weights += 1 }
    }
    for ($index = 0; $index -lt $labels.Count; $index++) {
        $label = $labels[$index]
        if ($letters -and $label -match '^[a-z]$') {
            $lower = $label
            $button = New-Key $lower { } 12
            $button.Tag = @{ Kind = "letter"; Char = $lower }
            $script:shiftables += [PSCustomObject]@{ Button = $button; Lower = $lower; Upper = $lower.ToUpper() }
        } elseif ($label -in @("https://", "www.", ".com")) {
            $button = New-Key $label { } 12
            $button.Tag = @{ Kind = "text"; Char = $label }
        } else {
            $button = New-Key $label { } 12
            $button.Tag = @{ Kind = "char"; Char = $label }
        }
        $keyboard.Controls.Add($button)
        [void]$buttons.Add($button)
    }
    [void]$script:keyRows.Add([PSCustomObject]@{ Buttons = $buttons.ToArray(); Weights = $weights })
}

$screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
$area = $screen.WorkingArea

$buttonForm = New-Object System.Windows.Forms.Form
$buttonForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$buttonForm.ShowInTaskbar = $false
$buttonForm.TopMost = $true
$buttonForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$buttonForm.BackColor = [System.Drawing.Color]::FromArgb(88, 88, 92)
$buttonForm.Opacity = 0.46
$buttonForm.Size = New-Object System.Drawing.Size 112, 112
$buttonForm.Text = "Keyboard"
$buttonForm.Add_HandleCreated({ [VncKeyboardWin]::NoActivate($buttonForm.Handle) })
Set-Round $buttonForm

$icon = New-Object System.Windows.Forms.Button
$icon.Dock = [System.Windows.Forms.DockStyle]::Fill
$icon.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$icon.FlatAppearance.BorderSize = 0
$icon.Font = New-Object System.Drawing.Font "Segoe UI Symbol", 36
$icon.ForeColor = [System.Drawing.Color]::FromArgb(214, 214, 216)
$icon.BackColor = [System.Drawing.Color]::FromArgb(88, 88, 92)
$icon.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(110, 110, 114)
$icon.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(128, 128, 132)
$icon.Text = [string]([char]0x2328)
$icon.TabStop = $false
$icon.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$buttonForm.Controls.Add($icon)
$margin = 24
$buttonForm.Location = New-Object System.Drawing.Point ($area.Right - $buttonForm.Width - $margin), ($area.Bottom - $buttonForm.Height - $margin)
$script:motionMs = 480
$script:buttonOpacity = 0.46
$script:buttonHome = $buttonForm.Location
$script:buttonIntro = $true
$buttonForm.Opacity = 0
$buttonForm.Top = $script:buttonHome.Y + $buttonForm.Height

$keyboard = New-Object System.Windows.Forms.Form
$keyboard.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$keyboard.ShowInTaskbar = $false
$keyboard.TopMost = $true
$keyboard.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$keyboard.BackColor = $panelBg
$keyboard.Text = "VNC Keyboard"
$keyboard.Visible = $false
$keyboard.Add_HandleCreated({ [VncKeyboardWin]::NoActivate($keyboard.Handle) })
$keyboardWidth = [Math]::Min(1040, $area.Width - 80)
$keyboardHeight = [Math]::Min(380, $area.Height - 160)
$keyboardX = $area.Left + [Math]::Floor(($area.Width - $keyboardWidth) / 2)
$keyboardY = $area.Bottom - $keyboardHeight - 16
$keyboard.Bounds = New-Object System.Drawing.Rectangle $keyboardX, $keyboardY, $keyboardWidth, $keyboardHeight
$script:keyboardPlaced = $false

$dragBar = New-Object System.Windows.Forms.Panel
$dragBar.Dock = [System.Windows.Forms.DockStyle]::None
$dragBar.Height = 36
$dragBar.BackColor = $dragBg
$dragBar.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$keyboard.Controls.Add($dragBar)

$dragLabel = New-Object System.Windows.Forms.Label
$dragLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$dragLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$dragLabel.Padding = New-Object System.Windows.Forms.Padding 16, 0, 0, 0
$dragLabel.ForeColor = $keyText
$dragLabel.BackColor = $dragBar.BackColor
$dragLabel.Font = New-Object System.Drawing.Font "Segoe UI", 12
$dragLabel.Text = "Drag to move"
$dragLabel.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$dragBar.Controls.Add($dragLabel)

$script:dragging = $false
$script:dragCursor = $null
$script:dragOrigin = $null
function Start-Drag {
    if ($script:panelMoving -and -not $script:panelHide) {
        $script:panelMoving = $false
        $script:panelMotion.Stop()
        $keyboard.Opacity = 1
        $script:panelRestX = $keyboard.Left
        $script:panelRestY = $keyboard.Top
    }
    $script:dragging = $true
    $script:dragCursor = [System.Windows.Forms.Cursor]::Position
    $script:dragOrigin = $keyboard.Location
    $dragBar.Capture = $true
}
function Move-Drag {
    if (-not $script:dragging) { return }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $x = $script:dragOrigin.X + ($cursor.X - $script:dragCursor.X)
    $y = $script:dragOrigin.Y + ($cursor.Y - $script:dragCursor.Y)
    $workArea = [System.Windows.Forms.Screen]::FromPoint($cursor).WorkingArea
    $minX = $workArea.Left - $keyboard.Width + 160
    $maxX = $workArea.Right - 160
    $minY = $workArea.Top
    $maxY = $workArea.Bottom - 44
    if ($x -lt $minX) { $x = $minX }
    if ($x -gt $maxX) { $x = $maxX }
    if ($y -lt $minY) { $y = $minY }
    if ($y -gt $maxY) { $y = $maxY }
    $keyboard.Location = New-Object System.Drawing.Point $x, $y
}
function Stop-Drag {
    $script:dragging = $false
    $dragBar.Capture = $false
    $script:panelRestX = $keyboard.Left
    $script:panelRestY = $keyboard.Top
}
$dragBar.Add_MouseDown({ if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Start-Drag } })
$dragBar.Add_MouseMove({ Move-Drag })
$dragBar.Add_MouseUp({ Stop-Drag })
$dragLabel.Add_MouseDown({ if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Start-Drag } })
$dragLabel.Add_MouseMove({ Move-Drag })
$dragLabel.Add_MouseUp({ Stop-Drag })

$accent = New-Object System.Windows.Forms.Panel
$accent.Dock = [System.Windows.Forms.DockStyle]::None
$accent.Height = 2
$accent.BackColor = $keyBorder
$keyboard.Controls.Add($accent)

Add-KeyRow @("1", "2", "3", "4", "5", "6", "7", "8", "9", "0") $false
Add-KeyRow @("q", "w", "e", "r", "t", "y", "u", "i", "o", "p") $true
Add-KeyRow @("a", "s", "d", "f", "g", "h", "j", "k", "l") $true
Add-KeyRow @("z", "x", "c", "v", "b", "n", "m", ".", "-", "_") $true
Add-KeyRow @("https://", "www.", "/", ":", ".com", "?", "&", "=", "#", "%") $false -weights 22, 14, 8, 8, 14, 8, 8, 8, 8, 8

$windowsButton = New-Key "" { [VncKeyboardWin]::Tap([uint16]0x5B, $false) } 12
$windowsButton.Name = "logo"
$windowsButton.Add_Paint({
    param($sender, $eventArgs)
    $bounds = $sender.ClientRectangle
    $side = [Math]::Min($bounds.Width, $bounds.Height) * 0.46
    if ($side -lt 8) { return }
    $pane = $side * 0.42
    $gap = $side * 0.16
    $originX = ($bounds.Width - ((2 * $pane) + $gap)) / 2
    $originY = ($bounds.Height - ((2 * $pane) + $gap)) / 2
    $brush = New-Object System.Drawing.SolidBrush $keyText
    $eventArgs.Graphics.FillRectangle($brush, $originX, $originY, $pane, $pane)
    $eventArgs.Graphics.FillRectangle($brush, ($originX + $pane + $gap), $originY, $pane, $pane)
    $eventArgs.Graphics.FillRectangle($brush, $originX, ($originY + $pane + $gap), $pane, $pane)
    $eventArgs.Graphics.FillRectangle($brush, ($originX + $pane + $gap), ($originY + $pane + $gap), $pane, $pane)
    $brush.Dispose()
})
$shiftButton = New-Key "Shift" { $script:shift = -not $script:shift; Update-ShiftLabels } 12
$spaceButton = New-Key "Space" { [VncKeyboardWin]::Tap([uint16]0x20, $false) } 12
$backButton = New-Key "Backspace" { [VncKeyboardWin]::Tap([uint16]0x08, $false) } 12
$enterButton = New-Key "Enter" { [VncKeyboardWin]::Tap([uint16]0x0D, $false) } 12
$hideButton = New-Key "Hide keyboard" { Hide-KeyboardPanel } 12
foreach ($action in @($windowsButton, $shiftButton, $spaceButton, $backButton, $enterButton, $hideButton)) {
    $keyboard.Controls.Add($action)
}
[void]$script:keyRows.Add([PSCustomObject]@{ Buttons = @($windowsButton, $shiftButton, $spaceButton, $backButton, $enterButton, $hideButton); Weights = @(12, 14, 24, 18, 14, 26) })

$script:keyFontSize = -1
function Update-KeyboardLayout {
    $clientW = $keyboard.ClientSize.Width
    $clientH = $keyboard.ClientSize.Height
    if ($clientW -lt 40 -or $clientH -lt 40 -or $script:keyRows.Count -eq 0) { return }
    $barH = [Math]::Max(28, [Math]::Min(40, [Math]::Floor($clientH * 0.07)))
    $dragBar.SetBounds(0, 0, $clientW, $barH)
    $accent.SetBounds(0, $barH, $clientW, 2)
    $top = $barH + 6
    $gap = [Math]::Max(3, [Math]::Floor($clientW / 220))
    $rowCount = $script:keyRows.Count
    $rowH = [Math]::Floor(($clientH - $top - ($gap * $rowCount)) / $rowCount)
    if ($rowH -lt 8) { $rowH = 8 }
    $fontSize = [Math]::Max(8, [Math]::Min(28, ($rowH * 0.38)))
    if ([Math]::Abs($script:keyFontSize - $fontSize) -gt 0.4) {
        $script:keyFontSize = $fontSize
        $textFont = New-Object System.Drawing.Font "Segoe UI", $fontSize
        $dragLabel.Font = New-Object System.Drawing.Font "Segoe UI", ([Math]::Max(9, [Math]::Min(14, $barH * 0.38)))
        foreach ($row in $script:keyRows) {
            foreach ($button in $row.Buttons) {
                if ($button.Name -ne "logo") { $button.Font = $textFont }
            }
        }
    }
    $y = $top
    foreach ($row in $script:keyRows) {
        $buttons = @($row.Buttons)
        $weights = @($row.Weights)
        $weightSum = 0
        foreach ($weight in $weights) { $weightSum += $weight }
        if ($weightSum -le 0) { $weightSum = $buttons.Count }
        $inner = [Math]::Max(2, $gap)
        $usable = $clientW - 8 - ($inner * ($buttons.Count - 1))
        $x = 4
        for ($index = 0; $index -lt $buttons.Count; $index++) {
            $keyW = [Math]::Floor($usable * $weights[$index] / $weightSum)
            if ($index -eq ($buttons.Count - 1)) { $keyW = $clientW - 4 - $x }
            $buttons[$index].SetBounds($x, $y, [Math]::Max(8, $keyW), $rowH)
            $x += $keyW + $inner
        }
        $y += $rowH + $inner
    }
    $dragBar.BringToFront()
    $accent.BringToFront()
}

$keyboard.Add_Resize({ Update-KeyboardLayout })
Update-KeyboardLayout

$script:panelRestX = $keyboard.Left
$script:panelRestY = $keyboard.Top
$script:panelFromY = 0.0
$script:panelToY = 0.0
$script:panelFromOpacity = 0.0
$script:panelToOpacity = 1.0
$script:panelStart = [datetime]::UtcNow
$script:panelHide = $false
$script:panelMoving = $false
$script:panelMotion = New-Object System.Windows.Forms.Timer
$script:panelMotion.Interval = 16
$script:panelMotion.Add_Tick({
    if (-not $script:panelMoving -or $keyboard.IsDisposed) { $script:panelMotion.Stop(); return }
    $elapsed = ([datetime]::UtcNow - $script:panelStart).TotalMilliseconds
    $t = 1.0
    if ($elapsed -lt $script:motionMs) { $t = $elapsed / $script:motionMs }
    $ease = [VncKeyboardWin]::Ease([double]$t)
    $y = $script:panelFromY + (($script:panelToY - $script:panelFromY) * $ease)
    $keyboard.Top = [int][Math]::Round($y)
    $opacity = $script:panelFromOpacity + (($script:panelToOpacity - $script:panelFromOpacity) * $ease)
    if ($opacity -lt 0) { $opacity = 0 }
    if ($opacity -gt 1) { $opacity = 1 }
    $keyboard.Opacity = $opacity
    if ($t -ge 1) {
        $script:panelMoving = $false
        $script:panelMotion.Stop()
        $keyboard.Top = [int][Math]::Round($script:panelToY)
        $keyboard.Opacity = $script:panelToOpacity
        if ($script:panelHide) {
            $keyboard.Hide()
            $keyboard.Top = $script:panelRestY
            $keyboard.Opacity = 0
        }
        [VncKeyboardWin]::StayOnTop($buttonForm.Handle)
    }
})

function Start-KeyboardMotion([bool]$show) {
    if ($show) {
        Get-Process -Name osk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (-not $script:keyboardPlaced) {
            $here = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
            $width = [Math]::Min(1040, $here.Width - 80)
            $height = [Math]::Min(380, $here.Height - 160)
            $x = $here.Left + [Math]::Floor(($here.Width - $width) / 2)
            $y = $here.Bottom - $height - 16
            $keyboard.Bounds = New-Object System.Drawing.Rectangle $x, $y, $width, $height
            $script:panelRestX = $keyboard.Left
            $script:panelRestY = $keyboard.Top
            $script:keyboardPlaced = $true
            Update-KeyboardLayout
        }
        $keyboard.Left = $script:panelRestX
        if (-not $keyboard.Visible) {
            $keyboard.Top = $script:panelRestY + $keyboard.Height
            $keyboard.Opacity = 0
            $keyboard.Show()
        }
        $script:panelFromY = $keyboard.Top
        $script:panelToY = $script:panelRestY
        $script:panelFromOpacity = [double]$keyboard.Opacity
        $script:panelToOpacity = 1
        $script:panelHide = $false
    } else {
        if (-not $keyboard.Visible) { return }
        $script:panelFromY = $keyboard.Top
        $script:panelToY = $script:panelRestY + $keyboard.Height
        $script:panelFromOpacity = [double]$keyboard.Opacity
        $script:panelToOpacity = 0
        $script:panelHide = $true
    }
    $script:panelStart = [datetime]::UtcNow
    $script:panelMoving = $true
    $keyboard.TopMost = $true
    [VncKeyboardWin]::StayOnTop($keyboard.Handle)
    [VncKeyboardWin]::StayOnTop($buttonForm.Handle)
    $script:panelMotion.Start()
}

function Show-KeyboardPanel { Start-KeyboardMotion $true }
function Hide-KeyboardPanel { Start-KeyboardMotion $false }

$script:buttonIntroTimer = New-Object System.Windows.Forms.Timer
$script:buttonIntroTimer.Interval = 16
$script:buttonIntroStart = [datetime]::UtcNow
$script:buttonIntroTimer.Add_Tick({
    if (-not $script:buttonIntro -or $buttonForm.IsDisposed) { $script:buttonIntroTimer.Stop(); return }
    $elapsed = ([datetime]::UtcNow - $script:buttonIntroStart).TotalMilliseconds
    $t = 1.0
    if ($elapsed -lt $script:motionMs) { $t = $elapsed / $script:motionMs }
    $ease = [VncKeyboardWin]::Ease([double]$t)
    $buttonForm.Opacity = $script:buttonOpacity * $ease
    $buttonForm.Top = [int][Math]::Round($script:buttonHome.Y + ((1 - $ease) * $buttonForm.Height))
    $buttonForm.Left = $script:buttonHome.X
    if ($t -ge 1) {
        $script:buttonIntro = $false
        $buttonForm.Opacity = $script:buttonOpacity
        $buttonForm.Location = $script:buttonHome
        $script:buttonIntroTimer.Stop()
    }
})

$script:iconDown = $false
$script:iconMoved = $false
$script:iconCursor = $null
$script:iconOrigin = $null
function Move-KeyboardIcon {
    if (-not $script:iconDown) { return }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $dx = $cursor.X - $script:iconCursor.X
    $dy = $cursor.Y - $script:iconCursor.Y
    if (-not $script:iconMoved -and [Math]::Abs($dx) -lt 24 -and [Math]::Abs($dy) -lt 24) { return }
    $script:iconMoved = $true
    $x = $script:iconOrigin.X + $dx
    $y = $script:iconOrigin.Y + $dy
    $workArea = [System.Windows.Forms.Screen]::FromPoint($cursor).WorkingArea
    $maxX = $workArea.Right - $buttonForm.Width
    $maxY = $workArea.Bottom - $buttonForm.Height
    if ($x -lt $workArea.Left) { $x = $workArea.Left }
    if ($y -lt $workArea.Top) { $y = $workArea.Top }
    if ($x -gt $maxX) { $x = $maxX }
    if ($y -gt $maxY) { $y = $maxY }
    $buttonForm.Location = New-Object System.Drawing.Point $x, $y
}
$icon.Add_MouseDown({
    if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    if ($script:buttonIntro) {
        $script:buttonIntro = $false
        $script:buttonIntroTimer.Stop()
        $buttonForm.Opacity = $script:buttonOpacity
    }
    $script:iconDown = $true
    $script:iconMoved = $false
    $script:iconCursor = [System.Windows.Forms.Cursor]::Position
    $script:iconOrigin = $buttonForm.Location
    $icon.Capture = $true
})
$icon.Add_MouseMove({ Move-KeyboardIcon })
$icon.Add_MouseUp({
    if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $dragged = $script:iconMoved
    $script:iconDown = $false
    $icon.Capture = $false
    if ($dragged) { return }
    if ($keyboard.Visible -and -not $script:panelHide) { Hide-KeyboardPanel } else { Show-KeyboardPanel }
})

$script:previewMode = [bool]$Preview
$openedAt = Get-Date
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if ($script:previewMode) { return }
    if (((Get-Date) - $openedAt).TotalSeconds -lt 8) { return }
    if (-not (Get-Process -Name vncviewer -ErrorAction SilentlyContinue)) {
        $keyboard.Hide()
        $buttonForm.Close()
    }
})
$timer.Start()
$script:buttonIntroStart = [datetime]::UtcNow
$script:buttonIntroTimer.Start()
if ($script:previewMode) { Show-KeyboardPanel }
$buttonForm.Add_FormClosed({ $keyboard.Close() })
[System.Windows.Forms.Application]::Run($buttonForm)
$mutex.ReleaseMutex() | Out-Null
$mutex.Dispose()
} catch {
    try { $_ | Out-File -FilePath "C:\layouts\keyboard-error.txt" -Encoding utf8 } catch {}
    try { $mutex.ReleaseMutex() | Out-Null } catch {}
    $mutex.Dispose()
    throw
}
