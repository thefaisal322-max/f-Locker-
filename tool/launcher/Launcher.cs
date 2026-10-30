// F-Locker.exe - the single file you click on Windows.
//
// It carries the real app (app.zip) inside itself. On first start it unpacks
// it, hidden, into %LOCALAPPDATA%\F-Locker\runtime\<version>, then starts it
// with FLOCKER_HOME set to the folder this file is in, so the locked data
// (the hidden "FLockerData" folder) stays next to F-Locker.exe - also on a USB.
//
// Built with the C# compiler that ships with Windows (.NET Framework 4).

using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("F-Locker")]
[assembly: AssemblyProduct("F-Locker")]
[assembly: AssemblyDescription("F-Locker - encrypted locker")]

static class Launcher
{
    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            string home = Path.GetDirectoryName(Path.GetFullPath(asm.Location));

            string version;
            using (Stream s = asm.GetManifestResourceStream("version.txt"))
            using (StreamReader r = new StreamReader(s))
                version = r.ReadToEnd().Trim();

            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string baseDir = Path.Combine(Path.Combine(local, "F-Locker"), "runtime");
            string appDir = Path.Combine(baseDir, version);
            string ready = Path.Combine(appDir, ".ready");

            if (!File.Exists(ready))
            {
                Directory.CreateDirectory(baseDir);
                File.SetAttributes(Path.GetDirectoryName(baseDir),
                    File.GetAttributes(Path.GetDirectoryName(baseDir)) | FileAttributes.Hidden);

                string tmp = appDir + ".tmp" + Process.GetCurrentProcess().Id;
                if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
                using (Stream z = asm.GetManifestResourceStream("app.zip"))
                using (ZipArchive zip = new ZipArchive(z, ZipArchiveMode.Read))
                    zip.ExtractToDirectory(tmp);
                File.WriteAllText(Path.Combine(tmp, ".ready"), version);

                try
                {
                    if (Directory.Exists(appDir)) Directory.Delete(appDir, true);
                    Directory.Move(tmp, appDir);
                }
                catch
                {
                    // Another F-Locker started at the same moment and won.
                    if (!File.Exists(ready)) throw;
                    try { Directory.Delete(tmp, true); } catch { }
                }

                // Remove older versions.
                foreach (string d in Directory.GetDirectories(baseDir))
                {
                    if (string.Equals(d, appDir, StringComparison.OrdinalIgnoreCase)) continue;
                    try { Directory.Delete(d, true); } catch { }
                }
            }

            ProcessStartInfo psi = new ProcessStartInfo(Path.Combine(appDir, "F-Locker.exe"));
            psi.UseShellExecute = false;
            psi.WorkingDirectory = appDir;
            psi.EnvironmentVariables["FLOCKER_HOME"] = home;
            StringBuilder a = new StringBuilder();
            foreach (string arg in args) a.Append('"').Append(arg.Replace("\"", "\\\"")).Append("\" ");
            psi.Arguments = a.ToString().Trim();
            Process.Start(psi);
            return 0;
        }
        catch (Exception e)
        {
            MessageBox.Show("F-Locker could not start:\n\n" + e.Message, "F-Locker",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
