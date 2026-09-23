# Places labeled test windows on computer 192.168.0.102.
# Windows must match computer 1: display 1 on the left, display 2 on the right,
# each 1920x1080, landscape, 100% scale, tops aligned.
#
# HDMI 1 (display 1)          HDMI 2 (display 2)
# TV9  0,0     960x540        TV11 1920,0    960x540
# TV10 960,0   960x540        TV12 2880,0    960x540
# TV14 0,540   960x540        TV16 1920,540  960x540
# TV15 960,540 960x540        TV17 2880,540  960x540
#
# TV13 and TV18 belong to 192.168.0.103 and are not opened here.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Independent", "DualFocus1", "DualFocus2", "DualFocus3", "Full")]
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
}
"@
[void][Panel2Dpi]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $root "panel2-layout.pid"
if (Test-Path $pidFile) {
    $oldId = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($oldId -and $oldId -ne $PID) {
        Stop-Process -Id $oldId -Force -ErrorAction SilentlyContinue
    }
}
Set-Content -Path $pidFile -Value $PID

function Zone($title, $x, $y, $w, $h, $color) {
    [pscustomobject]@{ Title = $title; X = $x; Y = $y; W = $w; H = $h; Color = $color }
}

$presets = @{
    Independent = @(
        (Zone "TV9"  0    0   960  540 "#1a6cff")
        (Zone "TV10" 960  0   960  540 "#12c2a3")
        (Zone "TV14" 0    540 960  540 "#7a5cff")
        (Zone "TV15" 960  540 960  540 "#d06bff")
        (Zone "TV11" 1920 0   960  540 "#f0a202")
        (Zone "TV12" 2880 0   960  540 "#3ec8ff")
        (Zone "TV16" 1920 540 960  540 "#ff6b8a")
        (Zone "TV17" 2880 540 960  540 "#9be36a")
    )
    DualFocus1 = @(
        (Zone "TV9  TV10`nTV14 TV15" 0    0 1920 1080 "#1a6cff")
        (Zone "TV11`nTV16"           1920 0 960  1080 "#f0a202")
        (Zone "TV12`nTV17"           2880 0 960  1080 "#12c2a3")
    )
    DualFocus2 = @(
        (Zone "TV9  TV10`nTV14 TV15" 0    0 1920 1080 "#1a6cff")
        (Zone "TV11 TV12`nTV16 TV17" 1920 0 1920 1080 "#f0a202")
    )
    DualFocus3 = @(
        (Zone "TV9`nTV14"            0    0 960  1080 "#1a6cff")
        (Zone "TV10 TV11`nTV15 TV16" 960  0 1920 1080 "#f0a202")
        (Zone "TV12`nTV17"           2880 0 960  1080 "#12c2a3")
    )
    Full = @(
        (Zone "TV9 TV10 TV11 TV12`nTV14 TV15 TV16 TV17" 0 0 3840 1080 "#1a6cff")
    )
}

$script:openForms = 0
foreach ($zone in $presets[$Preset]) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "P2 $Preset $($zone.Title)"
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
