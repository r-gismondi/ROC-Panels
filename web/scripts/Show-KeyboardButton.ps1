# Touch keyboard for a VNC session. Same layout and colors as the console keyboard.
# Keys are typed into the VNC window, so this panel does not take focus.
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

$panelBg = [System.Drawing.Color]::FromArgb(3, 16, 46)
$keyBg = [System.Drawing.Color]::FromArgb(8, 36, 95)
$keyBorder = [System.Drawing.Color]::FromArgb(72, 150, 170)
$cyan = [System.Drawing.Color]::FromArgb(125, 211, 252)
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
    $shiftButton.FlatAppearance.BorderColor = if ($script:shift) { [System.Drawing.Color]::White } else { $keyBorder }
    $shiftButton.BackColor = if ($script:shift) { [System.Drawing.Color]::FromArgb(16, 78, 168) } else { $keyBg }
}

function Send-Char([string]$ch, [bool]$useShift) {
    $vk = $null
    $shifted = $false
    if ($ch -match '^[a-zA-Z]$') {
        $vk = [uint16][byte][char]$ch.ToUpper()
        $shifted = $useShift -or [char]::IsUpper($ch)
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
    $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(14, 58, 130)
    $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(20, 78, 160)
    $button.BackColor = $keyBg
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font "Segoe UI", $fontSize
    $button.TabStop = $false
    $button.Add_MouseUp({
        param($sender, $eventArgs)
        if ($eventArgs.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        & $sender.Tag
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
            $captured = $lower
            $button.Tag = { Send-Char $captured $script:shift; if ($script:shift) { $script:shift = $false; Update-ShiftLabels } }.GetNewClosure()
            $script:shiftables += [PSCustomObject]@{ Button = $button; Lower = $lower; Upper = $lower.ToUpper() }
        } elseif ($label -in @("https://", "www.", ".com")) {
            $captured = $label
            $button = New-Key $label { } 12
            $button.Tag = { Send-Text $captured }.GetNewClosure()
        } else {
            $captured = $label
            $button = New-Key $label { } 12
            $button.Tag = { Send-Char $captured $false }.GetNewClosure()
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
$buttonForm.BackColor = [System.Drawing.Color]::FromArgb(8, 47, 140)
$buttonForm.Size = New-Object System.Drawing.Size 112, 112
$buttonForm.Text = "Keyboard"
$buttonForm.Add_HandleCreated({ [VncKeyboardWin]::NoActivate($buttonForm.Handle) })
Set-Round $buttonForm

$icon = New-Object System.Windows.Forms.Button
$icon.Dock = [System.Windows.Forms.DockStyle]::Fill
$icon.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$icon.FlatAppearance.BorderSize = 0
$icon.Font = New-Object System.Drawing.Font "Segoe UI Symbol", 36
$icon.ForeColor = [System.Drawing.Color]::White
$icon.BackColor = [System.Drawing.Color]::FromArgb(8, 47, 140)
$icon.Text = [string]([char]0x2328)
$icon.TabStop = $false
$buttonForm.Controls.Add($icon)
$margin = 24
$buttonForm.Location = New-Object System.Drawing.Point ($area.Right - $buttonForm.Width - $margin), ($area.Bottom - $buttonForm.Height - $margin)

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
$dragBar.BackColor = [System.Drawing.Color]::FromArgb(7, 26, 77)
$dragBar.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$keyboard.Controls.Add($dragBar)

$dragLabel = New-Object System.Windows.Forms.Label
$dragLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$dragLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$dragLabel.Padding = New-Object System.Windows.Forms.Padding 16, 0, 0, 0
$dragLabel.ForeColor = $cyan
$dragLabel.BackColor = $dragBar.BackColor
$dragLabel.Font = New-Object System.Drawing.Font "Segoe UI", 12
$dragLabel.Text = "Drag to move"
$dragLabel.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$dragBar.Controls.Add($dragLabel)

$script:dragging = $false
$script:dragCursor = $null
$script:dragOrigin = $null
function Start-Drag {
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
$accent.BackColor = $cyan
$keyboard.Controls.Add($accent)

Add-KeyRow @("1", "2", "3", "4", "5", "6", "7", "8", "9", "0") $false
Add-KeyRow @("q", "w", "e", "r", "t", "y", "u", "i", "o", "p") $true
Add-KeyRow @("a", "s", "d", "f", "g", "h", "j", "k", "l") $true
Add-KeyRow @("z", "x", "c", "v", "b", "n", "m", ".", "-", "_") $true
Add-KeyRow @("https://", "www.", "/", ":", ".com", "?", "&", "=", "#", "%") $false

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
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
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
$hideButton = New-Key "Hide keyboard" { $keyboard.Hide() } 12
foreach ($action in @($windowsButton, $shiftButton, $spaceButton, $backButton, $enterButton, $hideButton)) {
    $keyboard.Controls.Add($action)
}
[void]$script:keyRows.Add([PSCustomObject]@{ Buttons = @($windowsButton, $shiftButton, $spaceButton, $backButton, $enterButton, $hideButton); Weights = @(14, 14, 30, 16, 14, 18) })

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
    foreach ($control in @($keyboard.Controls)) {
        if ($control.Tag -in @("nw", "ne", "sw", "se")) { $control.BringToFront() }
    }
}

$script:resizing = $false
$script:resizeCorner = ""
$script:resizeCursor = $null
$script:resizeBounds = $null
function Start-Resize([string]$corner, [System.Windows.Forms.Control]$grip) {
    $script:resizing = $true
    $script:resizeCorner = $corner
    $script:resizeCursor = [System.Windows.Forms.Cursor]::Position
    $script:resizeBounds = $keyboard.Bounds
    $grip.Capture = $true
}
function Move-Resize {
    if (-not $script:resizing) { return }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $dx = $cursor.X - $script:resizeCursor.X
    $dy = $cursor.Y - $script:resizeCursor.Y
    $bounds = $script:resizeBounds
    $x = $bounds.X
    $y = $bounds.Y
    $w = $bounds.Width
    $h = $bounds.Height
    switch ($script:resizeCorner) {
        "se" { $w += $dx; $h += $dy }
        "sw" { $x += $dx; $w -= $dx; $h += $dy }
        "ne" { $y += $dy; $w += $dx; $h -= $dy }
        "nw" { $x += $dx; $y += $dy; $w -= $dx; $h -= $dy }
    }
    if ($w -lt 760) {
        if ($script:resizeCorner -in @("sw", "nw")) { $x -= (760 - $w) }
        $w = 760
    }
    if ($h -lt 300) {
        if ($script:resizeCorner -in @("ne", "nw")) { $y -= (300 - $h) }
        $h = 300
    }
    $workArea = [System.Windows.Forms.Screen]::FromPoint($cursor).WorkingArea
    if ($w -gt $workArea.Width) { $w = $workArea.Width }
    if ($h -gt ($workArea.Height - 24)) { $h = $workArea.Height - 24 }
    $keyboard.Bounds = New-Object System.Drawing.Rectangle $x, $y, $w, $h
    Update-KeyboardLayout
}
function New-Corner([string]$corner) {
    $grip = New-Object System.Windows.Forms.Panel
    $grip.Size = New-Object System.Drawing.Size 36, 36
    $grip.BackColor = [System.Drawing.Color]::FromArgb(18, 92, 176)
    $grip.Tag = $corner
    switch ($corner) {
        "nw" { $grip.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left; $grip.Location = New-Object System.Drawing.Point 0, 0; $grip.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE }
        "ne" { $grip.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right; $grip.Location = New-Object System.Drawing.Point ($keyboard.ClientSize.Width - 36), 0; $grip.Cursor = [System.Windows.Forms.Cursors]::SizeNESW }
        "sw" { $grip.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left; $grip.Location = New-Object System.Drawing.Point 0, ($keyboard.ClientSize.Height - 36); $grip.Cursor = [System.Windows.Forms.Cursors]::SizeNESW }
        "se" { $grip.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right; $grip.Location = New-Object System.Drawing.Point ($keyboard.ClientSize.Width - 36), ($keyboard.ClientSize.Height - 36); $grip.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE }
    }
    $grip.Add_MouseDown({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Start-Resize $this.Tag $this }
    })
    $grip.Add_MouseMove({ Move-Resize })
    $grip.Add_MouseUp({
        $script:resizing = $false
        $this.Capture = $false
    })
    $keyboard.Controls.Add($grip)
    $grip.BringToFront()
}
New-Corner "nw"
New-Corner "ne"
New-Corner "sw"
New-Corner "se"
$keyboard.Add_Resize({
    Update-KeyboardLayout
    foreach ($control in @($keyboard.Controls)) {
        if ($control.Tag -in @("nw", "ne", "sw", "se")) { $control.BringToFront() }
    }
})
Update-KeyboardLayout

function Show-KeyboardPanel {
    Get-Process -Name osk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if (-not $script:keyboardPlaced) {
        $here = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
        $width = [Math]::Min(1040, $here.Width - 80)
        $height = [Math]::Min(380, $here.Height - 160)
        $x = $here.Left + [Math]::Floor(($here.Width - $width) / 2)
        $y = $here.Bottom - $height - 16
        $keyboard.Bounds = New-Object System.Drawing.Rectangle $x, $y, $width, $height
        $script:keyboardPlaced = $true
    }
    $keyboard.Show()
    $keyboard.TopMost = $true
    [VncKeyboardWin]::StayOnTop($keyboard.Handle)
    Update-KeyboardLayout
}

$icon.Add_MouseUp({
    if ($keyboard.Visible) { $keyboard.Hide() } else { Show-KeyboardPanel }
})

$openedAt = Get-Date
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if (((Get-Date) - $openedAt).TotalSeconds -lt 8) { return }
    if (-not (Get-Process -Name vncviewer -ErrorAction SilentlyContinue)) {
        $keyboard.Hide()
        $buttonForm.Close()
    }
})
$timer.Start()
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
