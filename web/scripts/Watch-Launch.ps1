# Runs on the wall PC's signed-in desktop and starts layout batches as soon as they are queued.
$ErrorActionPreference = "Continue"
$root = "C:\layouts"
$queue = Join-Path $root "queue"
$alive = Join-Path $root "watcher-alive.txt"
New-Item -ItemType Directory -Force -Path $queue | Out-Null

$mutex = New-Object System.Threading.Mutex($false, "WallLayoutWatch")
$owned = $false
try {
    $owned = $mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $owned = $true
}
if (-not $owned) { exit 0 }

$stamp = Join-Path $root "watcher-script.txt"
try {
    $launchHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLower()
    $startHash = (Get-FileHash -LiteralPath (Join-Path $root "Start-Watch.bat") -Algorithm SHA256).Hash.ToLower()
    Set-Content -LiteralPath $stamp -Value "$launchHash $startHash" -Encoding Ascii
} catch {}

$thumbs = Join-Path $root "Capture-Thumbs.ps1"
if (Test-Path -LiteralPath $thumbs) {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", $thumbs -WindowStyle Hidden
}

$script:lastBeat = [datetime]::MinValue
function Update-Beat {
    $now = Get-Date
    if (($now - $script:lastBeat).TotalMilliseconds -ge 500) {
        Set-Content -LiteralPath $alive -Value $now.ToString("o") -Encoding Ascii
        $script:lastBeat = $now
    }
}

while ($true) {
    Update-Beat
    $items = @(Get-ChildItem -LiteralPath $queue -Filter *.txt -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($item in $items) {
        $bat = ""
        try { $bat = (Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop).Trim() } catch { continue }
        if (-not $bat -or -not (Test-Path -LiteralPath $bat)) {
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
            continue
        }
        $work = Split-Path -Parent $bat
        if ($bat -like "*Edge-Close.bat") {
            try {
                $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $bat -WorkingDirectory $work -WindowStyle Hidden -PassThru
                while ($proc -and -not $proc.HasExited) {
                    Update-Beat
                    Start-Sleep -Milliseconds 200
                }
            } catch {}
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
            continue
        }
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
        try {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $bat -WorkingDirectory $work -WindowStyle Normal
        } catch {}
    }
    Start-Sleep -Milliseconds 40
}
