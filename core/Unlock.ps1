param(
    [string]$Target = "",
    [string]$Pattern = "159873"
)

$ErrorActionPreference = "SilentlyContinue"
$coreDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = Split-Path -Parent $coreDir
$adb = Join-Path $rootDir "bin\scrcpy\adb.exe"

# 1. Resolve Target if empty
if ([string]::IsNullOrWhiteSpace($Target)) {
    $devLines = @(& $adb devices 2>$null | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of" })
    if ($devLines.Count -gt 0) {
        $firstLine = $devLines[0].Trim()
        $Target = ($firstLine -split "\s+")[0]
    }
}

if ([string]::IsNullOrWhiteSpace($Target)) {
    exit 1
}

$sFlag = @("-s", $Target)

# 2. Check if already unlocked
$policy = & $adb @sFlag shell dumpsys window policy 2>$null
$isShowing = ($policy | Select-String -Pattern "showing=true") -and (-not ($policy | Select-String -Pattern "mKeyguardUnlocked=\s*true"))

if (-not $isShowing) {
    # Already unlocked
    exit 0
}

# 3. Ensure unlock.sh is pushed to device
$localUnlockSh = Join-Path $coreDir "unlock.sh"
if (Test-Path $localUnlockSh) {
    & $adb @sFlag push $localUnlockSh /data/local/tmp/unlock.sh > $null 2>&1
    & $adb @sFlag shell chmod 755 /data/local/tmp/unlock.sh > $null 2>&1
}

# 4. Wake phone
& $adb @sFlag shell input keyevent 224
Start-Sleep -Milliseconds 150

# 5. Execute motion-event unlock routine
& $adb @sFlag shell "sh /data/local/tmp/unlock.sh" > $null 2>&1
Start-Sleep -Milliseconds 300

# 6. Check if unlocked
$policyAfter = & $adb @sFlag shell dumpsys window policy 2>$null
$stillLocked = ($policyAfter | Select-String -Pattern "showing=true") -and (-not ($policyAfter | Select-String -Pattern "mKeyguardUnlocked=\s*true"))

if ($stillLocked) {
    # Retry once
    & $adb @sFlag shell "sh /data/local/tmp/unlock.sh" > $null 2>&1
    Start-Sleep -Milliseconds 300
}

# 7. Bring Home screen to front
& $adb @sFlag shell input keyevent 3 > $null 2>&1
exit 0
