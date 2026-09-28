param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Minimize", "Close")]
    [string]$Action
)
$ErrorActionPreference = "Stop"
if (-not ("ConsoleWindow" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ConsoleWindow {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
}
"@
}
$script:found = New-Object System.Collections.Generic.List[IntPtr]
[ConsoleWindow]::EnumWindows({
    param($hwnd, $lParam)
    if (-not [ConsoleWindow]::IsWindowVisible($hwnd)) { return $true }
    $buffer = New-Object System.Text.StringBuilder 512
    [void][ConsoleWindow]::GetWindowText($hwnd, $buffer, $buffer.Capacity)
    $title = $buffer.ToString()
    if (-not $title.StartsWith("Remote Operation Center")) { return $true }
    $processId = [uint32]0
    [void][ConsoleWindow]::GetWindowThreadProcessId($hwnd, [ref]$processId)
    $name = ""
    try { $name = (Get-Process -Id $processId -ErrorAction Stop).ProcessName } catch { $name = "" }
    if ($name -ne "msedge" -and $name -ne "chrome") { return $true }
    $script:found.Add($hwnd)
    return $true
}, [IntPtr]::Zero) | Out-Null
if ($script:found.Count -eq 0) { throw "The console window is not open." }
$hwnd = $script:found[$script:found.Count - 1]
if ($Action -eq "Minimize") {
    [void][ConsoleWindow]::ShowWindow($hwnd, 6)
} else {
    [void][ConsoleWindow]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
}
Write-Output "ok"
