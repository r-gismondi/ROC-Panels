# Builds dist\ROC-Panels, a folder you copy to the 55" pedestal.
# ROC-Panels.exe opens the console full screen. The pedestal does not need Node or Python installed.
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$web = Join-Path $repo "web"
$dist = Join-Path $repo "dist\ROC-Panels"
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$pythonVersion = "3.12.10"
$pythonZip = Join-Path $PSScriptRoot "cache\python-$pythonVersion-embed-amd64.zip"
$pythonUrl = "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-embed-amd64.zip"

if (-not (Test-Path -LiteralPath $csc)) { throw "The .NET compiler was not found at $csc" }

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCommand) { throw "node was not found on PATH. Install Node.js or add it before building." }
$nodeExe = $nodeCommand.Source

Write-Host "Building the console..."
Push-Location $web
try {
    & $nodeExe .\scripts\repair-next-picocolors.cjs build
    if ($LASTEXITCODE -ne 0) { throw "next build failed" }
} finally {
    Pop-Location
}

$standalone = Join-Path $web ".next\standalone"
$serverJs = Get-ChildItem -LiteralPath $standalone -Recurse -Filter server.js | Where-Object { $_.FullName -notmatch '\\node_modules\\' } | Select-Object -First 1
if (-not $serverJs) { throw "The standalone server was not produced." }

# Keep operator-owned files out of the wiped install folder (also stored under %LOCALAPPDATA%\ROC-Panels).
$operatorData = Join-Path $env:LOCALAPPDATA "ROC-Panels"
if (Test-Path -LiteralPath $dist) {
    New-Item -ItemType Directory -Force -Path $operatorData | Out-Null
    foreach ($name in @("saved-links.json", "custom-views.json", "pinned-apps.json")) {
        $source = Join-Path $dist $name
        $destination = Join-Path $operatorData $name
        if ((Test-Path -LiteralPath $source) -and -not (Test-Path -LiteralPath $destination)) {
            Copy-Item -LiteralPath $source -Destination $destination
        }
    }
    $iconSource = Join-Path $dist "program-icons"
    $iconDestination = Join-Path $operatorData "program-icons"
    if ((Test-Path -LiteralPath $iconSource) -and -not (Test-Path -LiteralPath $iconDestination)) {
        Copy-Item -LiteralPath $iconSource -Destination $iconDestination -Recurse
    }
    Remove-Item -LiteralPath $dist -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$serverDir = Join-Path $dist "server"
Copy-Item -LiteralPath $serverJs.DirectoryName -Destination $serverDir -Recurse
$staticSource = Join-Path $web ".next\static"
$staticDest = Join-Path $serverDir ".next\static"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $staticDest) | Out-Null
Copy-Item -LiteralPath $staticSource -Destination $staticDest -Recurse
Copy-Item -LiteralPath (Join-Path $web "public") -Destination (Join-Path $serverDir "public") -Recurse

$nodeDir = Join-Path $dist "node"
New-Item -ItemType Directory -Force -Path $nodeDir | Out-Null
Copy-Item -LiteralPath $nodeExe -Destination (Join-Path $nodeDir "node.exe")

if (-not (Test-Path -LiteralPath $pythonZip)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pythonZip) | Out-Null
    Write-Host "Downloading Python $pythonVersion..."
    curl.exe -L --fail -o $pythonZip $pythonUrl
    if ($LASTEXITCODE -ne 0) { throw "Could not download Python." }
}
$pythonDir = Join-Path $dist "python"
New-Item -ItemType Directory -Force -Path $pythonDir | Out-Null
tar.exe -xf $pythonZip -C $pythonDir
$pth = Get-ChildItem -LiteralPath $pythonDir -Filter "python*._pth" | Select-Object -First 1
if (-not $pth) { throw "Python embed did not include a ._pth file." }
@(
    "python312.zip"
    "."
    ".."
    "import site"
) | Set-Content -LiteralPath $pth.FullName -Encoding Ascii

Copy-Item -LiteralPath (Join-Path $repo "samsung_controller") -Destination (Join-Path $dist "samsung_controller") -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $dist "config") | Out-Null
Copy-Item -LiteralPath (Join-Path $repo "config\panels.json") -Destination (Join-Path $dist "config\panels.json")
$scripts = Join-Path $dist "scripts"
New-Item -ItemType Directory -Force -Path $scripts | Out-Null
foreach ($name in @("Watch-Launch.ps1", "Start-Watch.bat", "Launch-InSession.ps1", "Show-RemoteSession.ps1", "Set-ConsoleWindow.ps1", "Capture-Thumbs.ps1", "Start-Thumbs.bat", "Watch-TypeField.ps1", "Refresh-Edge.ps1")) {
    Copy-Item -LiteralPath (Join-Path $web "scripts\$name") -Destination (Join-Path $scripts $name)
}
Copy-Item -LiteralPath (Join-Path $repo "layouts") -Destination (Join-Path $dist "layouts") -Recurse

$layoutUser = "Administrator"
$layoutPassword = ""
$envFile = Join-Path $web ".env.local"
if (Test-Path -LiteralPath $envFile) {
    foreach ($line in Get-Content -LiteralPath $envFile) {
        if ($line -match '^LAYOUT_USER=(.*)$') { $layoutUser = $Matches[1].Trim() }
        if ($line -match '^LAYOUT_PASSWORD=(.*)$') { $layoutPassword = $Matches[1].Trim() }
    }
}
@{
    layoutUser = $layoutUser
    layoutPassword = $layoutPassword
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dist "pedestal.config.json") -Encoding Ascii

Write-Host "Compiling ROC-Panels.exe..."
$icon = Join-Path $PSScriptRoot "ROC-Panels.ico"
Copy-Item -LiteralPath $icon -Destination (Join-Path $dist "ROC-Panels.ico")
& $csc /nologo /optimize /target:winexe /win32icon:$icon /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /out:"$(Join-Path $dist 'ROC-Panels.exe')" (Join-Path $PSScriptRoot "Launcher.cs")
if ($LASTEXITCODE -ne 0) { throw "The launcher did not compile." }

Write-Host ""
Write-Host "Pedestal folder: $dist"
Write-Host "Copy that whole folder to the 55 inch pedestal and run ROC-Panels.exe."
if ($layoutPassword) { Write-Host "The wall account was copied into pedestal.config.json." }
else { Write-Host "Set layoutPassword in pedestal.config.json before opening layouts." }
