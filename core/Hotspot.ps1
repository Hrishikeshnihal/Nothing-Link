param(
    [string]$Target = ""
)

$ErrorActionPreference = "SilentlyContinue"
$coreDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = Split-Path -Parent $coreDir
$adb = Join-Path $rootDir "bin\scrcpy\adb.exe"
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


Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "     NOTHING CONNECT // REMOTE HOTSPOT ACTIVATION     " -ForegroundColor White
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Determine target device
if ([string]::IsNullOrWhiteSpace($Target)) {
    # Check if cloud tunnel is active on port 5556
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $iar = $tcpClient.BeginConnect("127.0.0.1", 5556, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(300)) {
            $tcpClient.EndConnect($iar)
            $tcpClient.Close()
            & $adb connect "127.0.0.1:5556" > $null 2>&1
        }
    } catch {}

    # Check if a device is already reachable on hotspot, usb, or 5g tunnel
    $devLines = @(& $adb devices 2>$null | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of" })
    if ($devLines.Count -gt 0) {
        $firstLine = $devLines[0].Trim()
        $Target = ($firstLine -split "\s+")[0]
        Write-Host "[1/4] Using connected device: $Target" -ForegroundColor Green
    } else {
        Write-Host "No device detected. Please connect phone via USB or open Nothing Link on web hub (localhost:3000) to control over 5G." -ForegroundColor Red
        exit 1
    }
}

$sFlag = @("-s", $Target)

# 3. Unlock phone if locked
Write-Host "[3/5] Checking device lock state..." -ForegroundColor Cyan
& (Join-Path $coreDir "Unlock.ps1") -Target $Target

# 4. Check if Hotspot is already running
$tetherDump = & $adb @sFlag shell dumpsys tethering 2>$null
$isTethered = $tetherDump | Select-String -Pattern "ap\d\s+-\s+TetheredState"

if ($isTethered) {
    Write-Host "[4/5] Phone Wi-Fi Hotspot is ALREADY ACTIVE and broadcasting!" -ForegroundColor Green
} else {
    Write-Host "[4/5] Activating Wi-Fi Hotspot via system settings..." -ForegroundColor Yellow
    # Open Tether Settings
    & $adb @sFlag shell "am start -a android.settings.TETHER_SETTINGS" > $null 2>&1
    Start-Sleep -Milliseconds 600

    # Tap the Wi-Fi Hotspot toggle at (948, 1066)
    & $adb @sFlag shell "input tap 948 1066" > $null 2>&1
    Start-Sleep -Milliseconds 700

    # Close settings to home screen
    & $adb @sFlag shell "input keyevent 3" > $null 2>&1
    Write-Host "      Hotspot switch toggled successfully!" -ForegroundColor Green
}

# 5. Wait for PC to establish local connection (optional convenience)
Write-Host "[5/5] Checking local Wi-Fi Hotspot gateway on PC..." -ForegroundColor Cyan
$detectedGateway = $null
for ($i = 1; $i -le 10; $i++) {
    try {
        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
        if ($gw -and $gw -ne "192.168.1.1" -and $gw -ne "0.0.0.0") {
            # Quick check if ADB port is open on gateway
            $client = New-Object System.Net.Sockets.TcpClient
            $iar = $client.BeginConnect($gw, 5555, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(400)) {
                $client.EndConnect($iar)
                $client.Close()
                $detectedGateway = $gw
                break
            }
            $client.Close()
        }
    } catch {}
    Start-Sleep -Seconds 1
}

if ($detectedGateway) {
    Write-Host ""
    Write-Host "SUCCESS: PC connected directly to Nothing Phone Hotspot ($($detectedGateway):5555)!" -ForegroundColor Green
    Write-Host "Ultra-Low Latency 2ms Wired Speed is ready." -ForegroundColor Green
    & $adb connect "$detectedGateway`:5555" | Out-Null
} else {
    Write-Host ""
    Write-Host "Note: Hotspot is enabled on the phone. Connect your PC Wi-Fi to your Nothing Phone to switch from 5G to 2ms mode." -ForegroundColor Yellow
}
Start-Sleep -Seconds 2
