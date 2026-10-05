using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

static class Program {
    const int Port = 4721;

    [STAThread]
    static void Main() {
        bool created;
        var gate = new Mutex(true, "ROC-Panels-Pedestal", out created);
        if (!created) {
            gate.Dispose();
            return;
        }
        try {
            string root = Path.GetDirectoryName(Application.ExecutablePath);
            string log = Path.Combine(root, "ROC-Panels.log");
            try { File.WriteAllText(log, ""); } catch { }
            Process node = null;
            try {
                string user;
                string password;
                ReadConfig(root, out user, out password);
                node = StartServer(root, log, user, password);
                if (!WaitForPort(node, Port, 30000)) {
                    MessageBox.Show(
                        "The panel console did not start. See ROC-Panels.log next to this program.",
                        "Remote Operation Center",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return;
                }
                Process edge = StartKiosk(root);
                Thread iconThread = new Thread(delegate() {
                    try { KeepConsoleIcon(Path.Combine(root, "ROC-Panels.ico")); } catch { }
                });
                iconThread.IsBackground = true;
                iconThread.Start();
                if (edge == null) {
                    MessageBox.Show(
                        "Microsoft Edge was not found. The console is running at http://127.0.0.1:" + Port + ".",
                        "Remote Operation Center",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning);
                    if (node != null && !node.HasExited) node.WaitForExit();
                    return;
                }
                edge.WaitForExit();
            } catch (Exception ex) {
                try { File.AppendAllText(log, ex.ToString() + Environment.NewLine); } catch { }
                MessageBox.Show(ex.Message, "Remote Operation Center", MessageBoxButtons.OK, MessageBoxIcon.Error);
            } finally {
                StopProcess(node);
            }
        } finally {
            try { gate.ReleaseMutex(); } catch { }
            gate.Dispose();
        }
    }

    static void ReadConfig(string root, out string user, out string password) {
        user = "Administrator";
        password = "";
        string path = Path.Combine(root, "pedestal.config.json");
        if (!File.Exists(path)) {
            File.WriteAllText(path, "{\r\n  \"layoutUser\": \"Administrator\",\r\n  \"layoutPassword\": \"\"\r\n}\r\n");
            return;
        }
        string json = File.ReadAllText(path);
        string readUser = JsonString(json, "layoutUser");
        string readPassword = JsonString(json, "layoutPassword");
        if (readUser != null && readUser.Length > 0) user = readUser;
        if (readPassword != null) password = readPassword;
    }

    static string JsonString(string json, string key) {
        Match match = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
        if (!match.Success) return null;
        return match.Groups[1].Value.Replace("\\\"", "\"").Replace("\\\\", "\\");
    }

    static Process StartServer(string root, string log, string user, string password) {
        string nodeExe = Path.Combine(root, "node", "node.exe");
        string serverDir = Path.Combine(root, "server");
        if (!File.Exists(nodeExe)) throw new FileNotFoundException("node.exe is missing from the node folder.");
        if (!File.Exists(Path.Combine(serverDir, "server.js"))) throw new FileNotFoundException("server.js is missing from the server folder.");
        var start = new ProcessStartInfo();
        start.FileName = nodeExe;
        start.Arguments = "server.js";
        start.WorkingDirectory = serverDir;
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.RedirectStandardOutput = true;
        start.RedirectStandardError = true;
        start.EnvironmentVariables["PORT"] = Port.ToString();
        start.EnvironmentVariables["HOSTNAME"] = "127.0.0.1";
        start.EnvironmentVariables["ROC_ROOT"] = root;
        start.EnvironmentVariables["ROC_PYTHON"] = Path.Combine(root, "python", "python.exe");
        start.EnvironmentVariables["PYTHONPATH"] = root;
        start.EnvironmentVariables["LAYOUT_USER"] = user;
        start.EnvironmentVariables["LAYOUT_PASSWORD"] = password;
        Process node = new Process();
        node.StartInfo = start;
        DataReceivedEventHandler write = delegate(object sender, DataReceivedEventArgs e) {
            if (e.Data == null) return;
            try { File.AppendAllText(log, e.Data + Environment.NewLine); } catch { }
        };
        node.OutputDataReceived += write;
        node.ErrorDataReceived += write;
        node.Start();
        node.BeginOutputReadLine();
        node.BeginErrorReadLine();
        return node;
    }

    static bool WaitForPort(Process node, int port, int timeoutMs) {
        var watch = Stopwatch.StartNew();
        while (watch.ElapsedMilliseconds < timeoutMs) {
            if (node.HasExited) return false;
            try {
                using (var client = new TcpClient()) {
                    IAsyncResult result = client.BeginConnect("127.0.0.1", port, null, null);
                    if (result.AsyncWaitHandle.WaitOne(300) && client.Connected) return true;
                }
            } catch { }
            Thread.Sleep(200);
        }
        return false;
    }

    static Process StartKiosk(string root) {
        string edge = EdgePath();
        if (edge == null) return null;
        string profile = Path.Combine(root, "edge-profile");
        Directory.CreateDirectory(profile);
        string page = "http://127.0.0.1:" + Port + "/?build=" + File.GetLastWriteTimeUtc(Path.Combine(root, "ROC-Panels.exe")).Ticks;
        var start = new ProcessStartInfo();
        start.FileName = edge;
        start.Arguments = "--kiosk " + page + " --edge-kiosk-type=fullscreen --no-first-run --no-default-browser-check --disable-features=Translate --user-data-dir=\"" + profile + "\"";
        start.UseShellExecute = false;
        return Process.Start(start);
    }

    static string EdgePath() {
        string[] candidates = new string[] {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft", "Edge", "Application", "msedge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft", "Edge", "Application", "msedge.exe")
        };
        for (int i = 0; i < candidates.Length; i++) {
            if (File.Exists(candidates[i])) return candidates[i];
        }
        return null;
    }

    const string ConsoleAppId = "MarineTechnologies.ROCPanels";
    static EnumWindowsProc _enumKeep;
    static IntPtr _iconBig;
    static IntPtr _iconSmall;
    static string _iconFile;
    static string _exePath;

    static void KeepConsoleIcon(string iconPath) {
        if (!File.Exists(iconPath)) return;
        _iconFile = iconPath;
        _exePath = Application.ExecutablePath;
        _iconBig = LoadImage(IntPtr.Zero, iconPath, 1, 32, 32, 0x00000010);
        _iconSmall = LoadImage(IntPtr.Zero, iconPath, 1, 16, 16, 0x00000010);
        _enumKeep = MarkConsoleWindow;
        while (true) {
            try { EnumWindows(_enumKeep, IntPtr.Zero); } catch { }
            Thread.Sleep(1000);
        }
    }

    static bool MarkConsoleWindow(IntPtr hwnd, IntPtr lParam) {
        if (!IsWindowVisible(hwnd)) return true;
        var title = new StringBuilder(512);
        GetWindowText(hwnd, title, title.Capacity);
        if (!title.ToString().StartsWith("Remote Operation Center")) return true;
        uint procId;
        GetWindowThreadProcessId(hwnd, out procId);
        try {
            var process = Process.GetProcessById((int)procId);
            if (!string.Equals(process.ProcessName, "msedge", StringComparison.OrdinalIgnoreCase)) return true;
        } catch {
            return true;
        }
        try { ApplyWindowIcon(hwnd); } catch { }
        return true;
    }

    static void ApplyWindowIcon(IntPtr hwnd) {
        Guid storeId = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        IPropertyStore store;
        if (SHGetPropertyStoreForWindow(hwnd, ref storeId, out store) != 0 || store == null) return;
        try {
            SetStoreString(store, AppKey(5), ConsoleAppId);
            SetStoreString(store, AppKey(2), "\"" + _exePath + "\"");
            SetStoreString(store, AppKey(4), "Remote Operation Center");
            SetStoreString(store, AppKey(3), _iconFile + ",0");
            store.Commit();
        } finally {
            Marshal.ReleaseComObject(store);
        }
        IntPtr unused;
        if (_iconBig != IntPtr.Zero) SendMessageTimeout(hwnd, 0x0080, new IntPtr(1), _iconBig, 0x0002, 200, out unused);
        if (_iconSmall != IntPtr.Zero) SendMessageTimeout(hwnd, 0x0080, IntPtr.Zero, _iconSmall, 0x0002, 200, out unused);
    }

    static PropertyKey AppKey(uint pid) {
        return new PropertyKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = pid };
    }

    static void SetStoreString(IPropertyStore store, PropertyKey key, string value) {
        var variant = new PropVariant();
        variant.vt = 31;
        variant.pszVal = Marshal.StringToCoTaskMemUni(value);
        try {
            store.SetValue(ref key, ref variant);
        } finally {
            Marshal.FreeCoTaskMem(variant.pszVal);
        }
    }

    static void StopProcess(Process process) {
        if (process == null) return;
        try {
            if (!process.HasExited) process.Kill();
        } catch { }
    }

    delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lParam);
    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr LoadImage(IntPtr instance, string path, uint type, int width, int height, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("shell32.dll")]
    static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
}

[StructLayout(LayoutKind.Sequential, Pack = 4)]
struct PropertyKey {
    public Guid fmtid;
    public uint pid;
}

[StructLayout(LayoutKind.Explicit, Size = 24)]
struct PropVariant {
    [FieldOffset(0)] public ushort vt;
    [FieldOffset(8)] public IntPtr pszVal;
}

[ComImport]
[Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPropertyStore {
    void GetCount(out uint count);
    void GetAt(uint index, out PropertyKey key);
    void GetValue(ref PropertyKey key, out PropVariant value);
    void SetValue(ref PropertyKey key, ref PropVariant value);
    void Commit();
}
