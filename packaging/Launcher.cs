using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
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

    static void StopProcess(Process process) {
        if (process == null) return;
        try {
            if (!process.HasExited) process.Kill();
        } catch { }
    }
}
