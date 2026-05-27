# =========================
# Combined Autopilot Group Tag Update + Azure AD Group Assignment Script
# For Intune / Company Portal deployment
# =========================
param()

# =========================
# Configuration
# =========================
$TenantId     = "YOUR-TENANT-ID-HERE"
$ClientId     = "YOUR-CLIENT-ID-HERE"
$ClientSecret = "YOUR-CLIENT-SECRET-HERE"

# Department to Azure AD Group Mapping
# Format: "AGENCY_CODE" = "AGENCY_CODE-UninstallApps"
# Add or remove entries to match your organization's structure
$DepartmentGroups = @{
    "DEPT1"  = "DEPT1-UninstallApps"
    "DEPT2"  = "DEPT2-UninstallApps"
    "DEPT3"  = "DEPT3-UninstallApps"
    "DEPT4"  = "DEPT4-UninstallApps"
    "DEPT5"  = "DEPT5-UninstallApps"
    "TEST"   = "TEST-UninstallApps"
}

# Detection file path
$detectionPath = "C:\ProgramData\DepartmentMove\DetectionLogic"
if (-not (Test-Path $detectionPath)) {
    New-Item -Path $detectionPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# Log file - Use TEMP for user context, Windows\Logs for system context
$isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
if ($isSystem) {
    $logPath = "C:\Windows\Logs\Software"
} else {
    $logPath = "$env:TEMP"
}
$logFile = "$logPath\DepartmentMove.log"

# Create log directory if needed
if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# Logging function (wrapped in try/catch so logging never breaks execution)
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8 -Force
    } catch {
        Write-Output "$timestamp - $Message"
    }
}

Write-Log "========================================"
Write-Log "Autopilot Device Department Move"
Write-Log "========================================"

# =========================
# Wait for network connectivity
# =========================
Write-Log "Waiting for network connectivity..."
$networkReady = $false
$maxWaitTime = 300
$waitTime = 0

do {
    try {
        $testConnection = Test-NetConnection -ComputerName "login.microsoftonline.com" -Port 443 -InformationLevel Quiet -ErrorAction SilentlyContinue
        if ($testConnection) {
            $networkReady = $true
            Write-Log "Network connectivity confirmed"
        } else {
            Write-Log "Waiting for network... ($waitTime seconds elapsed)"
            Start-Sleep -Seconds 10
            $waitTime += 10
        }
    } catch {
        Write-Log "Network test failed, retrying... ($waitTime seconds elapsed)"
        Start-Sleep -Seconds 10
        $waitTime += 10
    }
} while (-not $networkReady -and $waitTime -lt $maxWaitTime)

if (-not $networkReady) {
    Write-Log "Network connectivity timeout. Cannot proceed with registration."
    exit 1
}

# =========================
# Get Device Information
# =========================
$serialNumber = (Get-CimInstance -Class Win32_BIOS).SerialNumber
$MachineName = $env:COMPUTERNAME
Write-Log "Device Serial: $serialNumber"
Write-Log "Machine Name: $MachineName"

# =========================
# Initialize WinForms
# =========================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================
# Create GUI Form
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Department Move"
$form.Size = New-Object System.Drawing.Size(600, 480)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 248, 255)
$form.TopMost = $true

# Header Panel
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Location = New-Object System.Drawing.Point(0, 0)
$headerPanel.Size = New-Object System.Drawing.Size(600, 70)
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$form.Controls.Add($headerPanel)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Location = New-Object System.Drawing.Point(20, 10)
$titleLabel.Size = New-Object System.Drawing.Size(550, 50)
$titleLabel.Text = "Department Move"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.TextAlign = "MiddleCenter"
$headerPanel.Controls.Add($titleLabel)

# Device Info Section
$deviceInfoLabel = New-Object System.Windows.Forms.Label
$deviceInfoLabel.Location = New-Object System.Drawing.Point(30, 85)
$deviceInfoLabel.Size = New-Object System.Drawing.Size(540, 25)
$deviceInfoLabel.Text = "Device Information"
$deviceInfoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$deviceInfoLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 51, 102)
$form.Controls.Add($deviceInfoLabel)

$serialLabel = New-Object System.Windows.Forms.Label
$serialLabel.Location = New-Object System.Drawing.Point(30, 115)
$serialLabel.Size = New-Object System.Drawing.Size(540, 25)
$serialLabel.Text = "Serial Number: $serialNumber"
$serialLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($serialLabel)

$machineLabel = New-Object System.Windows.Forms.Label
$machineLabel.Location = New-Object System.Drawing.Point(30, 140)
$machineLabel.Size = New-Object System.Drawing.Size(540, 25)
$machineLabel.Text = "Machine Name: $MachineName"
$machineLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($machineLabel)

# Separator
$separator1 = New-Object System.Windows.Forms.Panel
$separator1.Location = New-Object System.Drawing.Point(30, 175)
$separator1.Size = New-Object System.Drawing.Size(540, 2)
$separator1.BackColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$form.Controls.Add($separator1)

# Section 1: Autopilot Group Tag (destination department)
$autopilotLabel = New-Object System.Windows.Forms.Label
$autopilotLabel.Location = New-Object System.Drawing.Point(30, 190)
$autopilotLabel.Size = New-Object System.Drawing.Size(540, 25)
$autopilotLabel.Text = "Select the Department you want to move TO:"
$autopilotLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$autopilotLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$form.Controls.Add($autopilotLabel)

$autopilotDescLabel = New-Object System.Windows.Forms.Label
$autopilotDescLabel.Location = New-Object System.Drawing.Point(30, 215)
$autopilotDescLabel.Size = New-Object System.Drawing.Size(540, 20)
$autopilotDescLabel.Text = "This will update the Autopilot Group Tag"
$autopilotDescLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($autopilotDescLabel)

$autopilotDropdown = New-Object System.Windows.Forms.ComboBox
$autopilotDropdown.Location = New-Object System.Drawing.Point(30, 240)
$autopilotDropdown.Size = New-Object System.Drawing.Size(540, 30)
$autopilotDropdown.DropDownStyle = "DropDownList"
$autopilotDropdown.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$agencies = $DepartmentGroups.Keys | Sort-Object
$agencies | ForEach-Object { $autopilotDropdown.Items.Add($_) | Out-Null }
$autopilotDropdown.SelectedIndex = 0
$form.Controls.Add($autopilotDropdown)

# Separator
$separator2 = New-Object System.Windows.Forms.Panel
$separator2.Location = New-Object System.Drawing.Point(30, 280)
$separator2.Size = New-Object System.Drawing.Size(540, 2)
$separator2.BackColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$form.Controls.Add($separator2)

# Section 2: Azure AD Group (source department for uninstall group)
$groupLabel = New-Object System.Windows.Forms.Label
$groupLabel.Location = New-Object System.Drawing.Point(30, 295)
$groupLabel.Size = New-Object System.Drawing.Size(540, 25)
$groupLabel.Text = "Select the Department you want to move FROM:"
$groupLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$groupLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$form.Controls.Add($groupLabel)

$groupDescLabel = New-Object System.Windows.Forms.Label
$groupDescLabel.Location = New-Object System.Drawing.Point(30, 320)
$groupDescLabel.Size = New-Object System.Drawing.Size(540, 20)
$groupDescLabel.Text = "This will add the device to the selected department's Azure AD uninstall group"
$groupDescLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$groupDescLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
$form.Controls.Add($groupDescLabel)

$groupDropdown = New-Object System.Windows.Forms.ComboBox
$groupDropdown.Location = New-Object System.Drawing.Point(30, 345)
$groupDropdown.Size = New-Object System.Drawing.Size(540, 30)
$groupDropdown.DropDownStyle = "DropDownList"
$groupDropdown.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$groupDropdown.Items.AddRange(($DepartmentGroups.Keys | Sort-Object))
$groupDropdown.SelectedIndex = 0
$form.Controls.Add($groupDropdown)

# Confirm Button
$registerButton = New-Object System.Windows.Forms.Button
$registerButton.Location = New-Object System.Drawing.Point(350, 405)
$registerButton.Size = New-Object System.Drawing.Size(220, 40)
$registerButton.Text = "Confirm"
$registerButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$registerButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$registerButton.ForeColor = [System.Drawing.Color]::White
$registerButton.FlatStyle = "Flat"
$registerButton.FlatAppearance.BorderSize = 0
$registerButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.Controls.Add($registerButton)

# Cancel Button
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Location = New-Object System.Drawing.Point(30, 405)
$cancelButton.Size = New-Object System.Drawing.Size(100, 40)
$cancelButton.Text = "Cancel"
$cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$cancelButton.BackColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$cancelButton.FlatStyle = "Flat"
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancelButton)

# Show Form
$result = $form.ShowDialog()

if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Log "Operation cancelled by user"
    $form.Dispose()
    exit 1
}

$selectedDepartment      = $autopilotDropdown.SelectedItem
$selectedGroupDepartment = $groupDropdown.SelectedItem
$form.Dispose()

Write-Log "User selections:"
Write-Log "  Moving TO Department (Autopilot Group Tag): $selectedDepartment"
Write-Log "  Moving FROM Department (Azure AD Uninstall Group): $selectedGroupDepartment"

# =========================
# Authenticate with Microsoft Graph
# =========================
Write-Log "Authenticating with Microsoft Graph..."
$tokenBody = @{
    grant_type    = "client_credentials"
    scope         = "https://graph.microsoft.com/.default"
    client_id     = $ClientId
    client_secret = $ClientSecret
}

try {
    $tokenResponse = Invoke-RestMethod `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Method POST -Body $tokenBody `
        -ContentType "application/x-www-form-urlencoded" `
        -ErrorAction Stop

    $headers = @{
        Authorization  = "Bearer $($tokenResponse.access_token)"
        "Content-Type" = "application/json"
    }
    Write-Log "Authentication successful"
} catch {
    Write-Log "ERROR: Authentication failed: $_"
    [System.Windows.Forms.MessageBox]::Show(
        "Failed to authenticate with Microsoft Graph.`n`nError: $($_.Exception.Message)",
        "Authentication Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

# =========================
# STEP 1: Find and Update Autopilot Device
# =========================
Write-Log ""
Write-Log "STEP 1: Looking for device in Autopilot..."

try {
    $autopilotDeviceLookup = Invoke-RestMethod `
        -Headers $headers `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$serialNumber')" `
        -Method GET -ErrorAction Stop

    if ($autopilotDeviceLookup.value.Count -eq 0) {
        Write-Log "WARNING: Device not found in Autopilot registry"
        [System.Windows.Forms.MessageBox]::Show(
            "Device not found in Autopilot.`n`nThis device may need to be registered to Autopilot first.",
            "Device Not Found",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        exit 1
    }

    $AutopilotDeviceId = $autopilotDeviceLookup.value[0].id
    $currentGroupTag   = $autopilotDeviceLookup.value[0].groupTag
    Write-Log "Device found in Autopilot. Device ID: $AutopilotDeviceId"
    Write-Log "Current Group Tag: $currentGroupTag"

    Write-Log "Updating Autopilot Group Tag to: $selectedDepartment"
    $updateBody = @{ groupTag = $selectedDepartment } | ConvertTo-Json

    Invoke-RestMethod `
        -Headers $headers `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$AutopilotDeviceId/updateDeviceProperties" `
        -Method POST -Body $updateBody -ErrorAction Stop

    Write-Log "SUCCESS: Autopilot Group Tag updated to '$selectedDepartment'"

} catch {
    Write-Log "ERROR: Failed to update Autopilot: $_"
    [System.Windows.Forms.MessageBox]::Show(
        "Failed to update Autopilot Group Tag.`n`nError: $($_.Exception.Message)",
        "Autopilot Update Failed",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

# =========================
# STEP 2: Find Device in Azure AD
# =========================
Write-Log ""
Write-Log "STEP 2: Looking for device in Azure AD..."

Start-Sleep -Seconds 3

try {
    $azureADDeviceLookup = Invoke-RestMethod `
        -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$MachineName'" `
        -Method GET -ErrorAction Stop

    if ($azureADDeviceLookup.value.Count -eq 0) {
        Write-Log "WARNING: Device '$MachineName' not found in Azure AD"
        [System.Windows.Forms.MessageBox]::Show(
            "SUCCESS: Autopilot Group Tag updated!`n`nHowever, the device was not found in Azure AD yet. This is normal for new registrations.`n`nPlease wait 15-30 minutes for sync, then run this tool again.",
            "Partial Success",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning)

        $detectionContent = @"
Department Move Partially Completed
===================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Device: $MachineName
Serial Number: $serialNumber
Autopilot Group Tag Updated To: $selectedDepartment
Azure AD Group: Pending (Device not in Azure AD yet)
Status: Partial Success
"@
        $detectionContent | Out-File -FilePath "$detectionPath\DepartmentMove.txt" -Force
        Write-Log "Detection file created (partial success)"
        exit 0
    }

    $AzureADDeviceId = $azureADDeviceLookup.value[0].id
    Write-Log "Device found in Azure AD. Device ID: $AzureADDeviceId"

} catch {
    Write-Log "ERROR: Error finding device in Azure AD: $_"
    [System.Windows.Forms.MessageBox]::Show(
        "Autopilot updated successfully, but error looking up device in Azure AD.`n`nError: $($_.Exception.Message)",
        "Device Lookup Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    exit 0
}

# =========================
# STEP 3: Find Target Azure AD Group
# =========================
$TargetGroupName = $DepartmentGroups[$selectedGroupDepartment]
Write-Log "Looking for Azure AD group: $TargetGroupName"

try {
    $groupLookup = Invoke-RestMethod `
        -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$TargetGroupName'" `
        -Method GET -ErrorAction Stop

    if ($groupLookup.value.Count -eq 0) {
        Write-Log "ERROR: Group '$TargetGroupName' not found in Azure AD"
        [System.Windows.Forms.MessageBox]::Show(
            "Autopilot updated successfully, but Azure AD Group '$TargetGroupName' was not found.`n`nPlease ensure the group exists in Azure AD.",
            "Group Not Found",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        exit 0
    }

    $TargetGroupId = $groupLookup.value[0].id
    Write-Log "Group found. Group ID: $TargetGroupId"

} catch {
    Write-Log "ERROR: Error finding group: $_"
    [System.Windows.Forms.MessageBox]::Show(
        "Autopilot updated successfully, but error looking up Azure AD group.`n`nError: $($_.Exception.Message)",
        "Group Lookup Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    exit 0
}

# =========================
# STEP 4: Check if Device Already Member
# =========================
Write-Log "Checking if device is already a member of '$TargetGroupName'..."

try {
    $memberCheck = Invoke-RestMethod `
        -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/groups/$TargetGroupId/members?`$filter=id eq '$AzureADDeviceId'" `
        -Method GET -ErrorAction Stop

    if ($memberCheck.value.Count -gt 0) {
        Write-Log "Device is already a member of group '$TargetGroupName'"
        [System.Windows.Forms.MessageBox]::Show(
            "SUCCESS!`n`n✓ Autopilot Group Tag updated to: $selectedDepartment`n✓ Device already in Azure AD group: $TargetGroupName`n`nAll steps completed!",
            "Success",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)

        $detectionContent = @"
Department Move Completed Successfully
===================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Device: $MachineName
Serial Number: $serialNumber
Moved To Department: $selectedDepartment
Moved From Department: $selectedGroupDepartment
Autopilot Group Tag: $selectedDepartment
Azure AD Group: $TargetGroupName
Status: Success (Already Member)
"@
        $detectionContent | Out-File -FilePath "$detectionPath\DepartmentMove.txt" -Force
        Write-Log "Detection file created"
        exit 0
    }

} catch {
    Write-Log "WARNING: Could not check membership status: $_"
}

# =========================
# STEP 5: Add Device to Azure AD Group
# =========================
Write-Log "Adding device to Azure AD group '$TargetGroupName'..."

$AddBody = @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$AzureADDeviceId"
} | ConvertTo-Json

try {
    Invoke-RestMethod `
        -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/groups/$TargetGroupId/members/`$ref" `
        -Method POST -Body $AddBody -ErrorAction Stop

    Write-Log "SUCCESS: Device added to Azure AD group"
    [System.Windows.Forms.MessageBox]::Show(
        "COMPLETE!`n`n✓ Autopilot Group Tag updated to: $selectedDepartment`n✓ Device added to Azure AD group: $TargetGroupName`n`nDepartment move completed successfully!`n`nApps will deploy/uninstall within 30 minutes.",
        "Success",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)

    $detectionContent = @"
Department Move Completed Successfully
===================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Device: $MachineName
Serial Number: $serialNumber
Moved From Department: $selectedGroupDepartment
Moved To Department: $selectedDepartment
Autopilot Group Tag: $selectedDepartment
Azure AD Group: $TargetGroupName
Status: Success
"@
    $detectionContent | Out-File -FilePath "$detectionPath\DepartmentMove.txt" -Force
    Write-Log "Detection file created: $detectionPath\DepartmentMove.txt"

} catch {
    Write-Log "ERROR: Failed to add device to group: $_"
    [System.Windows.Forms.MessageBox]::Show(
        "Autopilot updated successfully, but failed to add device to Azure AD group.`n`nError: $($_.Exception.Message)`n`nPlease try running the tool again.",
        "Group Assignment Failed",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    exit 0
}

Write-Log ""
Write-Log "========================================"
Write-Log "Department Move Completed Successfully"
Write-Log "========================================"
Write-Log "Device: $MachineName"
Write-Log "Serial: $serialNumber"
Write-Log "Autopilot Group Tag: $selectedDepartment"
Write-Log "Azure AD Group: $TargetGroupName"
Write-Log "========================================"

exit 0
