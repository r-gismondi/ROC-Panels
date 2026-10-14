# Runs on the wall PC's signed-in desktop, started by Watch-Launch.ps1.
# While a Chrome Remote Desktop client is connected, type-field.txt says whether a text field has focus
# ("on <stamp>" or "off <stamp>"), so the pedestal can raise and lower its touch keyboard over the session.
# Focus events are only watched while a client is connected, so browsers on the wall are left alone otherwise.
$ErrorActionPreference = "Continue"
$root = "C:\layouts"
$alive = Join-Path $root "type-field-alive.txt"
$statePath = Join-Path $root "type-field.txt"
$logPath = Join-Path $root "type-field.log"

$mutex = New-Object System.Threading.Mutex($false, "WallTypeField")
$owned = $false
try {
    $owned = $mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $owned = $true
}
if (-not $owned) { exit 0 }

function Write-Log([string]$Text) {
    try { Add-Content -LiteralPath $logPath -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $Text) -Encoding utf8 } catch {}
}

try { Set-Content -LiteralPath $logPath -Value "" -Encoding utf8 } catch {}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -ReferencedAssemblies UIAutomationClient, UIAutomationTypes, WindowsBase -TypeDefinition @'
using System;
using System.Windows.Automation;

public static class FieldFocus {
    static volatile bool _typing;
    static volatile int _owner;
    static long _changed;
    static AutomationFocusChangedEventHandler _handler;

    public static bool Typing { get { return _typing; } }
    public static int Owner { get { return _owner; } }
    public static long Changed { get { return System.Threading.Interlocked.Read(ref _changed); } }

    public static void Start() {
        if (_handler != null) return;
        _handler = OnFocus;
        Automation.AddAutomationFocusChangedEventHandler(_handler);
    }

    public static void Stop() {
        if (_handler == null) return;
        try { Automation.RemoveAutomationFocusChangedEventHandler(_handler); } catch { }
        _handler = null;
        _typing = false;
    }

    static void OnFocus(object sender, AutomationFocusChangedEventArgs e) {
        bool typing = false;
        int owner = 0;
        try {
            var element = sender as AutomationElement;
            if (element != null) {
                owner = element.Current.ProcessId;
                typing = IsTypeable(element);
            }
        } catch { }
        _owner = owner;
        _typing = typing;
        System.Threading.Interlocked.Exchange(ref _changed, DateTime.UtcNow.Ticks);
    }

    static bool IsTypeable(AutomationElement element) {
        var current = element.Current;
        if (!current.IsEnabled || !current.IsKeyboardFocusable) return false;
        bool edit = current.ControlType == ControlType.Edit;
        if (!edit && current.ControlType != ControlType.ComboBox) return false;
        object pattern;
        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out pattern)) return !((ValuePattern)pattern).Current.IsReadOnly;
        return edit;
    }
}
'@

$ignore = @("TabTip", "TextInputHost", "osk")
$names = @{}
function Get-ProcessName([int]$Id) {
    if ($Id -le 0) { return "" }
    if (-not $names.ContainsKey($Id)) {
        $name = ""
        try { $name = (Get-Process -Id $Id -ErrorAction Stop).ProcessName } catch {}
        $names[$Id] = $name
    }
    return $names[$Id]
}

function Test-RemoteClient {
    return @(Get-Process -Name "remoting_desktop" -ErrorAction SilentlyContinue).Count -gt 0
}

function Set-FieldState([string]$State) {
    $text = "$State $([datetime]::UtcNow.Ticks)"
    $temporary = "$statePath.tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, $text)
        if (Test-Path -LiteralPath $statePath) {
            [System.IO.File]::Replace($temporary, $statePath, $null)
        } else {
            [System.IO.File]::Move($temporary, $statePath)
        }
    } catch {
        Write-Log "Could not save the field state: $($_.Exception.Message)"
    }
}

Write-Log "Watching for a remote desktop client."
$scriptStamp = (Get-Item -LiteralPath $PSCommandPath).LastWriteTimeUtc
$script:remote = $false
$script:handled = [long]0
$script:lastRemoteCheck = [datetime]::MinValue
$script:lastStampCheck = [datetime]::MinValue
$script:lastBeat = [datetime]::MinValue

while ($true) {
    $now = Get-Date
    if (($now - $script:lastBeat).TotalMilliseconds -ge 500) {
        Set-Content -LiteralPath $alive -Value $now.ToString("o") -Encoding Ascii
        $script:lastBeat = $now
    }
    if (($now - $script:lastStampCheck).TotalSeconds -ge 5) {
        $script:lastStampCheck = $now
        # A newer copy was published; the watcher starts it once this one stops beating.
        try { if ((Get-Item -LiteralPath $PSCommandPath -ErrorAction Stop).LastWriteTimeUtc -ne $scriptStamp) { break } } catch {}
    }
    if (($now - $script:lastRemoteCheck).TotalMilliseconds -ge 1000) {
        $script:lastRemoteCheck = $now
        $connected = Test-RemoteClient
        if ($connected -ne $script:remote) {
            $script:remote = $connected
            if ($connected) {
                [FieldFocus]::Start()
                $script:handled = [FieldFocus]::Changed
                Write-Log "A remote desktop client connected; watching text fields."
            } else {
                [FieldFocus]::Stop()
                Set-FieldState "off"
                Write-Log "The remote desktop client left."
            }
        }
    }
    $changed = [FieldFocus]::Changed
    if ($script:remote -and $changed -ne $script:handled -and -not ($ignore -contains (Get-ProcessName ([FieldFocus]::Owner)))) {
        $settled = ([datetime]::UtcNow.Ticks - $changed) / 10000
        if ([FieldFocus]::Typing) {
            if ($settled -ge 120) {
                $script:handled = $changed
                Set-FieldState "on"
                Write-Log "A text field took focus."
            }
        } elseif ($settled -ge 300) {
            $script:handled = $changed
            Set-FieldState "off"
            Write-Log "Focus left the text field."
        }
    }
    Start-Sleep -Milliseconds 100
}

[FieldFocus]::Stop()
try { $mutex.ReleaseMutex() | Out-Null } catch {}
$mutex.Dispose()
