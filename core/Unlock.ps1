param(
    [string]$Target = "",
    [string]$Pattern = "",
    [string]$LockType = "",
    [string]$LockCode = ""
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
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith(";") -or $trimmed.StartsWith("#") -or [string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -match "^\[(.*)\]$") {
            $currentSection = $matches[1].Trim()
        } elseif ($currentSection -eq $section -and $trimmed -match "^([^=]+)=(.*)$") {
            if ($matches[1].Trim() -eq $key) {
                return $matches[2].Trim()
            }
        }
    }
    return $default
}

# Resolve settings from ini if not passed via param
if ([string]::IsNullOrWhiteSpace($LockType)) {
    $LockType = (Get-IniValue $iniFile "Security" "LockType" "pattern").ToLower()
}
if ([string]::IsNullOrWhiteSpace($LockCode)) {
    $LockCode = Get-IniValue $iniFile "Security" "LockCode" ""
}
if ([string]::IsNullOrWhiteSpace($Pattern)) {
    $Pattern = Get-IniValue $iniFile "Security" "Pattern" "159873"
}

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

# 3. Handle by LockType
switch ($LockType) {
    "none" {
        # Wake & dismiss swipe keyguard
        & $adb @sFlag shell input keyevent 224
        Start-Sleep -Milliseconds 150
        & $adb @sFlag shell input keyevent 82
        Start-Sleep -Milliseconds 250
    }
    { $_ -in "pin", "password" } {
        if (-not [string]::IsNullOrWhiteSpace($LockCode)) {
            & $adb @sFlag shell input keyevent 224
            Start-Sleep -Milliseconds 150
            & $adb @sFlag shell input keyevent 82
            Start-Sleep -Milliseconds 300
            & $adb @sFlag shell input text "$LockCode"
            Start-Sleep -Milliseconds 150
            & $adb @sFlag shell input keyevent 66
            Start-Sleep -Milliseconds 300
        }
    }
    default {
        # Pattern mode
        # Get screen size for proportional scaling across phone models
        $wmOut = & $adb @sFlag shell wm size 2>$null
        $scaleX = 1.0
        $scaleY = 1.0
        if ($wmOut -match "(\d+)x(\d+)") {
            $w = [double]$matches[1]
            $h = [double]$matches[2]
            $scaleX = $w / 1080.0
            $scaleY = $h / 2412.0
        }

        # 3x3 Pattern Dot Map scaled to device resolution
        $dotMap = @{
            '1' = @( [int](247 * $scaleX), [int](1163 * $scaleY) )
            '2' = @( [int](540 * $scaleX), [int](1163 * $scaleY) )
            '3' = @( [int](833 * $scaleX), [int](1163 * $scaleY) )
            '4' = @( [int](247 * $scaleX), [int](1456 * $scaleY) )
            '5' = @( [int](540 * $scaleX), [int](1456 * $scaleY) )
            '6' = @( [int](833 * $scaleX), [int](1456 * $scaleY) )
            '7' = @( [int](247 * $scaleX), [int](1750 * $scaleY) )
            '8' = @( [int](540 * $scaleX), [int](1750 * $scaleY) )
            '9' = @( [int](833 * $scaleX), [int](1750 * $scaleY) )
        }

        # Generate shell unlock script on the fly
        $scriptLines = @(
            "#!/system/bin/sh",
            "cmd input keyevent 224",
            "cmd input keyevent 82",
            "sleep 0.4"
        )

        $chars = $Pattern.ToCharArray()
        if ($chars.Length -gt 0 -and $dotMap.ContainsKey([string]$chars[0])) {
            $first = $dotMap[[string]$chars[0]]
            $scriptLines += "cmd input motionevent DOWN $($first[0]) $($first[1])"
            for ($i = 0; $i -lt ($chars.Length - 1); $i++) {
                $c1 = [string]$chars[$i]
                $c2 = [string]$chars[$i + 1]
                if ($dotMap.ContainsKey($c1) -and $dotMap.ContainsKey($c2)) {
                    $p1 = $dotMap[$c1]
                    $p2 = $dotMap[$c2]
                    for ($step = 1; $step -le 4; $step++) {
                        $ix = [int]($p1[0] + ($p2[0] - $p1[0]) * ($step / 4.0))
                        $iy = [int]($p1[1] + ($p2[1] - $p1[1]) * ($step / 4.0))
                        $scriptLines += "cmd input motionevent MOVE $ix $iy"
                    }
                }
            }
            $last = $dotMap[[string]$chars[$chars.Length - 1]]
            $scriptLines += "cmd input motionevent UP $($last[0]) $($last[1])"
        }

        # Write and push dynamic script
        $tempSh = Join-Path $env:TEMP "nothing_unlock.sh"
        [System.IO.File]::WriteAllText($tempSh, ($scriptLines -join "`n"), [System.Text.Encoding]::ASCII)
        & $adb @sFlag push $tempSh /data/local/tmp/unlock.sh > $null 2>&1
        & $adb @sFlag shell chmod 755 /data/local/tmp/unlock.sh > $null 2>&1
        Remove-Item $tempSh -Force -ErrorAction SilentlyContinue

        # Execute
        & $adb @sFlag shell "sh /data/local/tmp/unlock.sh" > $null 2>&1
        Start-Sleep -Milliseconds 300
    }
}

# 4. Check if unlocked, retry once if needed
$policyAfter = & $adb @sFlag shell dumpsys window policy 2>$null
$stillLocked = ($policyAfter | Select-String -Pattern "showing=true") -and (-not ($policyAfter | Select-String -Pattern "mKeyguardUnlocked=\s*true"))

if ($stillLocked) {
    if ($LockType -eq "pin" -or $LockType -eq "password") {
        & $adb @sFlag shell "input text '$LockCode'; input keyevent 66" > $null 2>&1
    } elseif ($LockType -eq "pattern") {
        & $adb @sFlag shell "sh /data/local/tmp/unlock.sh" > $null 2>&1
    }
    Start-Sleep -Milliseconds 300
}

# 5. Bring Home screen to front
& $adb @sFlag shell input keyevent 3 > $null 2>&1
exit 0
