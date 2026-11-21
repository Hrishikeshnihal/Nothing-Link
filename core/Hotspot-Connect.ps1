# Nothing Connect // Hotspot Direct Mirror Engine
# High-Speed 120 FPS Low-Latency Screen Mirroring with Auto-Unlock (Pattern 159873)
# Physical phone screen stays completely OFF during mirroring.

$ErrorActionPreference = "SilentlyContinue"
$coreDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = Split-Path -Parent $coreDir
$adb = Join-Path $rootDir "bin\scrcpy\adb.exe"
$scrcpy = Join-Path $rootDir "bin\scrcpy\scrcpy.exe"
$scrcpyDir = Join-Path $rootDir "bin\scrcpy"
$iniFile = Join-Path $rootDir "settings.ini"
$unlockSh = Join-Path $coreDir "unlock.sh"

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

function Test-PortFast($hostOrIp, $port = 5555, $timeoutMs = 300) {
    if ([string]::IsNullOrWhiteSpace($hostOrIp) -or $hostOrIp -eq "0.0.0.0") { return $false }
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($hostOrIp, $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($timeoutMs)) {
            $client.EndConnect($iar)
            $client.Close()
            return $true
        }
        $client.Close()
    } catch {}
    return $false
}

Write-Host "==========================================================" -ForegroundColor Red
Write-Host "   NOTHING CONNECT // HOTSPOT DIRECT MIRROR (120 FPS)     " -ForegroundColor White
Write-Host "   Physical Screen: OFF | Auto-Unlock: Pattern 159873     " -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Red
Write-Host ""

# 1. Collect candidate IPs
$configuredIp = Get-IniValue $iniFile "Network" "WirelessIp" "10.38.115.80"
$maxFps = Get-IniValue $iniFile "Display" "MaxFps" "120"
$videoCodec = Get-IniValue $iniFile "Display" "VideoCodec" "h265"

$targetDevice = $null
$maxRetries = 15
$attempt = 0

Write-Host "[1/4] Detecting Nothing Phone on Hotspot network..." -ForegroundColor Cyan

while ($attempt -lt $maxRetries) {
    $attempt++

    # Check A: Direct USB connection if plugged in
    $devs = @(& $adb devices 2>$null | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of" })
    $usb = $devs | Where-Object { $_ -notmatch ":" } | Select-Object -First 1
    if ($usb) {
        $targetDevice = ($usb.Trim() -split "\s+")[0]
        Write-Host "      Found phone via USB cable: $targetDevice" -ForegroundColor Green
        break
    }

    # Check B: Gather network gateways from active adapters
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($configuredIp)) {
        $candidates.Add($configuredIp)
    }

    $gwList = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NextHop)
    foreach ($gw in $gwList) {
        if ($gw -and $gw -ne "0.0.0.0" -and $gw -ne "192.168.1.1" -and (-not $candidates.Contains($gw))) {
            $candidates.Add($gw)
        }
    }
    foreach ($fallback in @("10.38.115.80", "192.168.43.1", "192.168.137.1")) {
        if (-not $candidates.Contains($fallback)) {
            $candidates.Add($fallback)
        }
    }

    # Test port 5555 on candidate IPs
    foreach ($ip in $candidates) {
        if (Test-PortFast $ip 5555 250) {
            $targetDevice = "$ip`:5555"
            Write-Host "      Found Nothing Phone Hotspot at: $targetDevice" -ForegroundColor Green
            break
        }
    }

    if ($targetDevice) { break }

    # Check C: Already connected in ADB table
    foreach ($d in $devs) {
        $ipPort = ($d.Trim() -split "\s+")[0]
        if ($ipPort -match "^(\d+\.\d+\.\d+\.\d+):(\d+)$") {
            if (Test-PortFast $matches[1] [int]$matches[2] 250) {
                $targetDevice = $ipPort
                Write-Host "      Found active ADB connection: $targetDevice" -ForegroundColor Green
                break
            }
        }
    }

    if ($targetDevice) { break }

    Write-Host "      [Attempt $attempt/$maxRetries] Waiting for PC to acquire Hotspot IP..." -ForegroundColor DarkYellow
    Start-Sleep -Seconds 1
}

if (-not $targetDevice) {
    Write-Host ""
    Write-Host "[ERROR] Could not detect your Nothing Phone on Hotspot." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please ensure:" -ForegroundColor Yellow
    Write-Host "  1. Hotspot is turned ON on your Nothing Phone." -ForegroundColor White
    Write-Host "  2. Your PC Wi-Fi is CONNECTED to your phone's hotspot." -ForegroundColor White
    Write-Host "  3. Wireless debugging is active (or plug USB cable once)." -ForegroundColor White
    Write-Host ""
    Write-Host "Closing in 5 seconds..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
    exit 1
}

# 2. Connect via ADB
Write-Host "[2/4] Connecting ADB to $targetDevice..." -ForegroundColor Cyan
if ($targetDevice -match ":") {
    & $adb connect $targetDevice > $null 2>&1
    Start-Sleep -Milliseconds 400
}

# Verify device state
$checkDev = & $adb -s $targetDevice get-state 2>$null
if ($checkDev -notmatch "device") {
    # Retry connect once
    & $adb connect $targetDevice > $null 2>&1
    Start-Sleep -Milliseconds 500
}

# 3. Auto-Unlock with Pattern 159873
Write-Host "[3/4] Auto-unlocking screen with pattern 159873..." -ForegroundColor Cyan

# Wake screen
& $adb -s $targetDevice shell input keyevent 224 > $null 2>&1
Start-Sleep -Milliseconds 150

# Bring up bouncer
& $adb -s $targetDevice shell input keyevent 82 > $null 2>&1
Start-Sleep -Milliseconds 100
& $adb -s $targetDevice shell input swipe 540 1800 540 500 150 > $null 2>&1
Start-Sleep -Milliseconds 250

# Execute unlock pattern stroke
if (Test-Path $unlockSh) {
    & $adb -s $targetDevice push $unlockSh /data/local/tmp/unlock.sh > $null 2>&1
    & $adb -s $targetDevice shell chmod 755 /data/local/tmp/unlock.sh > $null 2>&1
    & $adb -s $targetDevice shell "sh /data/local/tmp/unlock.sh" > $null 2>&1
} else {
    # Direct motion event fallback
    $motionCmd = "cmd input motionevent DOWN 247 1163; cmd input motionevent MOVE 540 1456; cmd input motionevent MOVE 833 1750; cmd input motionevent MOVE 540 1750; cmd input motionevent MOVE 247 1750; cmd input motionevent MOVE 540 1456; cmd input motionevent MOVE 833 1163; cmd input motionevent UP 833 1163"
    & $adb -s $targetDevice shell $motionCmd > $null 2>&1
}

# Return to Home screen
& $adb -s $targetDevice shell input keyevent 3 > $null 2>&1
Write-Host "      Screen unlocked!" -ForegroundColor Green

# Optional: Enable 3-button navigation for PC mouse convenience
& $adb -s $targetDevice shell cmd overlay disable com.android.internal.systemui.navbar.gestural > $null 2>&1
& $adb -s $targetDevice shell cmd overlay enable com.android.internal.systemui.navbar.threebutton > $null 2>&1
& $adb -s $targetDevice shell settings put secure navigation_mode 0 > $null 2>&1

# 4. Launch Scrcpy Mirroring (Physical Screen OFF)
Write-Host "[4/4] Launching 120 FPS Mirroring (Physical screen will stay OFF)..." -ForegroundColor Cyan

$argsList = [System.Collections.Generic.List[string]]::new()
$argsList.Add("-s")
$argsList.Add($targetDevice)
$argsList.Add("--window-title=Nothing Phone (2a) Plus // Hotspot 120 FPS")
$argsList.Add("--turn-screen-off")
$argsList.Add("--stay-awake")
$argsList.Add("--power-off-on-close")
$argsList.Add("--video-codec=$videoCodec")
$argsList.Add("--max-fps=$maxFps")

Push-Location $scrcpyDir
try {
    $argString = ($argsList | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join " "
    $proc = Start-Process -FilePath $scrcpy -ArgumentList $argString -WorkingDirectory $scrcpyDir -PassThru
    $proc.WaitForExit()
} finally {
    Pop-Location
    # Cleanup on exit: Restore gesture navigation & put phone screen to sleep
    & $adb -s $targetDevice shell cmd overlay disable com.android.internal.systemui.navbar.threebutton > $null 2>&1
    & $adb -s $targetDevice shell cmd overlay enable com.android.internal.systemui.navbar.gestural > $null 2>&1
    & $adb -s $targetDevice shell settings put secure navigation_mode 2 > $null 2>&1
    & $adb -s $targetDevice shell input keyevent 223 > $null 2>&1
}

Write-Host "Mirror session finished." -ForegroundColor Green
