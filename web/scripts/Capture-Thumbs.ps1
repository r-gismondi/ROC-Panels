# Saves a small JPEG of each physical screen on this wall PC.
$ErrorActionPreference = "Stop"
$mutex = New-Object System.Threading.Mutex($false, "WallThumbs")
$owned = $false
try {
    $owned = $mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $owned = $true
}
if (-not $owned) { exit 0 }

Add-Type -AssemblyName System.Drawing
if (-not ("ThumbDpi" -as [type])) {
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class ThumbDpi {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
}
[void][ThumbDpi]::SetProcessDPIAware()

function Get-WallComputer {
    $ips = @([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | ForEach-Object { $_.ToString() })
    if ($ips -contains "192.168.0.101") { return "101" }
    if ($ips -contains "192.168.0.102") { return "102" }
    if ($ips -contains "192.168.0.103") { return "103" }
    return ""
}

$computer = Get-WallComputer
if (-not $computer) { exit 0 }

$tiles = @{
    "101" = @(
        @{ Name = "TV1"; X = 0; Y = 0; W = 960; H = 540 }
        @{ Name = "TV2"; X = 960; Y = 0; W = 960; H = 540 }
        @{ Name = "TV3"; X = 1920; Y = 0; W = 960; H = 540 }
        @{ Name = "TV4"; X = 2880; Y = 0; W = 960; H = 540 }
        @{ Name = "TV5"; X = 0; Y = 540; W = 960; H = 540 }
        @{ Name = "TV6"; X = 960; Y = 540; W = 960; H = 540 }
        @{ Name = "TV7"; X = 1920; Y = 540; W = 960; H = 540 }
        @{ Name = "TV8"; X = 2880; Y = 540; W = 960; H = 540 }
    )
    "102" = @(
        @{ Name = "TV9"; X = 0; Y = 0; W = 960; H = 540 }
        @{ Name = "TV10"; X = 960; Y = 0; W = 960; H = 540 }
        @{ Name = "TV11"; X = 1920; Y = 0; W = 960; H = 540 }
        @{ Name = "TV12"; X = 2880; Y = 0; W = 960; H = 540 }
        @{ Name = "TV14"; X = 0; Y = 540; W = 960; H = 540 }
        @{ Name = "TV15"; X = 960; Y = 540; W = 960; H = 540 }
        @{ Name = "TV16"; X = 1920; Y = 540; W = 960; H = 540 }
        @{ Name = "TV17"; X = 2880; Y = 540; W = 960; H = 540 }
    )
    "103" = @(
        @{ Name = "TV13"; X = 0; Y = 0; W = 1920; H = 1080 }
        @{ Name = "TV18"; X = 0; Y = 1080; W = 1920; H = 1080 }
    )
}

$dir = "C:\layouts\thumbs"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$codec = @([System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }) | Select-Object -First 1

function Save-Tile($tile) {
    $src = $null
    $graphics = $null
    $thumb = $null
    $scaled = $null
    $params = $null
    try {
        $src = New-Object System.Drawing.Bitmap ([int]$tile.W), ([int]$tile.H)
        $graphics = [System.Drawing.Graphics]::FromImage($src)
        $graphics.CopyFromScreen([int]$tile.X, [int]$tile.Y, 0, 0, (New-Object System.Drawing.Size ([int]$tile.W), ([int]$tile.H)))
        $thumbW = 240
        $thumbH = [Math]::Max(1, [int]($tile.H * $thumbW / $tile.W))
        $thumb = New-Object System.Drawing.Bitmap $thumbW, $thumbH
        $scaled = [System.Drawing.Graphics]::FromImage($thumb)
        $scaled.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        $scaled.DrawImage($src, 0, 0, $thumbW, $thumbH)
        $target = Join-Path $dir "$($tile.Name).jpg"
        $temp = "$target.writing"
        $params = New-Object System.Drawing.Imaging.EncoderParameters 1
        $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]60)
        $thumb.Save($temp, $codec, $params)
        Move-Item -LiteralPath $temp -Destination $target -Force
    } catch {
        # That part of the desktop is not available.
    } finally {
        if ($params) { $params.Dispose() }
        if ($scaled) { $scaled.Dispose() }
        if ($thumb) { $thumb.Dispose() }
        if ($graphics) { $graphics.Dispose() }
        if ($src) { $src.Dispose() }
    }
}

while ($true) {
    Set-Content -LiteralPath (Join-Path $dir "alive.txt") -Value (Get-Date).ToString("o") -Encoding Ascii
    foreach ($tile in $tiles[$computer]) { Save-Tile $tile }
    Start-Sleep -Milliseconds 1500
}
