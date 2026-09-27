param(
    [Parameter(Mandatory = $true)]
    [string]$Bat
)

$ErrorActionPreference = "Stop"
$result = "C:\layouts\launch-result.txt"

function Write-Result([string]$Text) {
    Set-Content -LiteralPath $result -Value $Text -Encoding Ascii
}

if (-not (Test-Path -LiteralPath $Bat)) {
    Write-Result "Missing $Bat"
    exit 1
}

Add-Type @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class SessionStart {
    [DllImport("kernel32.dll")] static extern uint WTSGetActiveConsoleSessionId();
    [DllImport("wtsapi32.dll", SetLastError = true)] static extern bool WTSQueryUserToken(uint sessionId, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool DuplicateTokenEx(IntPtr existing, uint access, IntPtr attributes, int level, int type, out IntPtr duplicate);
    [DllImport("userenv.dll", SetLastError = true)] static extern bool CreateEnvironmentBlock(out IntPtr environment, IntPtr token, bool inherit);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcessAsUser(IntPtr token, string application, string command, IntPtr processAttributes, IntPtr threadAttributes, bool inherit, uint flags, IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo process);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct StartupInfo {
        public int cb;
        public string reserved;
        public string desktop;
        public string title;
        public int x, y, xSize, ySize, xCountChars, yCountChars, fillAttribute, flags;
        public short showWindow, reserved2;
        public IntPtr reserved3, stdIn, stdOut, stdErr;
    }
    [StructLayout(LayoutKind.Sequential)] public struct ProcessInfo {
        public IntPtr process, thread;
        public int processId, threadId;
    }
    public static string Start(string command, string directory) {
        uint session = WTSGetActiveConsoleSessionId();
        IntPtr token;
        if (!WTSQueryUserToken(session, out token)) throw new Win32Exception(Marshal.GetLastWin32Error(), "No signed-in desktop on session " + session);
        IntPtr primary;
        if (!DuplicateTokenEx(token, 0x02000000, IntPtr.Zero, 2, 1, out primary)) throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not use the signed-in desktop");
        IntPtr environment;
        if (!CreateEnvironmentBlock(out environment, primary, false)) environment = IntPtr.Zero;
        StartupInfo startup = new StartupInfo();
        startup.cb = Marshal.SizeOf(typeof(StartupInfo));
        startup.desktop = "winsta0\\default";
        ProcessInfo process;
        if (!CreateProcessAsUser(primary, null, command, IntPtr.Zero, IntPtr.Zero, false, 0x00000410, environment, directory, ref startup, out process)) throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not open the layout");
        return "Opened on session " + session + " as process " + process.processId;
    }
}
"@

try {
    $directory = Split-Path -Parent $Bat
    $started = [SessionStart]::Start("cmd.exe /c `"`"$Bat`"`"", $directory)
    Write-Result $started
    Write-Output $started
    exit 0
} catch {
    Write-Result $_.Exception.Message
    Write-Output $_.Exception.Message
    exit 1
}
