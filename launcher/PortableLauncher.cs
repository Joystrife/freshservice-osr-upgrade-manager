using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Freshservice OSR Upgrade Manager Portable Preview")]
[assembly: AssemblyDescription("Portable launcher for the 0.5.1-preview.3 PowerShell source distribution")]
[assembly: AssemblyVersion("0.5.1.2")]
[assembly: AssemblyFileVersion("0.5.1.2")]

internal static class PortableLauncher
{
    // Replaced by the build script, never supplied by the caller.
    private const string PayloadSha256 = "__PAYLOAD_SHA256__";
    private static readonly string[] RequiredFiles = {
        "src/Freshservice_OSR_Upgrade_GUI.ps1", "src/OSR.Upgrade.Core.psm1",
        "src/OSR.Upgrade.Worker.ps1", "src/OSR.Recovery.LabFiles.psm1",
        "src/OSR.Recovery.WindowsServerBackup.psm1", "src/OSR.Gui.Settings.psm1", "LICENSE", "VERSION", "README.md"
    };

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            bool verifyOnly = args.Length == 1 && args[0] == "--verify-package";
            if (args.Length != 0 && !verifyOnly)
                throw new InvalidOperationException("Unsupported arguments. Open this application without arguments; select the operation inside the GUI.");
            string executable = Assembly.GetExecutingAssembly().Location;
            // Respect downloaded-file policy: do not strip or silently bypass MOTW.
            if (File.Exists(executable + ":Zone.Identifier"))
                throw new InvalidOperationException("This downloaded executable is blocked by Windows. Verify its published SHA-256 and source, then open File Properties and select Unblock if your policy permits it. No policy was changed.");
            string basePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "FreshworksOSRUpgradeManager", "Portable");
            string package;
            using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("OSR.Payload.zip"))
                package = ExtractPayload(payload, PayloadSha256, basePath);
            if (verifyOnly) return 0;
            string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string powershell = Path.Combine(windows, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!Environment.Is64BitOperatingSystem || !File.Exists(powershell))
                throw new InvalidOperationException("64-bit Windows with Windows PowerShell 5.1 is required. No runtime was installed.");
            ProcessStartInfo start = new ProcessStartInfo(powershell);
            start.Arguments = "-NoProfile -STA -File \"" +
                Path.Combine(package, "src", "Freshservice_OSR_Upgrade_GUI.ps1") + "\"";
            start.WorkingDirectory = package;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardError = true;
            start.RedirectStandardOutput = true;
            StringBuilder errors = new StringBuilder();
            using (Process process = new Process())
            {
                process.StartInfo = start;
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) {
                    if (e.Data != null) lock (errors) { if (errors.Length < 8000) errors.AppendLine(e.Data); }
                };
                process.OutputDataReceived += delegate { }; // Drain without writing runtime logs.
                if (!process.Start()) throw new InvalidOperationException("Windows PowerShell could not be started.");
                process.BeginErrorReadLine();
                process.BeginOutputReadLine();
                process.WaitForExit();
                if (process.ExitCode != 0)
                    throw new InvalidOperationException("The GUI could not complete (PowerShell exit " + process.ExitCode +
                        "). Execution policy, application control or an application error may be responsible.\n\n" + errors.ToString());
            }
            // Keep this unique payload: GUI elevation can outlive the first process.
            // Never remove modules from underneath the elevated GUI or worker.
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "OSR Upgrade Manager - launcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    internal static string ExtractPayload(Stream payload, string expectedHash, string basePath)
    {
        if (payload == null) throw new InvalidDataException("Embedded application payload is missing.");
        using (MemoryStream bytes = new MemoryStream())
        {
            payload.CopyTo(bytes);
            string actual;
            using (SHA256 sha = SHA256.Create()) actual = BitConverter.ToString(sha.ComputeHash(bytes.ToArray())).Replace("-", "");
            if (!String.Equals(actual, expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Embedded application checksum mismatch. Launch was blocked.");
            bytes.Position = 0;
            using (ZipArchive archive = new ZipArchive(bytes, ZipArchiveMode.Read))
            {
                // Validate the complete manifest before making filesystem changes.
                System.Collections.Generic.HashSet<string> names = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string name = entry.FullName;
                    if (Array.IndexOf(RequiredFiles, name) < 0 || !names.Add(name) || entry.Length > 2 * 1024 * 1024)
                        throw new InvalidDataException("Unexpected, duplicate or oversized application payload entry.");
                }
                if (names.Count != RequiredFiles.Length) throw new InvalidDataException("Application payload is incomplete.");
                string root = Path.GetFullPath(basePath);
                AssertNoReparseAncestors(root);
                Directory.CreateDirectory(root);
                AssertNoReparseAncestors(root);
                string destination = Path.Combine(root, Guid.NewGuid().ToString("N"));
                DirectorySecurity security = new DirectorySecurity();
                security.SetAccessRuleProtection(true, false);
                SecurityIdentifier user = WindowsIdentity.GetCurrent().User;
                foreach (SecurityIdentifier sid in new SecurityIdentifier[] { user,
                    new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                    new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null) })
                    security.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl,
                        InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
                Directory.CreateDirectory(destination, security);
                AssertNoReparseAncestors(destination);
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string target = Path.GetFullPath(Path.Combine(destination, entry.FullName.Replace('/', Path.DirectorySeparatorChar)));
                    if (!target.StartsWith(destination + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || target.Length >= 260)
                        throw new InvalidDataException("Application extraction path is unsafe or too long.");
                    AssertNoReparseAncestors(target);
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    using (Stream input = entry.Open())
                    using (FileStream output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                        input.CopyTo(output);
                }
                return destination;
            }
        }
    }

    private static void AssertNoReparseAncestors(string path)
    {
        for (string current = path; !String.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
            if ((Directory.Exists(current) || File.Exists(current)) &&
                (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Application extraction cannot traverse a reparse point.");
    }
}
