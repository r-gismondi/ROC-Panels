# Reloads open Edge pages on this wall PC through the shared DevTools port.
# Queued from the pedestal so it works without restarting Show-Edge.ps1.
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

try {
    Write-Result "working"
    $list = @()
    try {
        $list = @(Invoke-RestMethod -Uri 'http://127.0.0.1:9333/json/list' -TimeoutSec 3)
    } catch {
        Write-Result "error Edge is not open on those screens."
        exit 1
    }
    $pages = @(
        $list | Where-Object {
            $_.type -eq 'page' -and $_.webSocketDebuggerUrl -and $_.url -notmatch '^devtools://'
        }
    )
    if ($pages.Count -eq 0) {
        Write-Result "empty"
        exit 0
    }
    $ok = 0
    foreach ($page in $pages) {
        if (Refresh-Page ([string]$page.webSocketDebuggerUrl)) { $ok += 1 }
    }
    if ($ok -lt 1) {
        Write-Result "error The pages did not refresh."
        exit 1
    }
    Write-Result "ok"
    exit 0
} catch {
    $reason = $_.Exception.Message
    if (-not $reason) { $reason = "The pages did not refresh." }
    $reason = ($reason -replace '[\r\n]+', ' ')
    try { Write-Result "error $reason" } catch {}
    exit 1
}
