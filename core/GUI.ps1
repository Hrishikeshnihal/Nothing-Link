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

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$coreDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = Split-Path -Parent $coreDir
$enginePs1 = Join-Path $coreDir "Engine.ps1"
$hotspotPs1 = Join-Path $coreDir "Hotspot.ps1"
$unlockPs1 = Join-Path $coreDir "Unlock.ps1"
$iniFile = Join-Path $rootDir "settings.ini"
$adb = Join-Path $rootDir "bin\scrcpy\adb.exe"

# --- Main Form Window ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Nothing Connect // Master Hub"
$form.Size = New-Object System.Drawing.Size(480, 600)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(13, 13, 18)
$form.ForeColor = [System.Drawing.Color]::White
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false

# --- Title Header ---
$titleLbl = New-Object System.Windows.Forms.Label
$titleLbl.Text = "NOTHING CONNECT"
$titleLbl.Font = New-Object System.Drawing.Font("Consolas", 15, [System.Drawing.FontStyle]::Bold)
$titleLbl.Location = New-Object System.Drawing.Point(32, 24)
$titleLbl.Size = New-Object System.Drawing.Size(400, 26)
$titleLbl.ForeColor = [System.Drawing.Color]::FromArgb(250, 250, 252)
$form.Controls.Add($titleLbl)

$subLbl = New-Object System.Windows.Forms.Label
$subLbl.Text = "Ultra-Low Latency • Screen Off • Hardware Mirror"
$subLbl.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$subLbl.Location = New-Object System.Drawing.Point(34, 52)
$subLbl.Size = New-Object System.Drawing.Size(400, 18)
$subLbl.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 165)
$form.Controls.Add($subLbl)

# --- Button Factory ---
function New-ActionCard($title, $subtitle, $y, $bgColor, $accentColor, [scriptblock]$action) {
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Location = New-Object System.Drawing.Point(32, $y)
    $pnl.Size = New-Object System.Drawing.Size(400, 64)
    $pnl.BackColor = $bgColor
    $pnl.Cursor = [System.Windows.Forms.Cursors]::Hand

    $accentBar = New-Object System.Windows.Forms.Panel
    $accentBar.Location = New-Object System.Drawing.Point(0, 0)
    $accentBar.Size = New-Object System.Drawing.Size(5, 64)
    $accentBar.BackColor = $accentColor
    $pnl.Controls.Add($accentBar)

    $tLbl = New-Object System.Windows.Forms.Label
    $tLbl.Text = $title
    $tLbl.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
    $tLbl.Location = New-Object System.Drawing.Point(18, 11)
    $tLbl.Size = New-Object System.Drawing.Size(370, 22)
    $tLbl.ForeColor = [System.Drawing.Color]::White
    $tLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
    $pnl.Controls.Add($tLbl)

    $sLbl = New-Object System.Windows.Forms.Label
    $sLbl.Text = $subtitle
    $sLbl.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $sLbl.Location = New-Object System.Drawing.Point(18, 33)
    $sLbl.Size = New-Object System.Drawing.Size(370, 18)
    $sLbl.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 175)
    $sLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
    $pnl.Controls.Add($sLbl)

    # Click Handlers
    $pnl.Add_Click($action)
    $tLbl.Add_Click($action)
    $sLbl.Add_Click($action)

    # Hover Effects
    $hoverColor = [System.Drawing.Color]::FromArgb([Math]::Min(255, $bgColor.R + 15), [Math]::Min(255, $bgColor.G + 15), [Math]::Min(255, $bgColor.B + 20))
    $pnl.Add_MouseEnter({ $pnl.BackColor = $hoverColor })
    $pnl.Add_MouseLeave({ $pnl.BackColor = $bgColor })
    $tLbl.Add_MouseEnter({ $pnl.BackColor = $hoverColor })
    $sLbl.Add_MouseEnter({ $pnl.BackColor = $hoverColor })

    $form.Controls.Add($pnl)
    return $pnl
}

# --- Action 1: Mirror Screen (Screen OFF) ---
New-ActionCard "MIRROR SCREEN (SCREEN OFF)" "Physical screen stays dark & cool • 120Hz LTPO • Auto-Unlock" 88 `
    ([System.Drawing.Color]::FromArgb(215, 25, 33)) ([System.Drawing.Color]::FromArgb(255, 100, 100)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$enginePs1`" -Mode ScreenOff"
}

# --- Action 2: Mirror Screen (Screen ON) ---
New-ActionCard "MIRROR SCREEN (SCREEN ON)" "Simultaneous display on both phone and PC • 60-120 FPS" 162 `
    ([System.Drawing.Color]::FromArgb(24, 24, 32)) ([System.Drawing.Color]::FromArgb(74, 222, 128)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$enginePs1`" -Mode ScreenOn"
}

# --- Action 3: Turn On Hotspot (Cross-Network 5G) ---
New-ActionCard "TURN ON PHONE HOTSPOT" "Trigger Wi-Fi hotspot over ADB" 236 `
    ([System.Drawing.Color]::FromArgb(24, 24, 32)) ([System.Drawing.Color]::FromArgb(56, 189, 248)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$hotspotPs1`""
}

# --- Action 4: Auto-Unlock Phone ---
New-ActionCard "REMOTE AUTO-UNLOCK PHONE" "Instant pattern vector unlock (159873) • Screen wake" 310 `
    ([System.Drawing.Color]::FromArgb(24, 24, 32)) ([System.Drawing.Color]::FromArgb(250, 204, 21)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$unlockPs1`""
}

# --- Action 5: Windows Phone Link ---
New-ActionCard "OPEN PHONE LINK" "Receive calls, SMS, WhatsApp notifications & OTPs" 384 `
    ([System.Drawing.Color]::FromArgb(24, 24, 32)) ([System.Drawing.Color]::FromArgb(168, 85, 247)) {
    Start-Process "ms-phone-link:"
}

# --- Footer Status Bar ---
$statusBox = New-Object System.Windows.Forms.Panel
$statusBox.Location = New-Object System.Drawing.Point(32, 468)
$statusBox.Size = New-Object System.Drawing.Size(400, 68)
$statusBox.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
$statusBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$statusBox.Cursor = [System.Windows.Forms.Cursors]::Hand

$statusDot = New-Object System.Windows.Forms.Label
$statusDot.Text = "●"
$statusDot.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$statusDot.Location = New-Object System.Drawing.Point(12, 12)
$statusDot.Size = New-Object System.Drawing.Size(20, 20)
$statusDot.ForeColor = [System.Drawing.Color]::FromArgb(250, 204, 21)
$statusBox.Controls.Add($statusDot)

$statusTitle = New-Object System.Windows.Forms.Label
$statusTitle.Text = "CHECKING CONNECTION..."
$statusTitle.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$statusTitle.Location = New-Object System.Drawing.Point(36, 14)
$statusTitle.Size = New-Object System.Drawing.Size(350, 18)
$statusTitle.ForeColor = [System.Drawing.Color]::FromArgb(250, 204, 21)
$statusBox.Controls.Add($statusTitle)

$statusDetails = New-Object System.Windows.Forms.Label
$statusDetails.Text = "Scanning USB, Hotspot & Wi-Fi..."
$statusDetails.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$statusDetails.Location = New-Object System.Drawing.Point(36, 36)
$statusDetails.Size = New-Object System.Drawing.Size(350, 20)
$statusDetails.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 175)
$statusBox.Controls.Add($statusDetails)

$form.Controls.Add($statusBox)

# Function to check connection live
function Update-ConnectionStatus {
    $devs = @(& $adb devices 2>$null | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of" })
    if ($devs.Count -gt 0) {
        $target = ($devs[0].Trim() -split "\s+")[0]
        $statusDot.ForeColor = [System.Drawing.Color]::FromArgb(74, 222, 128)
        $statusTitle.ForeColor = [System.Drawing.Color]::FromArgb(74, 222, 128)
        $statusTitle.Text = "PHONE CONNECTED // READY"
        $statusDetails.Text = "Device: $target • 120 FPS High-Speed Mode"
    } else {
        # Check if Hotspot gateway exists
        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
        if ($gw -and $gw -ne "192.168.1.1" -and $gw -ne "0.0.0.0") {
            $statusDot.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
            $statusTitle.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
            $statusTitle.Text = "HOTSPOT DETECTED ($gw)"
            $statusDetails.Text = "Click any card above to connect at 2ms wired speed"
        } else {
            $statusDot.ForeColor = [System.Drawing.Color]::FromArgb(248, 113, 113)
            $statusTitle.ForeColor = [System.Drawing.Color]::FromArgb(248, 113, 113)
            $statusTitle.Text = "PHONE NOT CONNECTED"
            $statusDetails.Text = "Plug in USB or connect PC to Phone Wi-Fi Hotspot"
        }
    }
}

$statusBox.Add_Click({ Update-ConnectionStatus })
$statusTitle.Add_Click({ Update-ConnectionStatus })
$statusDetails.Add_Click({ Update-ConnectionStatus })

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 2500
$pollTimer.Add_Tick({ Update-ConnectionStatus })
$pollTimer.Start()

$form.Add_Shown({ Update-ConnectionStatus })

[System.Windows.Forms.Application]::Run($form)
