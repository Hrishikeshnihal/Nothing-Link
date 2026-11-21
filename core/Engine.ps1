param(
    [string]$Mode = "ScreenOff",
    [string]$Target = ""
)

Add-Type -Name WinAPI -Namespace Native -MemberDefinition '
[System.Runtime.InteropServices.DllImport("Kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
' -ErrorAction SilentlyContinue

$hwnd = [Native.WinAPI]::GetConsoleWindow()
if ($hwnd -ne [System.IntPtr]::Zero) {
    [Native.WinAPI]::ShowWindow($hwnd, 0) | Out-Null
}

$ErrorActionPreference = "SilentlyContinue"
$coreDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = Split-Path -Parent $coreDir
$adb = Join-Path $rootDir "bin\scrcpy\adb.exe"
$scrcpy = Join-Path $rootDir "bin\scrcpy\scrcpy.exe"
$scrcpyDir = Join-Path $rootDir "bin\scrcpy"
$iniFile = Join-Path $rootDir "settings.ini"

function Get-IniValue($file, $section, $key, $default="") {
    if (-not (Test-Path $file)) { return $default }
    $currentSection = ""
    foreach ($line in Get-Content $file) {
        $line = $line.Trim()
        if ($line.StartsWith("[") -and $line.EndsWith("]")) {
            $currentSection = $line.Substring(1, $line.Length - 2).Trim()
        } elseif ($currentSection -eq $section -and $line -match "^$key\s*=\s*(.*)$") {
            return $matches[1].Trim()
        }
    }
    return $default
}

function Test-PortFast($hostOrIp, $port, $timeoutMs = 350) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($hostOrIp, $port, $null, $null)
        $success = $iar.AsyncWaitHandle.WaitOne($timeoutMs)
        if ($success) {
            $client.EndConnect($iar)
            $client.Close()
            return $true
        }
        $client.Close()
    } catch {}
    return $false
}

function Find-PhoneTarget {
    # Check A: Direct Hotspot Gateway (2ms Mode)
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
    if ($gw -and $gw -ne "192.168.1.1" -and $gw -ne "0.0.0.0") {
        if (Test-PortFast $gw 5555 350) {
            return @{ Target = "$gw`:5555"; IsLocal = $true; Name = "Direct Hotspot (2ms Cable-Like Speed)" }
        }
    }

    # Check B: USB attached
    $devs = @(& $adb devices 2>$null | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of" })
    $usb = $devs | Where-Object { $_ -notmatch ":" } | Select-Object -First 1
    if ($usb) {
        $serial = ($usb.Trim() -split "\s+")[0]
        return @{ Target = $serial; IsLocal = $true; Name = "USB Cable (High-Speed)" }
    }

    # Check C: Active Wi-Fi targets in ADB table
    foreach ($d in $devs) {
        $ipPort = ($d.Trim() -split "\s+")[0]
        if ($ipPort -match "^(\d+\.\d+\.\d+\.\d+):(\d+)$") {
            if (Test-PortFast $matches[1] [int]$matches[2] 350) {
                return @{ Target = $ipPort; IsLocal = $true; Name = "Active Wi-Fi ($ipPort)" }
            }
        }
    }

    # Check D: Active 5G Cloud P2P Tunnel (Port 5556)
    if (Test-PortFast "127.0.0.1" 5556 300) {
        & $adb connect "127.0.0.1:5556" > $null 2>&1
        return @{ Target = "127.0.0.1:5556"; IsLocal = $false; Name = "5G Cloud P2P Mesh Tunnel" }
    }

    return $null
}

# --- 1. Resolve Target ---
$resolved = $null
if (-not [string]::IsNullOrWhiteSpace($Target)) {
    $resolved = @{ Target = $Target; IsLocal = $true; Name = "Custom ($Target)" }
} else {
    $resolved = Find-PhoneTarget
}

# If no target found, prompt user with dialog to connect
if (-not $resolved) {
    Add-Type -AssemblyName System.Windows.Forms
    $msg = "Nothing Phone not detected!`n`n" +
           "To connect your phone, choose either option:`n" +
           "1. Plug in your phone via USB Cable, OR`n" +
           "2. Turn ON your phone's Wi-Fi Hotspot and connect your PC Wi-Fi to it.`n`n" +
           "Connect your phone now and click OK to connect."
    $choice = [System.Windows.Forms.MessageBox]::Show(
        $msg,
        "Nothing Connect // Device Required",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    if ($choice -eq [System.Windows.Forms.DialogResult]::OK) {
        # Retry detection
        Start-Sleep -Seconds 1
        $resolved = Find-PhoneTarget
    }
}

if (-not $resolved) {
    exit 1
}

$phoneTarget = $resolved.Target
$isLocal = $resolved.IsLocal
$connectionName = $resolved.Name

# Connect ADB to target
& $adb connect $phoneTarget > $null 2>&1

# --- 2. Auto-Unlock & Navigation Bar ---
& (Join-Path $coreDir "Unlock.ps1") -Target $phoneTarget

# Enable on-screen buttons for PC mouse
& $adb -s $phoneTarget shell cmd overlay disable com.android.internal.systemui.navbar.gestural > $null 2>&1
& $adb -s $phoneTarget shell cmd overlay enable com.android.internal.systemui.navbar.threebutton > $null 2>&1
& $adb -s $phoneTarget shell settings put secure navigation_mode 0 > $null 2>&1

# --- 3. Build Scrcpy Arguments ---
$maxFps = Get-IniValue $iniFile "Display" "MaxFps" "120"
$videoCodec = Get-IniValue $iniFile "Display" "VideoCodec" "h265"

$argsList = [System.Collections.Generic.List[string]]::new()
$argsList.Add("-s")
$argsList.Add($phoneTarget)
$argsList.Add("--window-title=Nothing-Connect")

if ($Mode -eq "ScreenOn") {
    # Screen ON: Both phone and PC display simultaneously
    $argsList.Add("--stay-awake")
} else {
    # Screen OFF: Physical phone screen stays black & cool (default)
    $argsList.Add("--turn-screen-off")
    $argsList.Add("--stay-awake")
    $argsList.Add("--power-off-on-close")
}

if ($isLocal) {
    # 120 FPS High-Quality
    $argsList.Add("--video-codec=$videoCodec")
    $argsList.Add("--max-fps=$maxFps")
} else {
    # 60 FPS 5G Cellular
    $argsList.Add("--video-codec=h264")
    $argsList.Add("--video-encoder=c2.mtk.avc.encoder")
    $argsList.Add("--video-codec-options=i-frame-interval=1")
    $argsList.Add("--max-size=1200")
    $argsList.Add("--video-bit-rate=4M")
    $argsList.Add("--max-fps=60")
    $argsList.Add("--no-audio")
}

# --- 4. Launch Scrcpy GUI Window ---
Push-Location $scrcpyDir
try {
    $argString = ($argsList | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join " "
    $proc = Start-Process -FilePath $scrcpy -ArgumentList $argString -WorkingDirectory $scrcpyDir -PassThru
    $proc.WaitForExit()
} finally {
    Pop-Location
    # Cleanup: Restore gesture navigation and put phone screen to sleep
    & $adb -s $phoneTarget shell cmd overlay disable com.android.internal.systemui.navbar.threebutton > $null 2>&1
    & $adb -s $phoneTarget shell cmd overlay enable com.android.internal.systemui.navbar.gestural > $null 2>&1
    & $adb -s $phoneTarget shell settings put secure navigation_mode 2 > $null 2>&1
    & $adb -s $phoneTarget shell input keyevent 223 > $null 2>&1
}
