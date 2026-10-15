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
    static volatile string _label = "";
    static long _changed;
    static AutomationFocusChangedEventHandler _handler;

    public static bool Typing { get { return _typing; } }
    public static int Owner { get { return _owner; } }
    public static string Label { get { return _label; } }
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
        string label = "";
        try {
            var element = sender as AutomationElement;
            if (element != null) {
                var current = element.Current;
                owner = current.ProcessId;
                label = current.ControlType.ProgrammaticName.Replace("ControlType.", "") + " '" + current.Name + "'";
                typing = IsTypeable(element);
            }
        } catch { }
        _owner = owner;
        _label = label;
        _typing = typing;
        System.Threading.Interlocked.Exchange(ref _changed, DateTime.UtcNow.Ticks);
    }

    // Browsers report only their window until something asks for the page's elements, so look again.
    public static bool Recheck() {
        try {
            var element = AutomationElement.FocusedElement;
            if (element == null) return false;
            var current = element.Current;
            _owner = current.ProcessId;
            _label = current.ControlType.ProgrammaticName.Replace("ControlType.", "") + " '" + current.Name + "'";
            _typing = IsTypeable(element);
        } catch { }
        return _typing;
    }

    // A tap into a web field can raise no focus event at all, so the focused element is also read on a timer.
    // Only a change between typing and not typing counts. While typing, the browser's bare window
    // means its page tree is not ready yet, not that the field was left.
    public static void Poll() {
        try {
            var element = AutomationElement.FocusedElement;
            if (element == null) return;
            var current = element.Current;
            int owner = current.ProcessId;
            if (Ignored(owner)) return;
            bool typing = IsTypeable(element);
            if (typing == _typing) return;
            if (_typing && owner == _owner && current.ControlType == ControlType.Pane) return;
            _owner = owner;
            _label = current.ControlType.ProgrammaticName.Replace("ControlType.", "") + " '" + current.Name + "'";
            _typing = typing;
            System.Threading.Interlocked.Exchange(ref _changed, DateTime.UtcNow.Ticks);
        } catch { }
    }

    static readonly System.Collections.Generic.Dictionary<int, bool> _ignored = new System.Collections.Generic.Dictionary<int, bool>();

    static bool Ignored(int id) {
        bool ignored;
        if (_ignored.TryGetValue(id, out ignored)) return ignored;
        string name = "";
        try { name = System.Diagnostics.Process.GetProcessById(id).ProcessName; } catch { }
        ignored = name == "TabTip" || name == "TextInputHost" || name == "osk";
        _ignored[id] = ignored;
        return ignored;
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
            [System.IO.File]::Replace($temporary, $statePath, [NullString]::Value)
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
$script:typing = $false
$script:handled = [long]0
$script:rechecked = [long]0
$script:lastRemoteCheck = [datetime]::MinValue
$script:lastStampCheck = [datetime]::MinValue
$script:lastBeat = [datetime]::MinValue
$script:lastPoll = [datetime]::MinValue

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
                $script:typing = $false
                Set-FieldState "off"
                Write-Log "The remote desktop client left."
            }
        }
    }
    if ($script:remote -and ($now - $script:lastPoll).TotalMilliseconds -ge 300) {
        $script:lastPoll = $now
        [FieldFocus]::Poll()
    }
    $changed = [FieldFocus]::Changed
    $owner = Get-ProcessName ([FieldFocus]::Owner)
    if ($script:remote -and $changed -ne $script:handled -and -not ($ignore -contains $owner)) {
        $settled = ([datetime]::UtcNow.Ticks - $changed) / 10000
        if (-not [FieldFocus]::Typing -and $settled -ge 120 -and $script:rechecked -ne $changed) {
            $script:rechecked = $changed
            [void][FieldFocus]::Recheck()
            $owner = Get-ProcessName ([FieldFocus]::Owner)
        }
        if ([FieldFocus]::Typing) {
            if ($settled -ge 120) {
                $script:handled = $changed
                $script:typing = $true
                Set-FieldState "on"
                Write-Log "A text field took focus: $([FieldFocus]::Label) in $owner."
            }
        } elseif ($settled -ge 300) {
            $script:handled = $changed
            if ($script:typing) {
                $script:typing = $false
                Set-FieldState "off"
                Write-Log "Focus left the text field: $([FieldFocus]::Label) in $owner."
            } else {
                Write-Log "Focus: $([FieldFocus]::Label) in $owner."
            }
        }
    }
    Start-Sleep -Milliseconds 100
}

[FieldFocus]::Stop()
try { $mutex.ReleaseMutex() | Out-Null } catch {}
$mutex.Dispose()
