using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;

namespace NothingLink;

public partial class MainWindow : Window
{
    private string _rootDir = "";
    private string _adbPath = "";
    private string _scrcpyPath = "";
    private string _iniPath = "";
    private string _apkPath = "";

    private string _connectedTarget = "";
    private bool _isDeviceConnected = false;
    private DispatcherTimer _pollTimer = null!;

    public MainWindow()
    {
        InitializeComponent();
        ResolvePaths();
        LoadSettings();

        Log("Nothing Link Desktop Control Hub initialized.");
        Log($"Base Directory: {_rootDir}");

        // Setup background device polling timer
        _pollTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(2.5)
        };
        _pollTimer.Tick += async (s, e) => await ScanDeviceAsync(false);
        _pollTimer.Start();

        // Initial scan
        _ = ScanDeviceAsync(true);
    }

    private void ResolvePaths()
    {
        string current = AppDomain.CurrentDomain.BaseDirectory;
        // Search upwards for settings.ini or bin/scrcpy
        DirectoryInfo? dir = new DirectoryInfo(current);
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "settings.ini")) || Directory.Exists(Path.Combine(dir.FullName, "bin", "scrcpy")))
            {
                _rootDir = dir.FullName;
                break;
            }
            dir = dir.Parent;
        }

        if (string.IsNullOrEmpty(_rootDir))
        {
            _rootDir = current;
        }

        _adbPath = Path.Combine(_rootDir, "bin", "scrcpy", "adb.exe");
        _scrcpyPath = Path.Combine(_rootDir, "bin", "scrcpy", "scrcpy.exe");
        _iniPath = Path.Combine(_rootDir, "settings.ini");
        _apkPath = Path.Combine(_rootDir, "companion", "nothing-connect-companion.apk");
    }

    private void Log(string message)
    {
        Dispatcher.Invoke(() =>
        {
            string stamp = DateTime.Now.ToString("HH:mm:ss");
            TxtLog.AppendText($"[{stamp}] {message}\n");
            LogScroller.ScrollToEnd();
        });
    }

    #region INI Management

    private Dictionary<string, Dictionary<string, string>> ParseIni(string path)
    {
        var result = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(path)) return result;

        string currentSection = "";
        foreach (var raw in File.ReadAllLines(path))
        {
            string line = raw.Trim();
            if (line.StartsWith(";") || line.StartsWith("#") || string.IsNullOrWhiteSpace(line)) continue;
            if (line.StartsWith("[") && line.EndsWith("]"))
            {
                currentSection = line.Substring(1, line.Length - 2).Trim();
                if (!result.ContainsKey(currentSection))
                    result[currentSection] = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            }
            else if (!string.IsNullOrEmpty(currentSection) && line.Contains('='))
            {
                var parts = line.Split('=', 2);
                result[currentSection][parts[0].Trim()] = parts[1].Trim();
            }
        }
        return result;
    }

    private string GetIniValue(Dictionary<string, Dictionary<string, string>> ini, string section, string key, string fallback)
    {
        if (ini.TryGetValue(section, out var sec) && sec.TryGetValue(key, out var val))
            return val;
        return fallback;
    }

    private void LoadSettings()
    {
        var ini = ParseIni(_iniPath);
        string lockType = GetIniValue(ini, "Security", "LockType", "pattern").ToLower();
        string lockCode = GetIniValue(ini, "Security", "LockCode", "");
        string pattern = GetIniValue(ini, "Security", "Pattern", "159873");

        RbPattern.IsChecked = lockType == "pattern";
        RbPin.IsChecked = lockType == "pin";
        RbPassword.IsChecked = lockType == "password";
        RbNone.IsChecked = lockType == "none";

        if (lockType == "pattern")
        {
            TxtLockCode.Text = pattern;
            TxtLockHint.Text = "Pattern sequence 1-9 (e.g. 159873). Dot map: 123 top, 456 mid, 789 btm.";
        }
        else if (lockType == "pin")
        {
            TxtLockCode.Text = lockCode;
            TxtLockHint.Text = "Enter numeric PIN (e.g. 1234).";
        }
        else if (lockType == "password")
        {
            TxtLockCode.Text = lockCode;
            TxtLockHint.Text = "Enter alphanumeric password.";
        }
        else
        {
            TxtLockCode.Text = "";
            TxtLockHint.Text = "Auto-Unlock is set to None / Swipe (no code needed).";
        }
    }

    private void SaveSettings()
    {
        string lockType = "pattern";
        if (RbPin.IsChecked == true) lockType = "pin";
        else if (RbPassword.IsChecked == true) lockType = "password";
        else if (RbNone.IsChecked == true) lockType = "none";

        string code = TxtLockCode.Text.Trim();

        try
        {
            if (File.Exists(_iniPath))
            {
                var lines = new List<string>(File.ReadAllLines(_iniPath));
                bool inSec = false;
                bool hasLockType = false;
                bool hasLockCode = false;
                bool hasPattern = false;

                for (int i = 0; i < lines.Count; i++)
                {
                    string trimmed = lines[i].Trim();
                    if (trimmed.StartsWith("[") && trimmed.EndsWith("]"))
                    {
                        inSec = trimmed.Equals("[Security]", StringComparison.OrdinalIgnoreCase);
                    }
                    else if (inSec)
                    {
                        if (trimmed.StartsWith("LockType=", StringComparison.OrdinalIgnoreCase))
                        {
                            lines[i] = $"LockType={lockType}";
                            hasLockType = true;
                        }
                        else if (trimmed.StartsWith("LockCode=", StringComparison.OrdinalIgnoreCase))
                        {
                            lines[i] = $"LockCode={(lockType is "pin" or "password" ? code : "")}";
                            hasLockCode = true;
                        }
                        else if (trimmed.StartsWith("Pattern=", StringComparison.OrdinalIgnoreCase))
                        {
                            lines[i] = $"Pattern={(lockType == "pattern" ? (string.IsNullOrEmpty(code) ? "159873" : code) : "")}";
                            hasPattern = true;
                        }
                    }
                }

                if (!hasLockType) lines.Add($"LockType={lockType}");
                if (!hasLockCode && lockType is "pin" or "password") lines.Add($"LockCode={code}");
                if (!hasPattern && lockType == "pattern") lines.Add($"Pattern={(string.IsNullOrEmpty(code) ? "159873" : code)}");

                File.WriteAllLines(_iniPath, lines);
                Log($"Security settings updated: LockType={lockType}");
            }
        }
        catch (Exception ex)
        {
            Log($"Error saving settings: {ex.Message}");
        }
    }

    #endregion

    #region ADB Process Helpers

    private async Task<(int ExitCode, string Output, string Error)> RunAdbAsync(string args, int timeoutMs = 8000)
    {
        if (!File.Exists(_adbPath))
        {
            return (-1, "", $"ADB not found at: {_adbPath}");
        }

        return await Task.Run(() =>
        {
            try
            {
                using var p = new Process();
                p.StartInfo = new ProcessStartInfo
                {
                    FileName = _adbPath,
                    Arguments = args,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                p.Start();
                string output = p.StandardOutput.ReadToEnd();
                string error = p.StandardError.ReadToEnd();
                if (!p.WaitForExit(timeoutMs))
                {
                    p.Kill();
                    return (-2, output, "ADB command timed out.");
                }
                return (p.ExitCode, output.Trim(), error.Trim());
            }
            catch (Exception ex)
            {
                return (-3, "", ex.Message);
            }
        });
    }

    #endregion

    #region Device Scanning

    private async Task ScanDeviceAsync(bool verbose = false)
    {
        var res = await RunAdbAsync("devices");
        if (res.ExitCode != 0)
        {
            UpdateStatus(false, "ADB engine unavailable", res.Error);
            return;
        }

        string target = "";
        var lines = res.Output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        foreach (var line in lines)
        {
            if (line.Contains("\tdevice"))
            {
                target = line.Split('\t')[0].Trim();
                break;
            }
        }

        // If no device attached, attempt wireless IP from settings.ini
        if (string.IsNullOrEmpty(target))
        {
            var ini = ParseIni(_iniPath);
            string wirelessIp = GetIniValue(ini, "Network", "WirelessIp", "");
            if (!string.IsNullOrEmpty(wirelessIp))
            {
                string ipTarget = wirelessIp.Contains(':') ? wirelessIp : $"{wirelessIp}:5555";
                var connRes = await RunAdbAsync($"connect {ipTarget}", 3000);
                if (connRes.Output.Contains("connected to"))
                {
                    target = ipTarget;
                }
            }
        }

        if (!string.IsNullOrEmpty(target))
        {
            _connectedTarget = target;
            _isDeviceConnected = true;

            // Fetch device model asynchronously
            var modelRes = await RunAdbAsync($"-s {target} shell getprop ro.product.model", 3000);
            string model = string.IsNullOrEmpty(modelRes.Output) ? "Nothing Phone" : modelRes.Output;
            bool isWireless = target.Contains(':');

            UpdateStatus(true, $"{model} Connected", $"Target: {target} • Mode: {(isWireless ? "Wi-Fi Hotspot / Wireless" : "USB High-Speed")}");
            if (verbose) Log($"Detected device: {model} ({target})");
        }
        else
        {
            _connectedTarget = "";
            _isDeviceConnected = false;
            UpdateStatus(false, "Scanning for Nothing Phone...", "Connect via USB or ensure Phone Hotspot is active.");
        }
    }

    private void UpdateStatus(bool connected, string title, string details)
    {
        Dispatcher.Invoke(() =>
        {
            StatusDot.Fill = new SolidColorBrush(connected ? Color.FromRgb(16, 185, 129) : Color.FromRgb(234, 179, 8));
            StatusTitle.Text = title;
            StatusDetails.Text = details;
        });
    }

    #endregion

    #region Auto-Unlock Logic

    private async Task<bool> UnlockDeviceAsync(string target)
    {
        Log("Checking lockscreen state...");
        var policyRes = await RunAdbAsync($"-s {target} shell dumpsys window policy");
        bool isShowing = policyRes.Output.Contains("showing=true") && !policyRes.Output.Contains("mKeyguardUnlocked=true");

        if (!isShowing)
        {
            Log("Device is already unlocked.");
            return true;
        }

        var ini = ParseIni(_iniPath);
        string lockType = GetIniValue(ini, "Security", "LockType", "pattern").ToLower();
        string lockCode = GetIniValue(ini, "Security", "LockCode", "");
        string pattern = GetIniValue(ini, "Security", "Pattern", "159873");

        Log($"Executing auto-unlock for mode: {lockType.ToUpper()}...");

        if (lockType == "none")
        {
            await RunAdbAsync($"-s {target} shell input keyevent 224");
            await Task.Delay(150);
            await RunAdbAsync($"-s {target} shell input keyevent 82");
            return true;
        }
        else if (lockType is "pin" or "password")
        {
            if (string.IsNullOrEmpty(lockCode))
            {
                Log("[WARN] PIN/Password is empty in settings! Please enter it in Settings.");
                return false;
            }
            await RunAdbAsync($"-s {target} shell input keyevent 224");
            await Task.Delay(150);
            await RunAdbAsync($"-s {target} shell input keyevent 82");
            await Task.Delay(300);
            await RunAdbAsync($"-s {target} shell input text '{lockCode}'");
            await Task.Delay(150);
            await RunAdbAsync($"-s {target} shell input keyevent 66");
            return true;
        }
        else
        {
            // Dynamic Pattern Resolution & Gesture Generation
            var wmRes = await RunAdbAsync($"-s {target} shell wm size");
            double scaleX = 1.0, scaleY = 1.0;
            var match = Regex.Match(wmRes.Output, @"(\d+)x(\d+)");
            if (match.Success)
            {
                double w = double.Parse(match.Groups[1].Value);
                double h = double.Parse(match.Groups[2].Value);
                scaleX = w / 1080.0;
                scaleY = h / 2412.0;
            }

            var dotMap = new Dictionary<char, (int X, int Y)>
            {
                ['1'] = ((int)(247 * scaleX), (int)(1163 * scaleY)),
                ['2'] = ((int)(540 * scaleX), (int)(1163 * scaleY)),
                ['3'] = ((int)(833 * scaleX), (int)(1163 * scaleY)),
                ['4'] = ((int)(247 * scaleX), (int)(1456 * scaleY)),
                ['5'] = ((int)(540 * scaleX), (int)(1456 * scaleY)),
                ['6'] = ((int)(833 * scaleX), (int)(1456 * scaleY)),
                ['7'] = ((int)(247 * scaleX), (int)(1750 * scaleY)),
                ['8'] = ((int)(540 * scaleX), (int)(1750 * scaleY)),
                ['9'] = ((int)(833 * scaleX), (int)(1750 * scaleY)),
            };

            var scriptLines = new List<string>
            {
                "#!/system/bin/sh",
                "cmd input keyevent 224",
                "cmd input keyevent 82",
                "sleep 0.4"
            };

            if (pattern.Length > 0 && dotMap.ContainsKey(pattern[0]))
            {
                var first = dotMap[pattern[0]];
                scriptLines.Add($"cmd input motionevent DOWN {first.X} {first.Y}");

                for (int i = 0; i < pattern.Length - 1; i++)
                {
                    if (dotMap.ContainsKey(pattern[i]) && dotMap.ContainsKey(pattern[i + 1]))
                    {
                        var p1 = dotMap[pattern[i]];
                        var p2 = dotMap[pattern[i + 1]];
                        for (int step = 1; step <= 4; step++)
                        {
                            int ix = (int)(p1.X + (p2.X - p1.X) * (step / 4.0));
                            int iy = (int)(p1.Y + (p2.Y - p1.Y) * (step / 4.0));
                            scriptLines.Add($"cmd input motionevent MOVE {ix} {iy}");
                        }
                    }
                }
                var last = dotMap[pattern[^1]];
                scriptLines.Add($"cmd input motionevent UP {last.X} {last.Y}");
            }

            string tmp = Path.Combine(Path.GetTempPath(), "nothing_unlock.sh");
            await File.WriteAllLinesAsync(tmp, scriptLines);
            await RunAdbAsync($"-s {target} push \"{tmp}\" /data/local/tmp/unlock.sh");
            await RunAdbAsync($"-s {target} shell chmod 755 /data/local/tmp/unlock.sh");
            try { File.Delete(tmp); } catch { }

            await RunAdbAsync($"-s {target} shell sh /data/local/tmp/unlock.sh");
            await Task.Delay(350);
            Log("Pattern gesture dispatched.");
            return true;
        }
    }

    #endregion

    #region Action Handlers

    private async void BtnMirrorScreenOff_Click(object sender, RoutedEventArgs e)
    {
        await LaunchMirroringAsync(screenOff: true);
    }

    private async void BtnMirrorScreenOn_Click(object sender, RoutedEventArgs e)
    {
        await LaunchMirroringAsync(screenOff: false);
    }

    private async Task LaunchMirroringAsync(bool screenOff)
    {
        if (string.IsNullOrEmpty(_connectedTarget))
        {
            await ScanDeviceAsync(true);
            if (string.IsNullOrEmpty(_connectedTarget))
            {
                MessageBox.Show("No Nothing Phone detected. Please connect phone via USB or connect PC to Phone Wi-Fi Hotspot.", "Nothing Link", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
        }

        string target = _connectedTarget;
        Log($"Initiating Mirroring session for {target} (ScreenOff: {screenOff})...");

        // 1. Auto-Unlock
        await UnlockDeviceAsync(target);

        // 2. Enable 3-Button Navigation for PC Mouse control
        await RunAdbAsync($"-s {target} shell cmd overlay disable com.android.internal.systemui.navbar.gestural");
        await RunAdbAsync($"-s {target} shell cmd overlay enable com.android.internal.systemui.navbar.threebutton");
        await RunAdbAsync($"-s {target} shell settings put secure navigation_mode 0");

        // 3. Launch Scrcpy
        if (!File.Exists(_scrcpyPath))
        {
            Log($"[ERROR] Scrcpy not found at: {_scrcpyPath}");
            MessageBox.Show($"Scrcpy binary not found at:\n{_scrcpyPath}", "Scrcpy Missing", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        string scrcpyArgs = $"-s {target} --max-fps 120 --video-codec=h265 --shortcut-mod=lalt,ralt --window-title=\"Nothing Phone (2a) Plus\"";
        if (screenOff)
        {
            scrcpyArgs += " --turn-screen-off --stay-awake --power-off-on-close";
        }

        Log($"Launching Scrcpy: {scrcpyArgs}");

        try
        {
            var p = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = _scrcpyPath,
                    Arguments = scrcpyArgs,
                    WorkingDirectory = Path.GetDirectoryName(_scrcpyPath),
                    UseShellExecute = false
                }
            };
            p.Start();
            Log("Scrcpy 120 FPS Mirroring active!");
        }
        catch (Exception ex)
        {
            Log($"Failed to start Scrcpy: {ex.Message}");
        }
    }

    private async void BtnToggleHotspot_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_connectedTarget))
        {
            MessageBox.Show("Please connect device to toggle hotspot.", "Nothing Link", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        Log("Sending Wi-Fi Hotspot toggle command via Shizuku shell...");
        string cmd = "am start -a android.settings.TETHER_SETTINGS; sleep 0.4; input tap 948 1066; sleep 0.3; input keyevent 3";
        var res = await RunAdbAsync($"-s {targetParam()} shell \"{cmd}\"");
        Log("Hotspot toggle signal sent!");
    }

    private async void BtnSetupDevice_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_connectedTarget))
        {
            MessageBox.Show("Please plug your phone via USB cable with USB Debugging enabled before running setup.", "Phone Not Detected", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        string target = _connectedTarget;
        Log($"=== Starting 1-Click Setup on {target} ===");

        // 1. Install Companion APK
        if (File.Exists(_apkPath))
        {
            Log("Installing Nothing Link Companion APK...");
            var instRes = await RunAdbAsync($"-s {target} install -r \"{_apkPath}\"", 20000);
            Log($"Install Result: {instRes.Output}");
        }

        // 2. Grant permissions
        Log("Granting permissions (Notifications, Shizuku, Accessibility, Battery Whitelist)...");
        await RunAdbAsync($"-s {target} shell pm grant com.nothing.link.companion android.permission.POST_NOTIFICATIONS 2>/dev/null");
        await RunAdbAsync($"-s {target} shell pm grant com.nothing.link.companion moe.shizuku.manager.permission.API_V23 2>/dev/null");
        await RunAdbAsync($"-s {target} shell dumpsys deviceidle whitelist +com.nothing.link.companion 2>/dev/null");
        await RunAdbAsync($"-s {target} shell settings put secure enabled_accessibility_services com.nothing.link.companion/com.nothing.link.companion.service.NothingAccessibilityService 2>/dev/null");
        await RunAdbAsync($"-s {target} shell settings put secure accessibility_enabled 1 2>/dev/null");

        // 3. Start Shizuku
        Log("Starting Shizuku service on phone...");
        string shizukuCmd = "p=$(pm path moe.shizuku.privileged.api | head -n 1 | cut -d: -f2); d=$(dirname \"$p\"); if [ -f \"$d/lib/arm64/libshizuku.so\" ]; then \"$d/lib/arm64/libshizuku.so\"; else sh /sdcard/Android/data/moe.shizuku.privileged.api/starter.sh; fi 2>/dev/null";
        await RunAdbAsync($"-s {target} shell \"{shizukuCmd}\"");

        // 4. Enable Wireless ADB TCP/IP 5555
        Log("Enabling Wireless ADB on port 5555...");
        await RunAdbAsync($"-s {target} tcpip 5555");

        // 5. Launch companion app
        await RunAdbAsync($"-s {target} shell monkey -p com.nothing.link.companion -c android.intent.category.LAUNCHER 1 2>/dev/null");

        Log("=== 1-Click Setup Completed Successfully! ===");
        MessageBox.Show("Phone Setup Complete!\n\nWireless ADB is open on port 5555.\nYou can now disconnect USB and mirror over Wi-Fi Hotspot anytime.", "Setup Success", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private async void BtnStartShizuku_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_connectedTarget))
        {
            MessageBox.Show("Connect device first.", "Device Missing", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        Log("Starting Shizuku service via ADB...");
        string shizukuCmd = "p=$(pm path moe.shizuku.privileged.api | head -n 1 | cut -d: -f2); d=$(dirname \"$p\"); if [ -f \"$d/lib/arm64/libshizuku.so\" ]; then \"$d/lib/arm64/libshizuku.so\"; else sh /sdcard/Android/data/moe.shizuku.privileged.api/starter.sh; fi 2>/dev/null";
        var res = await RunAdbAsync($"-s {targetParam()} shell \"{shizukuCmd}\"");
        Log($"Shizuku Starter: {res.Output}");
        MessageBox.Show("Shizuku Server Started!", "Shizuku", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void BtnOpenDashboard_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "http://localhost:3000",
                UseShellExecute = true
            });
            Log("Opened Cloud Web Dashboard in browser.");
        }
        catch (Exception ex)
        {
            Log($"Could not open browser: {ex.Message}");
        }
    }

    private void LockType_Changed(object sender, RoutedEventArgs e)
    {
        if (!IsLoaded) return;
        if (RbPattern.IsChecked == true)
        {
            TxtLockHint.Text = "Pattern sequence 1-9 (e.g. 159873). Dot map: 123 top, 456 mid, 789 btm.";
        }
        else if (RbPin.IsChecked == true)
        {
            TxtLockHint.Text = "Enter numeric PIN (e.g. 1234).";
        }
        else if (RbPassword.IsChecked == true)
        {
            TxtLockHint.Text = "Enter alphanumeric password.";
        }
        else
        {
            TxtLockHint.Text = "Auto-Unlock is set to None / Swipe (no code needed).";
        }
    }

    private void BtnSaveSettings_Click(object sender, RoutedEventArgs e)
    {
        SaveSettings();
        MessageBox.Show("Lock screen settings saved successfully!", "Settings Saved", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void BtnScan_Click(object sender, RoutedEventArgs e)
    {
        _ = ScanDeviceAsync(true);
    }

    private void BtnClearLog_Click(object sender, RoutedEventArgs e)
    {
        TxtLog.Clear();
    }

    private string targetParam() => string.IsNullOrEmpty(_connectedTarget) ? "" : _connectedTarget;

    #endregion
}
