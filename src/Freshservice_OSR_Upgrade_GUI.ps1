#Requires -Version 5.1
<#
.SYNOPSIS
Freshservice OSR Upgrade Manager - Windows Forms edition.
.DESCRIPTION
Generic operator-supervised GUI for in-place upgrades of the Freshservice
Orchestration Server. Uses an integrated recovery engine, no external rollback script.
The application requires an authorized, independently validated vendor downgrade
path for automated recovery and an authentic prior-version MSI.
No host/tenant/organization names are embedded in the program.
#>
param([string]$ResumeState = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
Import-Module (Join-Path $PSScriptRoot 'OSR.Upgrade.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'OSR.Recovery.WindowsServerBackup.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'OSR.Recovery.LabFiles.psm1') -Force
$script:GuiScriptPath = $PSCommandPath
$script:ApplicationTitle = 'Freshservice OSR Upgrade Manager - V3 Preview'
$script:RestoringSession = $false
$script:ElevationStarted = $false

$script:ChildProcess = $null
$script:CurrentRun = $null
$script:CurrentPrompt = $null
$script:LastLogLineCount = 0
$script:DryRunActive = $false
$script:DryRunIndex = 0
$script:DryRunStages = @()
$script:DryRunTests = @()
$script:DryRunStartedAt = $null
$script:UpgradeRunBase = Join-Path $env:ProgramData 'FreshworksOSRUpgradeManager\Runs'
$script:LabRunBase = Join-Path $env:SystemDrive 'OSRLab\Runs'
$script:RunBase = $script:UpgradeRunBase
$script:WorkerPath = Join-Path $PSScriptRoot 'OSR.Upgrade.Worker.ps1'

$form = New-Object Windows.Forms.Form
$form.Text = $script:ApplicationTitle
$form.Size = New-Object Drawing.Size(1030,868)
$form.MinimumSize = New-Object Drawing.Size(990,875)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI',9)
$form.BackColor = [Drawing.Color]::FromArgb(247,249,250)

function New-Label([string]$Text,[int]$X,[int]$Y,[int]$Width,[int]$Height) {
    $c = New-Object Windows.Forms.Label
    $c.Text=$Text; $c.Location=New-Object Drawing.Point($X,$Y)
    $c.Size=New-Object Drawing.Size($Width,$Height)
    return $c
}
function New-Button([string]$Text,[int]$X,[int]$Y,[int]$Width,[int]$Height) {
    $c = New-Object Windows.Forms.Button
    $c.Text=$Text; $c.Location=New-Object Drawing.Point($X,$Y)
    $c.Size=New-Object Drawing.Size($Width,$Height)
    return $c
}
function New-TextBox([int]$X,[int]$Y,[int]$Width,[int]$Height) {
    $c=New-Object Windows.Forms.TextBox
    $c.Location=New-Object Drawing.Point($X,$Y)
    $c.Size=New-Object Drawing.Size($Width,$Height)
    return $c
}
function Add-Row([string]$Label,[int]$Y,[string]$Variable,[bool]$Folder=$false) {
    $form.Controls.Add((New-Label $Label 25 $Y 246 24))
    $text=New-TextBox 270 ($Y-2) 590 26
    $browse=New-Button 'Browse...' 870 ($Y-3) 109 30
    $form.Controls.AddRange(@($text,$browse))
    Set-Variable -Name ('txt'+$Variable) -Value $text -Scope Script
    Set-Variable -Name ('btn'+$Variable) -Value $browse -Scope Script
    if ($Folder) {
        $browse.Add_Click({
            $d=New-Object Windows.Forms.FolderBrowserDialog
            $d.Description='Select a directory'
            $d.ShowNewFolderButton=$true
            if(Test-Path -LiteralPath $text.Text -PathType Container){$d.SelectedPath=$text.Text}
            if($d.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){$text.Text=$d.SelectedPath}
            $d.Dispose()
        }.GetNewClosure())
    } else {
        $browse.Add_Click({
            $d=New-Object Windows.Forms.OpenFileDialog
            $d.Title='Choose an official Freshworks MSI package'
            $d.Filter='Windows Installer package (*.msi)|*.msi'
            if($d.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){$text.Text=$d.FileName}
            $d.Dispose()
        }.GetNewClosure())
    }
}

$title=New-Label 'Freshservice OSR Upgrade Manager' 25 15 950 38
$title.Font=New-Object Drawing.Font('Segoe UI Semibold',19)
$title.ForeColor=[Drawing.Color]::FromArgb(18,87,71)
$form.Controls.Add($title)
$subtitle=New-Label 'Auto-discovery  |  Integrated recovery  |  Controlled deployment  |  Manual acceptance' 26 56 720 22
$subtitle.ForeColor=[Drawing.Color]::FromArgb(83,100,110)
$form.Controls.Add($subtitle)
$script:lblPrivilege=New-Label 'Checking Windows token...' 750 56 228 22
$script:lblPrivilege.TextAlign='MiddleRight'
$script:lblPrivilege.Font=New-Object Drawing.Font('Segoe UI Semibold',9)
$form.Controls.Add($script:lblPrivilege)

Add-Row 'New FO-OSR.msi' 104 'Msi'
Add-Row 'Recovery MSI (auto-detect)' 145 'Previous'
Add-Row 'Existing installation directory' 186 'Install' $true
Add-Row 'Recovery storage directory' 227 'RecoveryRoot' $true
$script:txtRecoveryRoot.Text = $script:RunBase
try { $script:txtInstall.Text = Get-OsrInstallDirectory }
catch { $script:txtInstall.Text = Join-Path $env:ProgramFiles 'Freshworks\Orchestration Server' }

$lblSHA = New-Label 'Approved SHA-256 (if MSI unsigned)' 25 270 250 23
$form.Controls.Add($lblSHA)
$script:txtSHA = New-TextBox 270 268 709 25
$form.Controls.Add($script:txtSHA)

$lblPrevSHA=New-Label 'Recovery MSI SHA-256 (if unsigned)' 25 303 250 24
$form.Controls.Add($lblPrevSHA)
$script:txtPreviousSHA=New-TextBox 270 301 709 25
$form.Controls.Add($script:txtPreviousSHA)
# Automatically locate an original older MSI without requiring a manual download.
$script:txtPrevious.Width=498
$script:btnAutoFind=New-Button 'Auto-find' 777 141 82 30
$form.Controls.Add($script:btnAutoFind)

$lblMandatory=New-Label 'Required functional test' 25 343 246 24
$form.Controls.Add($lblMandatory)
$script:txtMandatory=New-TextBox 270 341 709 26
$script:txtMandatory.Text='Does a native Freshservice orchestration action succeed on a known-working target?'
$form.Controls.Add($script:txtMandatory)
$lblMore=New-Label 'Additional tests (one per line)' 25 378 250 25
$form.Controls.Add($lblMore)
$script:txtMore=New-TextBox 270 377 709 64
$script:txtMore.Multiline=$true
$script:txtMore.ScrollBars='Vertical'
$form.Controls.Add($script:txtMore)

$script:chkDryRun=New-Object Windows.Forms.CheckBox
$script:chkDryRun.Text='DRY RUN - Simulate the complete workflow (no system changes; logs in memory only)'
$script:chkDryRun.Location=New-Object Drawing.Point(26,447)
$script:chkDryRun.Size=New-Object Drawing.Size(940,25)
$script:chkDryRun.Checked=$true
$script:chkDryRun.Font=New-Object Drawing.Font('Segoe UI Semibold',10)
$script:chkDryRun.ForeColor=[Drawing.Color]::FromArgb(17,100,87)
$form.Controls.Add($script:chkDryRun)

$script:chkApproval=New-Object Windows.Forms.CheckBox
$script:chkApproval.Text='I confirm the approved maintenance window and authorized production change.'
$script:chkApproval.Location=New-Object Drawing.Point(26,479)
$script:chkApproval.Size=New-Object Drawing.Size(940,24)
$form.Controls.Add($script:chkApproval)
$script:chkRecovery=New-Object Windows.Forms.CheckBox
$script:chkRecovery.Text='I confirm the downgrade/recovery procedure for these OSR versions was independently tested.'
$script:chkRecovery.Location=New-Object Drawing.Point(26,505)
$script:chkRecovery.Size=New-Object Drawing.Size(940,24)
$form.Controls.Add($script:chkRecovery)

$script:btnPreflight=New-Button 'Read-only preflight' 25 549 210 38
$script:btnStart=New-Button 'Start dry run' 244 549 210 38
$script:btnLogs=New-Button 'Open run folder' 463 549 163 38
$script:btnBackupCheck=New-Button 'Check Windows backup' 637 549 205 38
$form.Controls.AddRange(@($script:btnPreflight,$script:btnStart,$script:btnLogs,$script:btnBackupCheck))

$script:lblMode=New-Label 'DRY RUN ACTIVE: only read-only discovery; upgrade, backups and recovery are SIMULATED.' 25 593 965 24
$script:lblMode.ForeColor=[Drawing.Color]::FromArgb(19,111,85)
$form.Controls.Add($script:lblMode)
$script:lblStatus=New-Label 'Ready. Dry Run is enabled by default.' 25 620 955 26
$form.Controls.Add($script:lblStatus)
$script:progress=New-Object Windows.Forms.ProgressBar
$script:progress.Location=New-Object Drawing.Point(25,650)
$script:progress.Size=New-Object Drawing.Size(954,17)
$script:progress.Style='Continuous'
$form.Controls.Add($script:progress)
$script:lstLog=New-Object Windows.Forms.ListBox
$script:lstLog.Location=New-Object Drawing.Point(25,683)
$script:lstLog.Size=New-Object Drawing.Size(954,128)
$script:lstLog.HorizontalScrollbar=$true
$script:lstLog.SelectionMode='MultiExtended'
$script:lstLog.IntegralHeight=$false
$script:lstLog.Font=New-Object Drawing.Font('Consolas',9)
$form.Controls.Add($script:lstLog)

# Leave room for an explicit operation selector without overlapping existing rows.
foreach ($control in $form.Controls) {
    if ($control.Top -ge 90) { $control.Top += 40 }
}
$form.Size = New-Object Drawing.Size(1030,930)
$form.MinimumSize = New-Object Drawing.Size(990,875)
$form.AutoScroll = $true
$form.Controls.Add((New-Label 'Operation' 25 88 240 24))
$script:cboOperation = New-Object Windows.Forms.ComboBox
$script:cboOperation.DropDownStyle = 'DropDownList'
$script:cboOperation.Location = New-Object Drawing.Point(270,85)
$script:cboOperation.Size = New-Object Drawing.Size(248,26)
[void]$script:cboOperation.Items.Add('Upgrade')
[void]$script:cboOperation.Items.Add('Lab Repair (same version)')
$script:cboOperation.SelectedIndex = 0
$form.Controls.Add($script:cboOperation)
$script:lblLabComputer = New-Label 'Lab guest computer name' 535 88 195 24
$script:txtLabComputer = New-TextBox 740 85 239 26
$form.Controls.AddRange(@($script:lblLabComputer,$script:txtLabComputer))

# Stretch input rows horizontally and give additional vertical space to logs.
$form.Size = New-Object Drawing.Size(1030,970)
foreach ($control in $form.Controls) {
    if ($control -is [Windows.Forms.TextBox] -or $control -is [Windows.Forms.CheckBox]) {
        $control.Anchor = 'Top, Left, Right'
    }
}
foreach ($control in @($script:btnMsi,$script:btnPrevious,$script:btnInstall,$script:btnRecoveryRoot,$script:btnAutoFind,$script:lblPrivilege)) {
    $control.Anchor = 'Top, Right'
}
foreach ($control in @($title,$subtitle,$script:lblMode,$script:lblStatus,$script:progress)) {
    $control.Anchor = 'Top, Left, Right'
}
$script:logPanel = New-Object Windows.Forms.Panel
$script:logPanel.Location = New-Object Drawing.Point(25,723)
$script:logPanel.Size = New-Object Drawing.Size(954,168)
$script:logPanel.Anchor = 'Top, Bottom, Left, Right'
$form.Controls.Add($script:logPanel)
$script:lstLog.Dock = 'Fill'
$script:logPanel.Controls.Add($script:lstLog)
$script:logToolbar = New-Object Windows.Forms.ToolStrip
$script:logToolbar.GripStyle = 'Hidden'
$script:logToolbar.Dock = 'Top'
$script:btnCopySelectedLogs = New-Object Windows.Forms.ToolStripButton('Copy selected')
$script:btnCopyAllLogs = New-Object Windows.Forms.ToolStripButton('Copy all logs')
$script:lblLogCopy = New-Object Windows.Forms.ToolStripLabel('Ctrl+C: copy selected | Ctrl+A: select all')
[void]$script:logToolbar.Items.Add($script:btnCopySelectedLogs)
[void]$script:logToolbar.Items.Add($script:btnCopyAllLogs)
[void]$script:logToolbar.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
[void]$script:logToolbar.Items.Add($script:lblLogCopy)
$script:logPanel.Controls.Add($script:logToolbar)
$script:lstLog.BringToFront()

function Get-GuiLogText([switch]$SelectedOnly) {
    $lines = if ($SelectedOnly) { @($script:lstLog.SelectedItems) } else { @($script:lstLog.Items) }
    return (($lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
}
function Set-GuiClipboardText([string]$Text) {
    [Windows.Forms.Clipboard]::SetText($Text,[Windows.Forms.TextDataFormat]::UnicodeText)
}
function Copy-GuiLog([switch]$SelectedOnly) {
    $text = Get-GuiLogText -SelectedOnly:$SelectedOnly
    if ([string]::IsNullOrEmpty($text)) {
        $script:lblLogCopy.Text = 'No log lines to copy.'
        return
    }
    try {
        Set-GuiClipboardText -Text $text
        $script:lblLogCopy.Text = 'Copied to clipboard. Ctrl+A selects all log lines.'
    } catch {
        $script:lblLogCopy.Text = 'Clipboard unavailable. Try copying again.'
    }
}
function Select-AllGuiLogs {
    $script:lstLog.BeginUpdate()
    try {
        for ($index=0; $index -lt $script:lstLog.Items.Count; $index++) {
            $script:lstLog.SetSelected($index,$true)
        }
    } finally { $script:lstLog.EndUpdate() }
}
$script:btnCopySelectedLogs.Add_Click({ Copy-GuiLog -SelectedOnly })
$script:btnCopyAllLogs.Add_Click({ Copy-GuiLog })
$script:lstLog.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq [Windows.Forms.Keys]::C) {
        Copy-GuiLog -SelectedOnly
        $_.SuppressKeyPress=$true
    } elseif ($_.Control -and $_.KeyCode -eq [Windows.Forms.Keys]::A) {
        Select-AllGuiLogs
        $_.SuppressKeyPress=$true
    }
})
$script:logMenu = New-Object Windows.Forms.ContextMenuStrip
$copySelectedMenu = $script:logMenu.Items.Add('Copy selected (Ctrl+C)')
$copySelectedMenu.Add_Click({ Copy-GuiLog -SelectedOnly })
$copyAllMenu = $script:logMenu.Items.Add('Copy all logs')
$copyAllMenu.Add_Click({ Copy-GuiLog })
$selectAllMenu = $script:logMenu.Items.Add('Select all (Ctrl+A)')
$selectAllMenu.Add_Click({ Select-AllGuiLogs })
$script:lstLog.ContextMenuStrip=$script:logMenu

function Get-GuiOperation {
    if ($script:cboOperation.SelectedIndex -eq 0) { return 'Upgrade' }
    if ($script:cboOperation.SelectedIndex -eq 1) { return 'LabRepair' }
    throw 'Select a supported operation.'
}

function Set-GuiBusy([bool]$Busy) {
    foreach ($control in @($script:txtMsi,$script:txtPrevious,$script:txtInstall,
        $script:txtRecoveryRoot,$script:txtSHA,$script:txtPreviousSHA,
        $script:txtMandatory,$script:txtMore,$script:chkDryRun,$script:chkApproval,$script:chkRecovery,
        $script:btnMsi,$script:btnPrevious,$script:btnInstall,$script:btnRecoveryRoot,
        $script:btnPreflight,$script:btnStart,$script:btnAutoFind,$script:btnBackupCheck,
        $script:cboOperation,$script:txtLabComputer)) { $control.Enabled = -not $Busy }
}
function Get-Questions {
    $q=@()
    if([string]::IsNullOrWhiteSpace($script:txtMandatory.Text)){throw 'A required functional test is mandatory.'}
    $q += $script:txtMandatory.Text.Trim()
    $q += @($script:txtMore.Lines | ForEach-Object {$_.Trim()} | Where-Object { $_ })
    return ,$q
}
function Get-GuiWindowsBackupAssessment {
    # Read-only inventory: this function does not run wbadmin or change a backup configuration.
    $cap = Get-OsrWindowsBackupCapability -InstallDirectory $script:txtInstall.Text.Trim()
    [void]$script:lstLog.Items.Add('[READ ONLY] Windows backup provider: '+$cap.Status+' | Feature: '+$cap.WindowsFeature)
    [void]$script:lstLog.Items.Add('[READ ONLY] OSR volume: '+$cap.OsrDrive+' | Windows volume: '+$cap.SystemDrive)
    if($cap.CandidateTargetCount -eq 0) {
        [void]$script:lstLog.Items.Add('[READ ONLY] No separate candidate fixed-volume backup target detected. A network share may be an option.')
    } else {
        foreach($candidate in @($cap.CandidateTargets)) {
            $freeGb=[Math]::Round(([double]$candidate.FreeBytes/1GB),1)
            [void]$script:lstLog.Items.Add('[READ ONLY] Candidate volume: '+$candidate.Drive+' | free: '+$freeGb+' GB | NOT VERIFIED')
        }
    }
    [void]$script:lstLog.Items.Add('[READ ONLY] Full-system recovery requires WinRE or an independently operating recovery controller.')
    $script:lstLog.TopIndex=[Math]::Max(0,$script:lstLog.Items.Count-1)
    return $cap
}

function Find-RecoveryInstallerInGui {
    if ((Get-GuiOperation) -eq 'LabRepair') {
        $installed = Get-OsrProduct
        $package = Get-OsrMsiMetadata -Path $script:txtMsi.Text.Trim()
        $evidence = Assert-OsrPackageAuthenticity -Path $package.Path -ExpectedSha256 $script:txtSHA.Text.Trim()
        Assert-OsrSameVersionRepair -InstalledProduct $installed -Package $package
        $script:txtPrevious.Text = $package.Path
        $script:lblStatus.Text = 'Lab repair uses the verified original MSI for the installed version. Restoration remains unverified.'
        return [pscustomobject]@{Found=$true;Verified=$true;Path=$package.Path;Verification=$evidence.Signature}
    }
    $app=$null
    try {$app=Get-OsrProduct}
    catch {throw ('Cannot detect installed Orchestration Server: '+$_.Exception.Message)}
    $roots=$script:txtRecoveryRoot.Text.Trim()
    $candidate=Find-OsrPreviousMsi -InstalledVersion $app.Version -UpgradeMsiPath $script:txtMsi.Text.Trim() -RecoveryRoot $roots -ExpectedSha256 $script:txtPreviousSHA.Text.Trim() -PreferredPath $script:txtPrevious.Text.Trim()
    if($candidate.Found){
        $script:txtPrevious.Text=$candidate.Path
        $script:lblStatus.Text=if($candidate.Verified){
            'Recovery installer auto-detected and verified: '+$candidate.Version
        }else{
            'Recovery installer discovered but NOT VERIFIED. Use an independently approved checksum.'
        }
        [void]$script:lstLog.Items.Add('[READ ONLY] Recovery MSI: '+$candidate.Path+' | '+$candidate.Verification)
    }else{
        $script:lblStatus.Text='Recovery MSI not found automatically. Live upgrade requires a validated recovery method.'
        [void]$script:lstLog.Items.Add('[READ ONLY] No complete previous-version MSI discovered in approved local locations.')
    }
    $environment=Get-OsrRecoveryEnvironment
    [void]$script:lstLog.Items.Add('[READ ONLY] Platform: '+$environment.Machine)
    [void]$script:lstLog.Items.Add('[READ ONLY] '+$environment.WindowsBackup)
    [void]$script:lstLog.Items.Add('[READ ONLY] '+$environment.Message)
    try { [void](Get-GuiWindowsBackupAssessment) }
    catch { [void]$script:lstLog.Items.Add('[READ ONLY] Windows Backup assessment unavailable: '+$_.Exception.Message) }
    $script:lstLog.TopIndex=[Math]::Max(0,$script:lstLog.Items.Count-1)
    return $candidate
}
function Protect-RunDirectory([string]$Path) {
    $security = New-Object System.Security.AccessControl.DirectorySecurity
    $security.SetAccessRuleProtection($true,$false)
    foreach($sidValue in @('S-1-5-32-544','S-1-5-18')) {
        $identity = New-Object System.Security.Principal.SecurityIdentifier($sidValue)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity, [Security.AccessControl.FileSystemRights]::FullControl,
            ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        [void]$security.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $security
}
function Export-GuiResumeState {
    # Data is transferred in the launch arguments; no temporary file is written.
    # Do not add credentials, backup secrets, or tokens to this payload.
    $state = @{
        FormatVersion = 1
        Operation = Get-GuiOperation
        LabExpectedComputerName = [string]$script:txtLabComputer.Text
        NewMsi = [string]$script:txtMsi.Text
        PreviousMsi = [string]$script:txtPrevious.Text
        InstallationDirectory = [string]$script:txtInstall.Text
        RecoveryStorage = [string]$script:txtRecoveryRoot.Text
        NewMsiSha256 = [string]$script:txtSHA.Text
        PreviousMsiSha256 = [string]$script:txtPreviousSHA.Text
        MandatoryTest = [string]$script:txtMandatory.Text
        AdditionalTests = [string]$script:txtMore.Text
        MaintenanceApproved = [bool]$script:chkApproval.Checked
        RecoveryValidated = [bool]$script:chkRecovery.Checked
    }
    $json = $state | ConvertTo-Json -Compress -Depth 3
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    if ($encoded.Length -gt 16000) {
        throw 'The current settings are too large to transfer during elevation. Shorten the optional test descriptions.'
    }
    return $encoded
}
function Restore-GuiResumeState([string]$EncodedState) {
    if ([string]::IsNullOrWhiteSpace($EncodedState)) { return }
    if (-not (Test-OsrAdministrator)) {
        throw 'Administrator elevation did not succeed. Live mode is blocked.'
    }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($EncodedState))
    $state = $json | ConvertFrom-Json -ErrorAction Stop
    if ([int]$state.FormatVersion -ne 1) { throw 'Unsupported elevation state format.' }
    $script:RestoringSession = $true
    try {
        $operation = [string]$state.Operation
        if ($operation -notin @('','Upgrade','LabRepair')) { throw 'Unsupported operation in elevation state.' }
        $script:cboOperation.SelectedIndex = if ($operation -eq 'LabRepair') { 1 } else { 0 }
        $script:txtLabComputer.Text = [string]$state.LabExpectedComputerName
        $script:txtMsi.Text = [string]$state.NewMsi
        $script:txtPrevious.Text = [string]$state.PreviousMsi
        $script:txtInstall.Text = [string]$state.InstallationDirectory
        $script:txtRecoveryRoot.Text = [string]$state.RecoveryStorage
        $script:txtSHA.Text = [string]$state.NewMsiSha256
        $script:txtPreviousSHA.Text = [string]$state.PreviousMsiSha256
        $script:txtMandatory.Text = [string]$state.MandatoryTest
        $script:txtMore.Text = [string]$state.AdditionalTests
        $script:chkApproval.Checked = [bool]$state.MaintenanceApproved
        $script:chkRecovery.Checked = [bool]$state.RecoveryValidated
        $script:chkDryRun.Checked = $false
        $form.Text = $script:ApplicationTitle + ' [Administrator]'
        $script:lblStatus.Text = 'Administrator privileges confirmed. Live mode is available.'
    } finally {
        $script:RestoringSession = $false
    }
}
function Request-GuiElevation {
    if (Test-OsrAdministrator) { return $true }
    $payload = Export-GuiResumeState
    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    $args = '-NoProfile -STA -ExecutionPolicy RemoteSigned -File "{0}" -ResumeState "{1}"' -f $script:GuiScriptPath,$payload
    try {
        $elevated = Start-Process -FilePath $powershellExe -ArgumentList $args -Verb RunAs -PassThru -ErrorAction Stop
        if (-not $elevated) { throw 'Windows did not return an elevated process.' }
        $script:ElevationStarted = $true
        $form.Close()
        return $false
    } catch {
        [void][Windows.Forms.MessageBox]::Show($form,
            'Administrator approval was cancelled or unavailable. Dry Run remains enabled. No live operation was started.' +
            [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message,
            'Administrator privileges required',
            [Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)
        return $false
    }
}
function Get-GuiRunConfiguration([object[]]$Questions) {
    $lab = (Get-GuiOperation) -eq 'LabRepair'
    return @{
        MsiPath=$script:txtMsi.Text.Trim()
        PreviousMsiPath=$script:txtPrevious.Text.Trim()
        InstallDirectory=$script:txtInstall.Text.Trim()
        BackupRoot=$script:RunBase
        ExpectedSha256=$script:txtSHA.Text.Trim()
        PreviousSha256=$script:txtPreviousSHA.Text.Trim()
        Questions=$Questions
        MaintenanceApproved=[bool]$script:chkApproval.Checked
        RecoveryProcedureValidated=((-not $lab) -and [bool]$script:chkRecovery.Checked)
        LabCheckpointConfirmed=($lab -and [bool]$script:chkRecovery.Checked)
        LabExpectedComputerName=$script:txtLabComputer.Text.Trim()
    }
}
function New-Run([string]$Mode) {
    if ($script:chkDryRun.Checked) { throw 'Dry Run is active; deployment worker is disabled.' }
    if (-not (Test-OsrAdministrator)) { throw 'Live operations require an elevated Administrator session.' }
    if($script:ChildProcess -and -not $script:ChildProcess.HasExited){throw 'Another run is already active.'}
    if(-not (Test-Path -LiteralPath $script:WorkerPath)){throw 'Worker script missing.'}
    $questions=Get-Questions
    $operation = Get-GuiOperation
    $lab = $operation -eq 'LabRepair'
    if ($lab) {
        Assert-OsrLabEnvironment -ExpectedComputerName $script:txtLabComputer.Text.Trim() -System (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop)
        if (-not $script:chkRecovery.Checked) { throw 'Confirm the current host-side baseline checkpoint for this dedicated lab guest.' }
    }
    if($Mode -eq 'Deploy') {
        if(-not $script:chkApproval.Checked){throw 'Confirm the approved maintenance window.'}
        if(-not $lab -and -not $script:chkRecovery.Checked){throw 'Confirm independently validated downgrade and restoration.'}
    }
    $script:RunBase = [IO.Path]::GetFullPath($script:txtRecoveryRoot.Text.Trim())
    $runName=('Run-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8)))
    $script:CurrentRun=Join-Path $script:RunBase $runName
    if ($lab) { Assert-OsrLabPaths -Source $script:txtInstall.Text.Trim() -Destination $script:CurrentRun }
    [void](New-Item -Path $script:CurrentRun -ItemType Directory -Force)
    Protect-RunDirectory $script:CurrentRun
    $cfg=Get-GuiRunConfiguration -Questions $questions
    $configPath=Join-Path $script:CurrentRun 'settings.json'
    [IO.File]::WriteAllText($configPath,($cfg | ConvertTo-Json -Depth 5),[Text.Encoding]::UTF8)
    $script:CurrentPrompt=$null
    $script:LastLogLineCount=0
    $script:lstLog.Items.Clear()
    $script:progress.Value=0
    $script:lblStatus.Text="Starting $Mode..."
    Set-GuiBusy $true
    $powershellExe=Join-Path $PSHOME 'powershell.exe'
    $arg='-NoProfile -ExecutionPolicy RemoteSigned -File "{0}" -Mode {1} -RunDirectory "{2}" -ConfigurationPath "{3}" -Operation {4}' -f `
        $script:WorkerPath,$Mode,$script:CurrentRun,$configPath,$operation
    $pi=New-Object Diagnostics.ProcessStartInfo
    $pi.FileName=$powershellExe
    $pi.Arguments=$arg
    $pi.UseShellExecute=$false
    $pi.CreateNoWindow=$true
    $script:ChildProcess=[Diagnostics.Process]::Start($pi)
    $script:poll.Start()
}
function Send-Answer([string]$Answer,[string]$PromptId) {
    if(-not $script:CurrentRun){return}
    $response=Join-Path $script:CurrentRun 'response.json'
    $tmp="$response.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($tmp,(@{PromptId=$PromptId;Answer=$Answer} | ConvertTo-Json),[Text.Encoding]::UTF8)
    if(Test-Path -LiteralPath $response){Remove-Item -LiteralPath $response -Force}
    [IO.File]::Move($tmp,$response)
}
function Refresh-Run {
    if(-not $script:CurrentRun){return}
    $log=Join-Path $script:CurrentRun 'activity.log'
    if(Test-Path -LiteralPath $log){
        try{
            $lines=@(Get-Content -LiteralPath $log -ErrorAction Stop)
            if($lines.Count -gt $script:LastLogLineCount){
                for($i=$script:LastLogLineCount;$i -lt $lines.Count;$i++){
                    [void]$script:lstLog.Items.Add($lines[$i])
                }
                $script:LastLogLineCount=$lines.Count
                $script:lstLog.TopIndex=[Math]::Max(0,$script:lstLog.Items.Count-1)
            }
        }catch{}
    }
    $path=Join-Path $script:CurrentRun 'state.json'
    if(Test-Path -LiteralPath $path){
        try{
            $state=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $script:lblStatus.Text="$($state.Stage): $($state.Message -replace '[\r\n]+',' ')"
            $script:progress.Value=[Math]::Max(0,[Math]::Min(100,[int]$state.Percent))
            if($state.Kind -eq 'PROMPT' -and $script:CurrentPrompt -ne [string]$state.PromptId){
                $script:CurrentPrompt=[string]$state.PromptId
                $buttons=[Windows.Forms.MessageBoxButtons]::YesNoCancel
                $answer=[Windows.Forms.MessageBox]::Show($form,[string]$state.Message,
                    'Functional validation / rollback decision',$buttons,[Windows.Forms.MessageBoxIcon]::Question)
                $value=switch($answer){
                    ([Windows.Forms.DialogResult]::Yes){'YES';break}
                    ([Windows.Forms.DialogResult]::No){'NO';break}
                    default {'CANCEL'}
                }
                Send-Answer $value $script:CurrentPrompt
            }
        }catch{}
    }
    if($script:ChildProcess -and $script:ChildProcess.HasExited){
        $script:poll.Stop()
        Refresh-RunLog
        Set-GuiBusy $false
        $report=Join-Path $script:CurrentRun 'report.json'
        if(Test-Path -LiteralPath $report){
            try{
                $r=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
                $script:lblStatus.Text="Finished: $($r.Status). Review local execution report."
            }catch{$script:lblStatus.Text='Worker ended. Review local logs.'}
        }else{$script:lblStatus.Text='Worker ended without report. Review local logs.'}
    }
}
function Refresh-RunLog {
    $log=Join-Path $script:CurrentRun 'activity.log'
    if(-not (Test-Path -LiteralPath $log)){return}
    $lines=@(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue)
    if($lines.Count -gt $script:LastLogLineCount){
        for($i=$script:LastLogLineCount;$i -lt $lines.Count;$i++){[void]$script:lstLog.Items.Add($lines[$i])}
        $script:LastLogLineCount=$lines.Count
        if($script:lstLog.Items.Count){$script:lstLog.TopIndex=$script:lstLog.Items.Count-1}
    }
}
# In-memory DRY RUN: no subprocess, directory creation, log file, registry writes,
# service control, MSI invocation or recovery operations. Read-only inspection is optional.
function Add-DryRunLog([string]$Message) {
    [void]$script:lstLog.Items.Add(('[{0}] [DRY RUN] {1}' -f (Get-Date -Format 'HH:mm:ss'),$Message))
    $script:lstLog.TopIndex=[Math]::Max(0,$script:lstLog.Items.Count-1)
}
function Show-DryRunProgress([string]$Stage,[string]$Message,[int]$Percent) {
    $script:lblStatus.Text='DRY RUN | '+$Stage+': '+$Message
    $script:progress.Value=[Math]::Max(0,[Math]::Min(100,$Percent))
    Add-DryRunLog ($Stage+' | '+$Message)
}
function Inspect-DryRunReadOnly {
    Add-DryRunLog 'Read-only environment inspection started. Missing inputs do not block the simulation.'
    try {
        if(Test-OsrAdministrator){Add-DryRunLog 'Admin token: elevated.'}
        else {Add-DryRunLog 'NOTICE: not elevated; a live upgrade will require Administrator privileges.'}
    } catch {Add-DryRunLog ('NOTICE: privilege check unavailable: '+$_.Exception.Message)}
    $installed=$null
    try {
        $installed=Get-OsrProduct
        Add-DryRunLog ('Detected installed OSR version: '+$installed.Version)
    } catch {Add-DryRunLog ('NOTICE: OSR installation could not be detected: '+$_.Exception.Message)}
    try {
        $actual=Get-OsrInstallDirectory
        Add-DryRunLog ('Detected directory: '+$actual)
        if($script:txtInstall.Text.Trim()) {
            if(([IO.Path]::GetFullPath($actual)).TrimEnd('\') -ine ([IO.Path]::GetFullPath($script:txtInstall.Text.Trim())).TrimEnd('\')) {
                Add-DryRunLog 'NOTICE: selected installation directory differs from the detected location.'
            }
        }
    } catch {Add-DryRunLog ('NOTICE: directory check unavailable: '+$_.Exception.Message)}
    try {
        foreach($svc in @(Get-OsrServiceRecords)) {
            Add-DryRunLog ('READ ONLY: '+$svc.DisplayName+' is '+$svc.State+' (no service control performed).')
        }
    } catch {Add-DryRunLog ('NOTICE: service query unavailable: '+$_.Exception.Message)}
    foreach($item in @(
        @{Name='New installer';Path=$script:txtMsi.Text.Trim()},
        @{Name='Previous installer';Path=$script:txtPrevious.Text.Trim()}
    )) {
        if (-not $item.Path) { Add-DryRunLog ('NOTICE: '+$item.Name+' was not selected.'); continue }
        if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) {
            Add-DryRunLog ('NOTICE: '+$item.Name+' not found: '+$item.Path); continue
        }
        try {
            $msi=Get-OsrMsiMetadata -Path $item.Path
            Add-DryRunLog ($item.Name+' | '+$msi.Version+' | SHA-256: '+$msi.Sha256)
            if($installed -and $item.Name -eq 'New installer'){
                if ((Get-GuiOperation) -eq 'LabRepair') {
                    Assert-OsrSameVersionRepair -InstalledProduct $installed -Package $msi
                    Add-DryRunLog 'Lab repair MSI matches the installed version and ProductCode.'
                } elseif ($msi.Version -le $installed.Version) {
                    Add-DryRunLog 'NOTICE: selected new installer is not newer than installed OSR.'
                }
            }
            if($installed -and $item.Name -eq 'Previous installer' -and $msi.Version -ne $installed.Version){
                Add-DryRunLog 'NOTICE: previous installer version differs from installed OSR.'
            }
        } catch {Add-DryRunLog ('NOTICE: MSI metadata inspection failed: '+$_.Exception.Message)}
    }
    try {
        $found=Find-RecoveryInstallerInGui
        if($found.Found -and $found.Verified) {Add-DryRunLog 'A verified recovery MSI is locally available.'}
        elseif($found.Found){Add-DryRunLog 'A previous MSI was found, but authenticity still requires verification.'}
        else{Add-DryRunLog 'No complete previous MSI was found automatically; a full-machine recovery mechanism is not yet integrated.'}
    } catch {Add-DryRunLog ('NOTICE: automatic recovery discovery unavailable: '+$_.Exception.Message)}
    try {
        $cap=Get-OsrWindowsBackupCapability -InstallDirectory $script:txtInstall.Text.Trim()
        Add-DryRunLog ('Windows backup provider: '+$cap.Status+'; '+$cap.CandidateTargetCount+' unverified candidate fixed disks.')
        Add-DryRunLog 'Windows recovery is NOT automatically ready just because wbadmin is installed.'
    } catch {Add-DryRunLog ('NOTICE: Windows Backup inventory unavailable: '+$_.Exception.Message)}
    Add-DryRunLog 'Inspection was read-only. Service control, backup, MSI and rollback have not been executed.'
}
function Stop-DryRun([string]$Status) {
    $script:dryTimer.Stop()
    Show-DryRunProgress 'DONE' ($Status+'; all actions were simulations; no local report was created.') 100
    $script:DryRunActive=$false
    Set-GuiBusy $false
    Update-GuiMode
}
function Start-DryRunAcceptance {
    $tests=[string[]]$script:DryRunTests
    for($i=0;$i -lt $tests.Count;$i++) {
        $text=('Simulated test {0}/{1}: {2}' -f ($i+1),$tests.Count,$tests[$i])
        Show-DryRunProgress 'FUNCTIONAL_TEST' $text 90
        $answer=[Windows.Forms.MessageBox]::Show($form,
            "DRY RUN - no actual Freshservice test is performed.`n`n$text`n`nFor workflow simulation, select Yes, No or Cancel.",
            'Dry Run - acceptance simulation',[Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [Windows.Forms.MessageBoxIcon]::Question)
        if($answer -ne [Windows.Forms.DialogResult]::Yes) {
            Add-DryRunLog ('Functional test simulated as '+$answer+'.')
            $restore=[Windows.Forms.MessageBox]::Show($form,
                'DRY RUN: Simulate restoring the captured OSR baseline? No services, files, registry or MSI will be modified.',
                'Dry Run - rollback decision',[Windows.Forms.MessageBoxButtons]::YesNo,
                [Windows.Forms.MessageBoxIcon]::Question)
            if($restore -eq [Windows.Forms.DialogResult]::Yes){
                Show-DryRunProgress 'ROLLBACK' 'Would stop Freshworks services and execute the integrated recovery procedure (SIMULATED).' 94
                $restoreMessage=if((Get-GuiOperation) -eq 'LabRepair'){'Would verify the captured file tree, restore it with its permissions, and compare hashes (SIMULATED).'}else{'Would restore the previous MSI and backed-up configuration (SIMULATED).'}
                Show-DryRunProgress 'RESTORE' $restoreMessage 97
                Show-DryRunProgress 'HEALTH' 'Would restart both services and request recovery acceptance (SIMULATED).' 99
                $recoveryAccepted=[Windows.Forms.MessageBox]::Show($form,
                    'DRY RUN: Simulate that the previous OSR installation is operational after recovery?',
                    'Dry Run - recovery acceptance',[Windows.Forms.MessageBoxButtons]::YesNo,
                    [Windows.Forms.MessageBoxIcon]::Question)
                if($recoveryAccepted -eq [Windows.Forms.DialogResult]::Yes) {
                    Stop-DryRun 'ROLLBACK SIMULATED AND ACCEPTED'
                } else {
                    Stop-DryRun 'ROLLBACK SIMULATED - RECOVERY NOT VALIDATED'
                }
            } else {Stop-DryRun 'NOT VALIDATED - rollback declined (simulation)'}
            return
        }
        Add-DryRunLog 'Functional acceptance answered YES (simulation only).'
    }
    Stop-DryRun $(if((Get-GuiOperation) -eq 'LabRepair'){'SIMULATED LAB REPAIR ACCEPTED'}else{'SIMULATED UPGRADE ACCEPTED'})
}
function Start-DryRun([bool]$PreflightOnly) {
    if($script:DryRunActive -or ($script:ChildProcess -and -not $script:ChildProcess.HasExited)) {
        throw 'Another operation is running.'
    }
    $script:DryRunTests=[string[]](Get-Questions)
    $script:lstLog.Items.Clear()
    $script:progress.Value=0
    $script:DryRunActive=$true
    Set-GuiBusy $true
    try {
        Show-DryRunProgress 'START' 'Simulation mode enabled. No system changes will be performed.' 2
        Inspect-DryRunReadOnly
        if($PreflightOnly) {Stop-DryRun 'READ-ONLY PREFLIGHT COMPLETE'; return}
        $script:DryRunStages=@(
            @{Stage='PREFLIGHT';Message='Would validate privileges, MSI authenticity, service state and upgrade versions (SIMULATED).';Percent=15},
            @{Stage='RECOVERY_POINT';Message='Would auto-discover a trusted original MSI, assess recovery readiness and reserve protected backup storage (SIMULATED).';Percent=23},
            @{Stage='STOP_SERVICES';Message='Would stop Orchestration Server - WinRM_SSH, then Orchestration Server (SIMULATED).';Percent=30},
            @{Stage='BACKUP';Message='Would back up OSR application files and the verified original MSI if available (SIMULATED).';Percent=38},
            @{Stage='INSTALL';Message='Would invoke the official new MSI, with logging and no automatic reboot (SIMULATED).';Percent=57},
            @{Stage='START_SERVICES';Message='Would start Orchestration Server and Orchestration Server - WinRM_SSH (SIMULATED).';Percent=72},
            @{Stage='HEALTH';Message='Would validate installed version and both Windows services (SIMULATED).';Percent=83}
        )
        if ((Get-GuiOperation) -eq 'LabRepair') {
            $script:DryRunStages[0].Message = 'Would verify the named Hyper-V lab guest, checkpoint confirmation, exact MSI version and ProductCode (SIMULATED).'
            $script:DryRunStages[3].Message = 'Would capture installation files, directory permissions and original MSI, then verify hashes (SIMULATED).'
            $script:DryRunStages[4].Message = 'Would repair the same OSR version using /fomus with no automatic reboot (SIMULATED).'
        }
        $script:DryRunIndex=0
        $script:dryTimer.Start()
    } catch {
        $script:DryRunActive=$false
        Set-GuiBusy $false
        Update-GuiMode
        throw
    }
}
function Update-GuiMode {
    $elevated = Test-OsrAdministrator
    if ($elevated) {
        $script:lblPrivilege.Text = 'SESSION: ADMINISTRATOR'
        $script:lblPrivilege.ForeColor = [Drawing.Color]::FromArgb(18,112,72)
        $form.Text = $script:ApplicationTitle + ' [Administrator]'
    } else {
        $script:lblPrivilege.Text = 'SESSION: STANDARD USER'
        $script:lblPrivilege.ForeColor = [Drawing.Color]::FromArgb(162,89,22)
        $form.Text = $script:ApplicationTitle
    }
    $dry=[bool]$script:chkDryRun.Checked
    $lab = (Get-GuiOperation) -eq 'LabRepair'
    $script:btnStart.Text=if($dry){'Start dry run'}elseif($lab){'START LAB REPAIR'}else{'START REAL UPGRADE'}
    $script:lblLabComputer.Visible=$lab
    $script:txtLabComputer.Visible=$lab
    $script:chkApproval.Text=if($lab){'I authorize this same-version repair test on the dedicated lab guest.'}else{'I confirm the approved maintenance window and authorized production change.'}
    $script:chkRecovery.Text=if($lab){'I confirm a current host-side baseline checkpoint exists. Application restoration is still under test.'}else{'I confirm the downgrade/recovery procedure for these OSR versions was independently tested.'}
    $script:btnPreflight.Text=if($dry){'Read-only preflight'}else{'Run preflight'}
    $script:lblMode.Text=if($dry){
        'DRY RUN ACTIVE: only read-only discovery; upgrade, backups and recovery are SIMULATED.'
    }elseif($lab){
        'LIVE LAB REPAIR: only the named Hyper-V guest; file restoration is experimental. No cross-version validation.'
    }else{
        'LIVE MODE [ADMINISTRATOR]: backup, service control, installation and recovery CAN MODIFY THIS SERVER.'
    }
    $script:lblMode.ForeColor=if($dry){
        [Drawing.Color]::FromArgb(19,111,85)
    }else{
        [Drawing.Color]::FromArgb(171,65,42)
    }
    $script:btnLogs.Enabled=(-not $dry) -and (-not $script:DryRunActive)
    $script:chkApproval.Enabled=(-not $dry) -and (-not $script:DryRunActive)
    $script:chkRecovery.Enabled=(-not $dry) -and (-not $script:DryRunActive)
}
$script:dryTimer=New-Object Windows.Forms.Timer
$script:dryTimer.Interval=520
$script:dryTimer.Add_Tick({
    if(-not $script:DryRunActive){$script:dryTimer.Stop();return}
    if($script:DryRunIndex -lt @($script:DryRunStages).Count){
        $step=$script:DryRunStages[$script:DryRunIndex]
        Show-DryRunProgress $step.Stage $step.Message $step.Percent
        $script:DryRunIndex++
    }else{
        $script:dryTimer.Stop()
        try { Start-DryRunAcceptance }
        catch {
            Add-DryRunLog ('ERROR: '+$_.Exception.Message)
            Stop-DryRun 'SIMULATION INTERRUPTED'
        }
    }
})
$script:poll=New-Object Windows.Forms.Timer
$script:poll.Interval=900
$script:poll.Add_Tick({Refresh-Run})

$script:btnBackupCheck.Add_Click({
    try {
        $cap=Get-GuiWindowsBackupAssessment
        $candidates = if ($cap.CandidateTargetCount) {
            (@($cap.CandidateTargets) | ForEach-Object {
                ('{0} (free: {1:N1} GB; NOT VERIFIED)' -f $_.Drive,([double]$_.FreeBytes/1GB))
            }) -join [Environment]::NewLine
        } else { 'No separate local fixed disk found. An authorized UNC share may be used in a future version.' }
        $msg = @(
            ('Windows Server Backup: '+$cap.Status)
            ('Feature state: '+$cap.WindowsFeature)
            ('Windows volume: '+$cap.SystemDrive)
            ('OSR volume: '+$cap.OsrDrive)
            ''
            'Possible backup destinations (inspection only):'
            $candidates
            ''
            'This release does not create Windows backups or perform full-system recovery.'
            'A recovery provider cannot unlock a live upgrade until a valid restoration procedure exists.'
        ) -join [Environment]::NewLine
        [void][Windows.Forms.MessageBox]::Show($form,$msg,'Windows backup capability (read-only)',
            [Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        [void][Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'Windows backup discovery',
            [Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)
    }
})
$script:btnAutoFind.Add_Click({
    try { [void](Find-RecoveryInstallerInGui) }
    catch {[void][Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'Recovery discovery')}
})
$script:cboOperation.Add_SelectedIndexChanged({
    if ($script:RestoringSession) { return }
    $script:chkApproval.Checked=$false
    $script:chkRecovery.Checked=$false
    $script:chkDryRun.Checked=$true
    if ($script:txtRecoveryRoot.Text -in @($script:UpgradeRunBase,$script:LabRunBase)) {
        $script:txtRecoveryRoot.Text=if((Get-GuiOperation) -eq 'LabRepair'){$script:LabRunBase}else{$script:UpgradeRunBase}
    }
    $upgradeQuestion='Does a native Freshservice orchestration action succeed on a known-working target?'
    $labQuestion='Are both Freshworks services running, OSR version unchanged, and expected configuration present after repair?'
    if ($script:txtMandatory.Text -in @($upgradeQuestion,$labQuestion)) {
        $script:txtMandatory.Text=if((Get-GuiOperation) -eq 'LabRepair'){$labQuestion}else{$upgradeQuestion}
    }
    $script:lblStatus.Text='Operation changed. Dry Run is enabled; live approvals were cleared.'
    Update-GuiMode
})
$script:chkDryRun.Add_CheckedChanged({
    if ($script:RestoringSession -or $script:DryRunActive) { return }
    if (-not $script:chkDryRun.Checked) {
        $selection=[Windows.Forms.MessageBox]::Show($form,
            'Switch to LIVE MODE? Windows Administrator approval (UAC) is mandatory. Live operations can stop Freshworks services, create backups, modify files, and install the MSI. An approved recovery method and explicit deployment confirmation are also required.',
            'Administrator privileges required',
            [Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
        if ($selection -ne [Windows.Forms.DialogResult]::Yes) {
            $script:chkDryRun.Checked = $true
            return
        }
        if (-not (Test-OsrAdministrator)) {
            try { [void](Request-GuiElevation) }
            catch {
                [void][Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,
                    'Administrator elevation error',
                    [Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)
            }
            if (-not $script:ElevationStarted) { $script:chkDryRun.Checked = $true }
            return
        }
    } else {
        $script:lblStatus.Text = 'Dry Run enabled. Operations are simulated; existing session privileges are unchanged.'
    }
    Update-GuiMode
})
$script:btnPreflight.Add_Click({
    try { if($script:chkDryRun.Checked){Start-DryRun $true}else{New-Run 'Preflight'} }
    catch { [void][Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'Preflight error') }
})
$script:btnStart.Add_Click({
    if($script:chkDryRun.Checked){
        try {Start-DryRun $false} catch {[void][Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'Dry Run error')}
        return
    }
    $warning='LIVE UPGRADE: Freshworks services will be stopped and the OSR MSI will be installed. The previous MSI will be auto-discovered when possible. If a verified recovery package and a validated downgrade path are unavailable, the deployment is blocked. This may interrupt automations. Continue with the authorized change?'
    if ((Get-GuiOperation) -eq 'LabRepair') {
        $warning='LIVE LAB REPAIR: stop both Freshworks services, capture the installation tree, and repair the same MSI version. A named Hyper-V guest and an existing baseline checkpoint are required. If you reject the result, the GUI can offer experimental file restoration. Registry and external dependencies are outside this test. Continue with the authorized lab test?'
    }
    if([Windows.Forms.MessageBox]::Show($form,$warning,'LIVE operation confirmation',
        [Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning) -ne [Windows.Forms.DialogResult]::Yes){return}
    try{New-Run 'Deploy'}catch{[void][Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'Deployment blocked')}
})
$script:btnLogs.Add_Click({
    if($script:chkDryRun.Checked){
        [void][Windows.Forms.MessageBox]::Show($form,'Dry Run logs exist only in the GUI memory. No log folder or report files are created.','Dry Run - in-memory logs')
        return
    }
    $folder=if($script:CurrentRun){$script:CurrentRun}else{$script:RunBase}
    if(-not(Test-Path -LiteralPath $folder)){
        [void][Windows.Forms.MessageBox]::Show($form,'No run folder exists yet. A live operation must create a run first.','No logs available')
        return
    }
    Start-Process explorer.exe -ArgumentList ('"'+$folder+'"')
})
$form.Add_FormClosing({
    if($script:DryRunActive -or ($script:ChildProcess -and -not $script:ChildProcess.HasExited)){
        [void][Windows.Forms.MessageBox]::Show($form,
            'An operation is running. Keep this session open until it completes.',
            'Operation in progress',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)
        $_.Cancel=$true
    }
})
if (-not [string]::IsNullOrWhiteSpace($ResumeState)) {
    try {
        Restore-GuiResumeState $ResumeState
    } catch {
        $script:chkDryRun.Checked = $true
        [void][Windows.Forms.MessageBox]::Show($form,
            'The saved settings could not be restored after elevation. Dry Run remains enabled.' +
            [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message,
            'Resume failed',
            [Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)
    }
}
if (Test-OsrAdministrator) {
    $form.Text = $script:ApplicationTitle + ' [Administrator]'
}
Update-GuiMode
[void]$form.ShowDialog()
$script:dryTimer.Stop()
$script:poll.Stop()
$form.Dispose()
