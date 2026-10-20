# Reloads open Edge pages on this wall PC through the shared DevTools port.
# Queued from the pedestal so it works without restarting Show-Edge.ps1.
# Falls back to F5 on the recorded layout windows when the debug port is down.
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Screen = "ALL"
)

$ErrorActionPreference = "Stop"
$resultDir = Join-Path $Root "refresh-results"
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$safeScreen = if ($Screen -match '^(ALL|TV([1-9]|1[0-8]))$') { $Screen } else { "ALL" }
$resultPath = Join-Path $resultDir "$safeScreen.txt"
$utf8 = New-Object System.Text.UTF8Encoding $false

function Write-Result([string]$Text) {
    [System.IO.File]::WriteAllText($resultPath, $Text, $utf8)
}

if (-not ("RefreshWin" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class RefreshWin {
    public const uint WM_KEYDOWN = 0x0100;
    public const uint WM_KEYUP = 0x0101;
    public const int VK_F5 = 0x74;
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
}
"@
}

function New-CdpTimeout([int]$Milliseconds) {
    $source = New-Object System.Threading.CancellationTokenSource
    $source.CancelAfter($Milliseconds)
    return $source
}

function Send-CdpMessage($Socket, [string]$Payload) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
    $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (, $bytes)
    $cancel = New-CdpTimeout 2000
    try {
        $null = $Socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cancel.Token).GetAwaiter().GetResult()
    } finally { $cancel.Dispose() }
}

function Receive-CdpMessage($Socket) {
    $buffer = New-Object byte[] 131072
    $stream = New-Object System.IO.MemoryStream
    $cancel = New-CdpTimeout 2000
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

function Invoke-Cdp($Socket, [int]$Id, [string]$Method, $Params) {
    $body = @{ id = $Id; method = $Method }
    if ($null -ne $Params) { $body.params = $Params }
    Send-CdpMessage $Socket ($body | ConvertTo-Json -Compress -Depth 6)
    $deadline = (Get-Date).AddSeconds(2)
    while ((Get-Date) -lt $deadline) {
        $raw = Receive-CdpMessage $Socket
        if (-not $raw) { continue }
        $reply = $raw | ConvertFrom-Json
        if ($reply.id -eq $Id) { return $reply }
    }
    return $null
}

function Open-CdpSocket([string]$Url) {
    $socket = New-Object System.Net.WebSockets.ClientWebSocket
    $cancel = New-CdpTimeout 2000
    try {
        $socket.ConnectAsync([Uri]$Url, $cancel.Token).GetAwaiter().GetResult() | Out-Null
        return $socket
    } catch {
        try { $socket.Dispose() } catch {}
        throw
    } finally { $cancel.Dispose() }
}

function Refresh-Page([string]$DebuggerUrl) {
    $socket = $null
    try {
        $socket = Open-CdpSocket $DebuggerUrl
        $reply = Invoke-Cdp $socket 1 'Page.reload' @{ ignoreCache = $false }
        if (-not $reply -or $reply.error) { return $false }
        return $true
    } catch {
        return $false
    } finally {
        if ($socket) { try { $socket.Dispose() } catch {} }
    }
}

function Get-LayoutHwnds {
    $hwndFile = Join-Path $Root "edge-layout.hwnds"
    if (-not (Test-Path -LiteralPath $hwndFile)) { return @() }
    $list = @()
    foreach ($line in @(Get-Content -LiteralPath $hwndFile -ErrorAction SilentlyContinue)) {
        $value = 0L
        if (-not [int64]::TryParse(([string]$line).Trim(), [ref]$value) -or $value -eq 0) { continue }
        $hwnd = [IntPtr]$value
        if ([RefreshWin]::IsWindow($hwnd)) { $list += $hwnd }
    }
    return $list
}

function Refresh-Hwnds {
    $hwnds = @(Get-LayoutHwnds)
    if ($hwnds.Count -lt 1) { return $false }
    $ok = 0
    foreach ($hwnd in $hwnds) {
        $down = [RefreshWin]::PostMessage($hwnd, [RefreshWin]::WM_KEYDOWN, [IntPtr][RefreshWin]::VK_F5, [IntPtr]0x00390001)
        $up = [RefreshWin]::PostMessage($hwnd, [RefreshWin]::WM_KEYUP, [IntPtr][RefreshWin]::VK_F5, [IntPtr]0xC0390001)
        if ($down -or $up) { $ok += 1 }
    }
    return ($ok -gt 0)
}

function Refresh-ViaCdp {
    $list = @()
    try {
        $list = @(Invoke-RestMethod -Uri 'http://127.0.0.1:9333/json/list' -TimeoutSec 3)
    } catch {
        return "down"
    }
    $pages = @(
        $list | Where-Object {
            $_.type -eq 'page' -and $_.webSocketDebuggerUrl -and $_.url -notmatch '^devtools://'
        }
    )
    if ($pages.Count -eq 0) { return "empty" }
    $ok = 0
    foreach ($page in $pages) {
        if (Refresh-Page ([string]$page.webSocketDebuggerUrl)) { $ok += 1 }
    }
    if ($ok -lt 1) { return "fail" }
    return "ok"
}

try {
    Write-Result "working"
    $cdp = Refresh-ViaCdp
    if ($cdp -eq "ok") {
        Write-Result "ok"
        exit 0
    }
    if ($cdp -eq "empty" -and @(Get-LayoutHwnds).Count -lt 1) {
        Write-Result "empty"
        exit 0
    }
    if (Refresh-Hwnds) {
        Write-Result "ok"
        exit 0
    }
    if ($cdp -eq "down" -and @(Get-LayoutHwnds).Count -lt 1) {
        Write-Result "error Edge is not open on those screens."
        exit 1
    }
    Write-Result "error The pages did not refresh."
    exit 1
} catch {
    $reason = $_.Exception.Message
    if (-not $reason) { $reason = "The pages did not refresh." }
    $reason = ($reason -replace '[\r\n]+', ' ')
    try { Write-Result "error $reason" } catch {}
    exit 1
}
