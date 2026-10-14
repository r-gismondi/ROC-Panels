using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

static class Program {
    internal const int Port = 4721;

    [STAThread]
    static void Main() {
        SetProcessDPIAware();
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
                Thread homeThread = new Thread(delegate() {
                    try { Application.Run(new HomeButton()); } catch (Exception homeError) {
                        try { File.AppendAllText(log, homeError.ToString() + Environment.NewLine); } catch { }
                    }
                });
                homeThread.IsBackground = true;
                homeThread.SetApartmentState(ApartmentState.STA);
                homeThread.Start();
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
        if (!IsConsoleWindow(hwnd)) return true;
        try { ApplyWindowIcon(hwnd); } catch { }
        return true;
    }

    public static bool IsConsoleWindow(IntPtr hwnd) {
        if (!IsWindowVisible(hwnd)) return false;
        var title = new StringBuilder(512);
        GetWindowText(hwnd, title, title.Capacity);
        if (!title.ToString().StartsWith("Remote Operation Center")) return false;
        uint procId;
        GetWindowThreadProcessId(hwnd, out procId);
        try {
            var process = Process.GetProcessById((int)procId);
            return string.Equals(process.ProcessName, "msedge", StringComparison.OrdinalIgnoreCase);
        } catch {
            return false;
        }
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
    static extern bool SetProcessDPIAware();
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

// Stays above every window, the remote session included, and never takes focus from what is under it.
class HomeButton : Form {
    const string HomeRequest = @"C:\layouts\remote-session.home";
    const uint SWP_NOSIZE = 0x0001;
    const uint SWP_NOMOVE = 0x0002;
    const uint SWP_NOACTIVATE = 0x0010;
    readonly System.Windows.Forms.Timer keepOnTop = new System.Windows.Forms.Timer();
    bool pressed;

    public HomeButton() {
        float scale;
        using (Graphics screen = Graphics.FromHwnd(IntPtr.Zero)) scale = screen.DpiX / 96f;
        int side = (int)Math.Round(60 * scale);
        int margin = (int)Math.Round(18 * scale);
        Rectangle area = Screen.PrimaryScreen.Bounds;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Text = "ROC Home";
        BackColor = Color.FromArgb(7, 26, 77);
        Cursor = Cursors.Hand;
        DoubleBuffered = true;
        Bounds = new Rectangle(area.Left + margin, area.Bottom - margin - side, side, side);
        using (var path = new GraphicsPath()) {
            path.AddEllipse(0, 0, side, side);
            Region = new Region(path);
        }
        keepOnTop.Interval = 250;
        keepOnTop.Tick += delegate {
            SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        };
        keepOnTop.Start();
    }

    protected override bool ShowWithoutActivation {
        get { return true; }
    }

    protected override CreateParams CreateParams {
        get {
            CreateParams created = base.CreateParams;
            created.ExStyle |= 0x08000000 | 0x00000080 | 0x00000008;
            return created;
        }
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0021) {
            m.Result = new IntPtr(3);
            return;
        }
        base.WndProc(ref m);
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        float s = ClientSize.Width;
        float u = s / 60f;
        var face = new RectangleF(0.5f, 0.5f, s - 1, s - 1);
        Color top = pressed ? Color.FromArgb(12, 112, 178) : Color.FromArgb(26, 163, 232);
        using (var fill = new LinearGradientBrush(face, top, Color.FromArgb(10, 58, 140), LinearGradientMode.Vertical)) {
            g.FillEllipse(fill, face);
        }
        float ringWidth = 2.2f * u;
        using (var ring = new Pen(Color.FromArgb(200, 235, 255), ringWidth)) {
            g.DrawEllipse(ring, ringWidth / 2 + 0.5f, ringWidth / 2 + 0.5f, s - ringWidth - 1, s - ringWidth - 1);
        }
        using (var pen = new Pen(Color.White, 3.2f * u)) {
            pen.LineJoin = LineJoin.Round;
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            g.DrawLines(pen, Points(u, 17, 31, 30, 18.5f, 43, 31));
            g.DrawLines(pen, Points(u, 21.5f, 28, 21.5f, 42, 38.5f, 42, 38.5f, 28));
            g.DrawLines(pen, Points(u, 27, 42, 27, 35, 33, 35, 33, 42));
        }
    }

    static PointF[] Points(float u, params float[] xy) {
        var points = new PointF[xy.Length / 2];
        for (int i = 0; i < points.Length; i++) points[i] = new PointF(xy[i * 2] * u, xy[i * 2 + 1] * u);
        return points;
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        pressed = true;
        Invalidate();
        base.OnMouseDown(e);
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        pressed = false;
        Invalidate();
        base.OnMouseUp(e);
    }

    protected override void OnClick(EventArgs e) {
        base.OnClick(e);
        GoHome();
    }

    static void GoHome() {
        if (SessionRunning()) {
            try {
                Directory.CreateDirectory(Path.GetDirectoryName(HomeRequest));
                File.WriteAllText(HomeRequest, "home");
            } catch { }
        }
        IntPtr console = FindConsole();
        if (console != IntPtr.Zero) BringToFront(console);
        ThreadPool.QueueUserWorkItem(delegate {
            try {
                using (var web = new WebClient()) {
                    web.Headers[HttpRequestHeader.ContentType] = "application/json";
                    web.UploadString("http://127.0.0.1:" + Program.Port + "/api/home", "POST", "{}");
                }
            } catch { }
        });
    }

    static bool SessionRunning() {
        try {
            Mutex running;
            if (!Mutex.TryOpenExisting("WallRemoteSession", out running)) return false;
            running.Dispose();
            return true;
        } catch (UnauthorizedAccessException) {
            return true;
        } catch {
            return false;
        }
    }

    static IntPtr FindConsole() {
        IntPtr found = IntPtr.Zero;
        EnumProc visit = delegate(IntPtr hwnd, IntPtr lParam) {
            if (!Program.IsConsoleWindow(hwnd)) return true;
            found = hwnd;
            return false;
        };
        EnumWindows(visit, IntPtr.Zero);
        GC.KeepAlive(visit);
        return found;
    }

    static void BringToFront(IntPtr hwnd) {
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
        uint self = GetCurrentThreadId();
        IntPtr front = GetForegroundWindow();
        uint frontThread = front == IntPtr.Zero ? 0 : GetWindowThreadProcessId(front, IntPtr.Zero);
        bool attached = frontThread != 0 && frontThread != self && AttachThreadInput(frontThread, self, true);
        BringWindowToTop(hwnd);
        SetForegroundWindow(hwnd);
        if (attached) AttachThreadInput(frontThread, self, false);
    }

    delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, IntPtr processId);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint attach, uint attachTo, bool on);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
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
