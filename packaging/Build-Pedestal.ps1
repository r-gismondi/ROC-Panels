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

Write-Host "Building the console..."
Push-Location $web
try {
    & node .\scripts\repair-next-picocolors.cjs build
    if ($LASTEXITCODE -ne 0) { throw "next build failed" }
} finally {
    Pop-Location
}

$standalone = Join-Path $web ".next\standalone"
$serverJs = Get-ChildItem -LiteralPath $standalone -Recurse -Filter server.js | Where-Object { $_.FullName -notmatch '\\node_modules\\' } | Select-Object -First 1
if (-not $serverJs) { throw "The standalone server was not produced." }

if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
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
Copy-Item -LiteralPath (Get-Command node).Source -Destination (Join-Path $nodeDir "node.exe")

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
foreach ($name in @("Watch-Launch.ps1", "Start-Watch.bat", "Launch-InSession.ps1", "Show-VncSession.ps1", "Show-KeyboardButton.ps1")) {
    Copy-Item -LiteralPath (Join-Path $web "scripts\$name") -Destination (Join-Path $scripts $name)
}
Copy-Item -LiteralPath (Join-Path $repo "layouts") -Destination (Join-Path $dist "layouts") -Recurse

@"
{
  "layoutUser": "Administrator",
  "layoutPassword": ""
}
"@ | Set-Content -LiteralPath (Join-Path $dist "pedestal.config.json") -Encoding Ascii

Write-Host "Compiling ROC-Panels.exe..."
& $csc /nologo /optimize /target:winexe /reference:System.Windows.Forms.dll /out:"$(Join-Path $dist 'ROC-Panels.exe')" (Join-Path $PSScriptRoot "Launcher.cs")
if ($LASTEXITCODE -ne 0) { throw "The launcher did not compile." }

Write-Host ""
Write-Host "Pedestal folder: $dist"
Write-Host "Copy that whole folder to the 55 inch pedestal and run ROC-Panels.exe."
Write-Host "Set layoutPassword in pedestal.config.json to the wall Administrator password before opening layouts."
