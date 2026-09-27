# Runs on the wall PC's signed-in desktop and starts layout batches as soon as they are queued.
$ErrorActionPreference = "Continue"
$root = "C:\layouts"
$queue = Join-Path $root "queue"
$alive = Join-Path $root "watcher-alive.txt"
New-Item -ItemType Directory -Force -Path $queue | Out-Null

$mutex = New-Object System.Threading.Mutex($false, "WallLayoutWatch")
if (-not $mutex.WaitOne(0)) { exit 0 }

$lastBeat = [datetime]::MinValue
while ($true) {
    $now = Get-Date
    if (($now - $lastBeat).TotalMilliseconds -ge 500) {
        Set-Content -LiteralPath $alive -Value $now.ToString("o") -Encoding Ascii
        $lastBeat = $now
    }
    $items = @(Get-ChildItem -LiteralPath $queue -Filter *.txt -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($item in $items) {
        $bat = ""
        try { $bat = (Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop).Trim() } catch { continue }
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
        if (-not $bat -or -not (Test-Path -LiteralPath $bat)) { continue }
        $work = Split-Path -Parent $bat
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "start", '""', $bat -WorkingDirectory $work | Out-Null
    }
    Start-Sleep -Milliseconds 40
}
