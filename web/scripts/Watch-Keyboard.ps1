# Runs on the wall PC's signed-in desktop, started by Watch-Launch.ps1.
# While a Chrome Remote Desktop client is connected, a text field that takes focus raises the
# Windows touch keyboard, so it shows in the remote picture; it lowers again when focus leaves.
# Without a connected client it does nothing, so pages that focus a field never pop a keyboard on the wall.
$ErrorActionPreference = "Continue"
$root = "C:\layouts"
$alive = Join-Path $root "keyboard-alive.txt"
$logPath = Join-Path $root "keyboard.log"

$mutex = New-Object System.Threading.Mutex($false, "WallKeyboardWatch")
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
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Automation;

public static class TouchKeyboard {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [ComImport, Guid("37c994e7-432b-4834-a2f7-dce1f13b834b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ITipInvocation { void Toggle(IntPtr hwnd); }

    [ComImport, Guid("4ce576fa-83dc-4f88-951c-9d0782b4e376")]
    class UIHostNoLaunch { }

    [ComImport, Guid("5752238B-24F0-495A-82F1-2FD593056796"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IFrameworkInputPane {
        [PreserveSig] int Advise(IntPtr window, IntPtr handler, out uint cookie);
        [PreserveSig] int AdviseWithHWND(IntPtr hwnd, IntPtr handler, out uint cookie);
        [PreserveSig] int Unadvise(uint cookie);
        [PreserveSig] int Location(out RECT rect);
    }

    [ComImport, Guid("D5120AA3-46BA-44C5-822D-CA8092C1FC72")]
    class FrameworkInputPane { }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string className, string title);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();

    static volatile bool _typing;
    static volatile int _owner;
    static long _changed;
    static AutomationFocusChangedEventHandler _handler;

    public static bool Typing { get { return _typing; } }
    public static int Owner { get { return _owner; } }
    public static long Changed { get { return System.Threading.Interlocked.Read(ref _changed); } }

    public static void Watch() {
        if (_handler != null) return;
        _handler = OnFocus;
        Automation.AddAutomationFocusChangedEventHandler(_handler);
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
        if (!current.IsEnabled) return false;
        bool edit = current.ControlType == ControlType.Edit;
        if (!edit && current.ControlType != ControlType.ComboBox) return false;
        object pattern;
        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out pattern)) return !((ValuePattern)pattern).Current.IsReadOnly;
        return edit;
    }

    public static bool IsShowing() {
        try {
            var pane = (IFrameworkInputPane)new FrameworkInputPane();
            try {
                RECT rect;
                if (pane.Location(out rect) == 0) return rect.Right > rect.Left && rect.Bottom > rect.Top;
            } finally {
                Marshal.ReleaseComObject(pane);
            }
        } catch { }
        IntPtr tip = FindWindow("IPTip_Main_Window", null);
        return tip != IntPtr.Zero && IsWindowVisible(tip) && (GetWindowLong(tip, -16) & 0x08000000) == 0;
    }

    public static bool Toggle() {
        try {
            var tip = (ITipInvocation)new UIHostNoLaunch();
            try {
                tip.Toggle(GetDesktopWindow());
            } finally {
                Marshal.ReleaseComObject(tip);
            }
            return true;
        } catch {
            return false;
        }
    }

    public static void StartHost() {
        if (Process.GetProcessesByName("TabTip").Length > 0) return;
        string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonProgramFiles), @"microsoft shared\ink\TabTip.exe");
        if (!File.Exists(path)) return;
        var start = new ProcessStartInfo(path);
        start.UseShellExecute = true;
        Process.Start(start);
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

function Show-Keyboard {
    if ([TouchKeyboard]::IsShowing()) { return $true }
    [TouchKeyboard]::StartHost()
    $deadline = (Get-Date).AddSeconds(2)
    while ((Get-Date) -lt $deadline) {
        if ([TouchKeyboard]::IsShowing()) { return $true }
        if ([TouchKeyboard]::Toggle()) {
            Start-Sleep -Milliseconds 250
            if ([TouchKeyboard]::IsShowing()) { return $true }
        }
        Start-Sleep -Milliseconds 150
    }
    return [TouchKeyboard]::IsShowing()
}

function Hide-Keyboard {
    if ([TouchKeyboard]::IsShowing()) { [void][TouchKeyboard]::Toggle() }
}

[TouchKeyboard]::Watch()
Write-Log "Watching text fields."

$scriptStamp = (Get-Item -LiteralPath $PSCommandPath).LastWriteTimeUtc
$script:shown = $false
$script:handled = [long]0
$script:remote = $false
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
        try { if ((Get-Item -LiteralPath $PSCommandPath).LastWriteTimeUtc -ne $scriptStamp) { break } } catch {}
    }
    if (($now - $script:lastRemoteCheck).TotalMilliseconds -ge 1000) {
        $script:lastRemoteCheck = $now
        $connected = Test-RemoteClient
        if ($connected -ne $script:remote) {
            $script:remote = $connected
            Write-Log $(if ($connected) { "A remote desktop client connected." } else { "The remote desktop client left." })
            if (-not $connected -and $script:shown) {
                Hide-Keyboard
                $script:shown = $false
            }
        }
    }
    $changed = [TouchKeyboard]::Changed
    if ($script:remote -and $changed -ne $script:handled -and -not ($ignore -contains (Get-ProcessName ([TouchKeyboard]::Owner)))) {
        $settled = ([datetime]::UtcNow.Ticks - $changed) / 10000
        if ([TouchKeyboard]::Typing) {
            if ($settled -ge 120) {
                $script:handled = $changed
                $script:shown = Show-Keyboard
                Write-Log $(if ($script:shown) { "Raised the keyboard." } else { "The keyboard did not open." })
            }
        } elseif ($settled -ge 300) {
            $script:handled = $changed
            if ($script:shown) {
                Hide-Keyboard
                $script:shown = $false
                Write-Log "Lowered the keyboard."
            }
        }
    }
    Start-Sleep -Milliseconds 100
}

if ($script:shown) { Hide-Keyboard }
try { $mutex.ReleaseMutex() | Out-Null } catch {}
$mutex.Dispose()
