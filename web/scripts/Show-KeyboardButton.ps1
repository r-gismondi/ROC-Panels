# Small always-on-top keyboard button for the touchscreen while VNC is open.
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
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class KeyboardButtonWin {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    public static void NoActivate(IntPtr hwnd) {
        int ex = GetWindowLong(hwnd, -20);
        ex |= 0x08000000;
        ex |= 0x00000008;
        SetWindowLong(hwnd, -20, ex);
    }
}
"@

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.BackColor = [System.Drawing.Color]::FromArgb(8, 47, 140)
$form.Size = New-Object System.Drawing.Size 112, 112
$form.Text = "Keyboard"
$form.Add_HandleCreated({ [KeyboardButtonWin]::NoActivate($form.Handle) })

$button = New-Object System.Windows.Forms.Button
$button.Dock = [System.Windows.Forms.DockStyle]::Fill
$button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$button.FlatAppearance.BorderSize = 0
$button.Font = New-Object System.Drawing.Font "Segoe UI Symbol", 36
$button.ForeColor = [System.Drawing.Color]::White
$button.BackColor = [System.Drawing.Color]::FromArgb(8, 47, 140)
$button.Text = [string]([char]0x2328)
$button.TabStop = $false
$form.Controls.Add($button)

$screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
$area = $screen.WorkingArea
$margin = 24
$form.Location = New-Object System.Drawing.Point ($area.Right - $form.Width - $margin), ($area.Bottom - $form.Height - $margin)

$button.Add_Click({
    $running = @(Get-Process -Name osk -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        return
    }
    Start-Process -FilePath "$env:SystemRoot\System32\osk.exe"
})

$openedAt = Get-Date
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    $form.TopMost = $true
    if (((Get-Date) - $openedAt).TotalSeconds -lt 8) { return }
    if (-not (Get-Process -Name vncviewer -ErrorAction SilentlyContinue)) { $form.Close() }
})
$timer.Start()
[System.Windows.Forms.Application]::Run($form)
$mutex.ReleaseMutex() | Out-Null
$mutex.Dispose()
} catch {
    try { $mutex.ReleaseMutex() | Out-Null } catch {}
    $mutex.Dispose()
    throw
}
