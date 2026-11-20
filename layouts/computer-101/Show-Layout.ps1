# Places labeled test windows on computer 192.168.0.101.
# Display 1 is the left monitor and display 2 is the right monitor.
# Each is landscape, tops aligned, at the same Windows display scale.
# Positions below assume 1920x1080 monitors and are stretched to the real monitor size.
#
# HDMI 1 (display 1)          HDMI 2 (display 2)
# TV1  0,0     960x540        TV3  1920,0    960x540
# TV2  960,0   960x540        TV4  2880,0    960x540
# TV5  0,540   960x540        TV7  1920,540  960x540
# TV6  960,540 960x540        TV8  2880,540  960x540
#
# TV9-TV18 belong to computers 2 and 3 and are not opened here.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Independent", "Split", "Focus", "FocusSplit", "Full")]
    [string]$Preset
)

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    Write-Error "Start this from its .bat file so PowerShell runs in STA mode."
    exit 1
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Panel2Dpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);
}
"@
[void][Panel2Dpi]::SetProcessDPIAware()
$LayoutX = [Panel2Dpi]::GetSystemMetrics(0) / 1920.0
$LayoutY = [Panel2Dpi]::GetSystemMetrics(1) / 1080.0
function Sx([double]$Value) { [int][Math]::Round($Value * $LayoutX) }
function Sy([double]$Value) { [int][Math]::Round($Value * $LayoutY) }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $root "panel1-layout.pid"
if (Test-Path $pidFile) {
    $oldId = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($oldId -and $oldId -ne $PID) {
        Stop-Process -Id $oldId -Force -ErrorAction SilentlyContinue
    }
}
Set-Content -Path $pidFile -Value $PID

function Zone($title, $x, $y, $w, $h, $color) {
    [pscustomobject]@{ Title = $title; X = (Sx $x); Y = (Sy $y); W = (Sx ($x + $w)) - (Sx $x); H = (Sy ($y + $h)) - (Sy $y); Color = $color }
}

$presets = @{
    Independent = @(
        (Zone "TV1"  0    0   960  540 "#1a6cff")
        (Zone "TV2"  960  0   960  540 "#12c2a3")
        (Zone "TV5"  0    540 960  540 "#7a5cff")
        (Zone "TV6"  960  540 960  540 "#d06bff")
        (Zone "TV3"  1920 0   960  540 "#f0a202")
        (Zone "TV4"  2880 0   960  540 "#3ec8ff")
        (Zone "TV7"  1920 540 960  540 "#ff6b8a")
        (Zone "TV8"  2880 540 960  540 "#9be36a")
    )
    Split = @(
        (Zone "TV1  TV2`nTV5  TV6" 0    0 1920 1080 "#1a6cff")
        (Zone "TV3  TV4`nTV7  TV8" 1920 0 1920 1080 "#f0a202")
    )
    Focus = @(
        (Zone "TV1`nTV5"            0    0 960  1080 "#1a6cff")
        (Zone "TV2 TV3`nTV6 TV7"    960  0 1920 1080 "#f0a202")
        (Zone "TV4`nTV8"            2880 0 960  1080 "#12c2a3")
    )
    FocusSplit = @(
        (Zone "TV1"                 0    0 960  540  "#1a6cff")
        (Zone "TV5"                 0    540 960 540  "#7a5cff")
        (Zone "TV2 TV3`nTV6 TV7"    960  0 1920 1080 "#f0a202")
        (Zone "TV4"                 2880 0 960  540  "#12c2a3")
        (Zone "TV8"                 2880 540 960 540  "#9be36a")
    )
    Full = @(
        (Zone "TV1 TV2 TV3 TV4`nTV5 TV6 TV7 TV8" 0 0 3840 1080 "#1a6cff")
    )
}

$script:openForms = 0
foreach ($zone in $presets[$Preset]) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "P1 $Preset $($zone.Title)"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.Bounds = New-Object System.Drawing.Rectangle $zone.X, $zone.Y, $zone.W, $zone.H
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($zone.Color)
    $form.KeyPreview = $true
    $form.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Dock = [System.Windows.Forms.DockStyle]::Fill
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $label.ForeColor = [System.Drawing.Color]::White
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 36, [System.Drawing.FontStyle]::Bold)
    $label.Text = "$($zone.Title)`n$($zone.X), $($zone.Y)`n$($zone.W) x $($zone.H)`nEsc closes"
    $form.Controls.Add($label)

    $form.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            [System.Windows.Forms.Application]::Exit()
        }
    })
    $form.Add_FormClosed({
        $script:openForms = $script:openForms - 1
        if ($script:openForms -le 0) {
            [System.Windows.Forms.Application]::Exit()
        }
    })
    $form.Show()
    $script:openForms = $script:openForms + 1
}

try {
    [System.Windows.Forms.Application]::Run()
}
finally {
    if ((Get-Content $pidFile -ErrorAction SilentlyContinue) -eq $PID) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
}
