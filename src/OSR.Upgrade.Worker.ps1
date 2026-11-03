#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Preflight','Deploy')][string]$Mode,
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][string]$ConfigurationPath,
    [ValidateSet('Upgrade','LabRepair','Replacement')][string]$Operation = 'Upgrade'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'OSR.Upgrade.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'OSR.Recovery.LabFiles.psm1') -Force

$runDir = [IO.Path]::GetFullPath($RunDirectory)
$config = Get-Content -LiteralPath $ConfigurationPath -Raw -ErrorAction Stop | ConvertFrom-Json
Assert-OsrLabPaths -Source ([string]$config.InstallDirectory) -Destination $runDir
[void](New-Item -Path $runDir -ItemType Directory -Force)
Protect-OsrLabDirectory -Path $runDir
$stateFile = Join-Path $runDir 'state.json'
$responseFile = Join-Path $runDir 'response.json'
$logFile = Join-Path $runDir 'activity.log'
$reportFile = Join-Path $runDir 'report.json'
$msiLog = Join-Path $runDir $(if($Operation -eq 'LabRepair'){'repair-msi.log'}else{'upgrade-msi.log'})
$backupPath = Join-Path $runDir 'recovery-point'
$before = $null; $after = $null; $target = $null; $previous = $null
$recoveryReady = $false; $stoppedForBackup = $false; $deploymentStarted = $false
$isLabRepair = $Operation -eq 'LabRepair'
$isReplacement = $Operation -eq 'Replacement'
$rebootRequired=$false
$runMutex=$null; $lockTaken=$false
$restartAttempted=$false
$labInventory = $null
$script:Report = [ordered]@{
    Mode=$Mode; Operation=$Operation; Host=$env:COMPUTERNAME; StartedAt=(Get-Date).ToString('o')
    CurrentVersion=$null; TargetVersion=$null; PreviousMsiVersion=$null
    NewInstallerSHA256=$null; RecoveryPoint=$null; MsiExitCode=$null
    PreviousMsiAutoDiscovered=$false; RecoveryProvider='UNDETERMINED'
    BackupIntegrity='NOT_VERIFIED'; LabFileRestoreVerified=$false; CrossVersionRollbackValidated=$false
    LabPathAssessment=$null; FileRestoreVerified=$false; IdentityMigrated=$false
    MigrationScope=$(if($isReplacement){'OSR_CONF_IDENTITY_ONLY'}else{'NOT_APPLICABLE'})
    Connectivity='NOT_AUTOMATICALLY_TESTED'; RebootRequired=$false; ManifestSHA256=$null
    Error=$null; RestartError=$null
    Tests=@(); Rollback='NOT_REQUESTED'; Status='RUNNING'; FinishedAt=$null
}

function Add-Log([string]$Message) {
    $line=('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message)
    for($attempt=0;$attempt -lt 12;$attempt++){
        try{Add-Content -LiteralPath $logFile -Encoding UTF8 -Value $line;return}
        catch [IO.IOException]{if($attempt -eq 11){throw};Start-Sleep -Milliseconds 75}
    }
}
function Write-JsonAtomic([string]$Path,[object]$Data) {
    $tmp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $json = ConvertTo-Json -InputObject $Data -Depth 10
    try {
        [IO.File]::WriteAllText($tmp,$json,[Text.Encoding]::UTF8)
        for($attempt=0;$attempt -lt 8;$attempt++){
            try{
                if([IO.File]::Exists($Path)){[IO.File]::Replace($tmp,$Path,[System.Management.Automation.Language.NullString]::Value)}
                else{[IO.File]::Move($tmp,$Path)}
                return
            }catch [IO.IOException]{if($attempt -eq 7){throw};Start-Sleep -Milliseconds 75}
        }
    }finally{if([IO.File]::Exists($tmp)){try{[IO.File]::Delete($tmp)}catch{}}}
}
function Write-WorkerFailure($Failure) {
    # Independent of the activity/state writers. Keep diagnostics in the protected run.
    $details=('Worker failure: {0}: {1}{2}{3}' -f $Failure.Exception.GetType().FullName,$Failure.Exception.Message,[Environment]::NewLine,$Failure.ScriptStackTrace)
    try{[IO.File]::AppendAllText((Join-Path $runDir 'worker-failure.log'),$details+[Environment]::NewLine,[Text.Encoding]::UTF8)}catch{}
    try{[Console]::Error.WriteLine($details)}catch{}
}
function Restart-BeforeDeploymentFailure {
    if($Mode -ne 'Deploy' -or -not $stoppedForBackup -or $deploymentStarted -or $restartAttempted){return}
    $script:restartAttempted=$true
    # Service recovery must run before any diagnostic write, which may itself fail.
    try{Start-OsrServices}catch{
        $script:Report.RestartError=$_.Exception.Message
        Write-WorkerFailure $_
    }
}
function Update-Progress([string]$Stage,[string]$Message,[int]$Percentage,[string]$Kind='WORKING',[string]$PromptId='') {
    $data = [ordered]@{
        Stage=$Stage; Message=$Message; Percent=$Percentage; Kind=$Kind
        PromptId=$PromptId; UpdatedAt=(Get-Date).ToString('o')
    }
    Write-JsonAtomic $stateFile $data
    Add-Log "$Stage | $Message"
}
function Save-Report([string]$Status) {
    $script:Report.Status=$Status
    $script:Report.FinishedAt=(Get-Date).ToString('o')
    Write-JsonAtomic $reportFile $script:Report
}
function Invoke-CheckedMsi([string]$Action,[string]$Media,[string]$LogName,[string]$Hash='') {
    if($Action -ne 'Uninstall'){
        if((Get-FileHash -LiteralPath $Media -Algorithm SHA256).Hash -ine $Hash){throw 'Saved MSI changed after verification.'}
        [void](Assert-OsrPackageAuthenticity -Path $Media -ExpectedSha256 $Hash)
    }
    $exit=Invoke-OsrMsi -Operation $Action -Target $Media -LogFile (Join-Path $runDir $LogName) -ExpectedSha256 $Hash
    $script:Report.MsiExitCode=$exit
    if($exit -eq 3010 -or $exit -eq 1641){
        $script:rebootRequired=$true; $script:Report.RebootRequired=$true
        throw 'Windows Installer requires reboot review. No further MSI or automatic reboot will be executed.'
    }
    if($exit -ne 0){throw ("MSI {0} failed with exit code {1}. Inspect the protected MSI log; 1603 alone is not a diagnosis." -f $Action,$exit)}
}
function Assert-SavedRecoveryPoint {
    if(-not $recoveryReady -or $null -eq $labInventory){throw 'A complete verified recovery point is required.'}
    if((Get-FileHash -LiteralPath $previous.Path -Algorithm SHA256).Hash -ine $previous.Sha256){throw 'Recovery MSI integrity check failed.'}
    [void](Assert-OsrPackageAuthenticity -Path $previous.Path -ExpectedSha256 $previous.Sha256)
    $verifyProgress={param($Phase,$Done,$Total) Update-Progress 'VERIFY_RECOVERY' ("{0}: {1} entries" -f $Phase,$Done) 40}
    Assert-OsrLabTreeEqual -Expected $labInventory -Actual (Get-OsrLabTreeInventory (Join-Path $backupPath 'files') -Progress $verifyProgress)
}
function Await-Decision([string]$Question,[int]$Percent,[string]$Stage='OPERATOR_TEST') {
    $id = [guid]::NewGuid().ToString('N')
    if (Test-Path -LiteralPath $responseFile) { Remove-Item -LiteralPath $responseFile -Force }
    Update-Progress $Stage $Question $Percent 'PROMPT' $id
    $until=(Get-Date).AddHours(3)
    while ((Get-Date) -lt $until) {
        if (Test-Path -LiteralPath $responseFile) {
            try {
                $answer = Get-Content -LiteralPath $responseFile -Raw | ConvertFrom-Json
                if ($answer.PromptId -eq $id -and $answer.Answer -in @('YES','NO','CANCEL')) {
                    Remove-Item -LiteralPath $responseFile -Force -ErrorAction SilentlyContinue
                    Add-Log "$Stage response: $($answer.Answer)"
                    return [string]$answer.Answer
                }
            } catch { }
        }
        Start-Sleep -Milliseconds 600
    }
    throw 'Operator response timeout. Do not assume that the upgrade is validated.'
}
function Require-BasicPreflight {
    Update-Progress 'PREFLIGHT' 'Checking Windows administration privileges and OSR installation...' 5
    if (-not (Test-OsrAdministrator)) { throw 'Run the application as an elevated administrator.' }
    if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
    if ($isLabRepair) {
        Assert-OsrLabEnvironment -ExpectedComputerName ([string]$config.LabExpectedComputerName) -System (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop)
        Assert-OsrLabPaths -Source ([string]$config.InstallDirectory) -Destination $runDir
        Protect-OsrLabDirectory -Path $runDir
        if ($config.LabCheckpointConfirmed -isnot [bool] -or -not $config.LabCheckpointConfirmed) {
            throw 'Lab Repair requires operator confirmation of an existing host-side baseline checkpoint.'
        }
    }
    $script:before = Get-OsrProduct
    $actualDir = Get-OsrInstallDirectory
    if (([IO.Path]::GetFullPath([string]$config.InstallDirectory)).TrimEnd('\') -ine ([IO.Path]::GetFullPath($actualDir)).TrimEnd('\')) {
        throw "Selected directory does not match the current OSR installation: $actualDir"
    }
    $serviceRecords=@(Get-OsrServiceRecords)
    if($serviceRecords.Count -ne 2){throw 'Expected exactly two Freshworks services before deployment.'}
    foreach($svc in $serviceRecords) {
        if ($svc.State -ne 'Running') { throw "Service is not running before upgrade: $($svc.DisplayName)" }
    }
    Update-Progress 'PREFLIGHT' 'Inspecting Freshworks MSI packages and signatures...' 12
    $script:target = Get-OsrMsiMetadata -Path ([string]$config.MsiPath)
    $sig = Assert-OsrPackageAuthenticity -Path $target.Path -ExpectedSha256 ([string]$config.ExpectedSha256)
    if ($isLabRepair) {
        Assert-OsrSameVersionRepair -InstalledProduct $before -Package $target
        if ([IO.Path]::GetFullPath($target.Path) -match '(?i)\\Windows\\Installer\\') { throw 'Lab Repair requires original media outside the Windows Installer cache.' }
        $script:previous = $target.PSObject.Copy()
        $script:Report.RecoveryProvider='LAB_SAME_VERSION_FILES'
    } else {
    if ($target.Version -le $before.Version) { throw "Upgrade MSI $($target.Version) is not newer than installed $($before.Version)." }
    if(-not $isReplacement -and $before.Version -eq [version]'2.4.0.0' -and $target.Version -eq [version]'2.5.0.0'){
        throw 'The tested 2.4 -> 2.5 in-place MSI path fails on residual Osr.jar. Select Controlled replacement; do not delete individual application files.'
    }
    $previousPath=[string]$config.PreviousMsiPath
    if([string]::IsNullOrWhiteSpace($previousPath)) {
        Update-Progress 'RECOVERY_DISCOVERY' 'Searching local original MSIs and prior recovery points for the installed version...' 14
        $find = Find-OsrPreviousMsi -InstalledVersion $before.Version -UpgradeMsiPath $target.Path -RecoveryRoot ([string]$config.BackupRoot) -ExpectedSha256 ([string]$config.PreviousSha256)
        if($find.Found -and $find.Verified) {
            $previousPath=$find.Path
            $script:Report.PreviousMsiAutoDiscovered=$true
            Add-Log ('Automatically discovered a verified old MSI at: ' + $previousPath)
        } elseif($find.Found) {
            Add-Log 'A matching previous-version MSI was found but its authenticity could not be verified.'
        } else {
            Add-Log 'No complete original previous-version MSI found in bounded local locations.'
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($previousPath)) {
        if ([IO.Path]::GetFullPath($previousPath) -match '(?i)\\Windows\\Installer\\') {
            throw 'Windows Installer cached packages are not accepted as original recovery media.'
        }
        $script:previous = Get-OsrMsiMetadata -Path $previousPath
        [void](Assert-OsrPackageAuthenticity -Path $previous.Path -ExpectedSha256 ([string]$config.PreviousSha256))
        if ($previous.Version -ne $before.Version) { throw "Previous MSI must match installed version $($before.Version)." }
        if (-not $previous.ProductCode) { throw 'Previous MSI ProductCode missing.' }
        if($previous.ProductCode -ine $before.ProductCode){throw 'Recovery MSI ProductCode must match the installed product.'}
        $script:Report.RecoveryProvider='APPLICATION_MSI_VERIFIED'
    }
    }
    if($isReplacement){
        Assert-OsrReplacementProfile -Installed $before -Original $previous -Target $target
        if(-not $sig.VendorSignature){throw 'Controlled replacement requires a valid vendor signature.'}
        $identity=Join-Path $actualDir 'osr\config\osr.conf'
        if(-not(Test-Path -LiteralPath $identity -PathType Leaf) -or (Get-Item -LiteralPath $identity).Length -eq 0){throw 'A nonempty osr.conf identity file is required.'}
        $script:Report.RecoveryProvider='VERIFIED_FILES_AND_ORIGINAL_MSI'
        if($Mode -eq 'Deploy' -and ($config.MigrationScopeApproved -isnot [bool] -or -not $config.MigrationScopeApproved)){
            throw 'Confirm identity-only migration scope; proxy/custom application settings and external dependencies are not migrated.'
        }
    }
    Assert-OsrSafePath -InstallDirectory $actualDir -BackupRoot $runDir
    $oldPackagePath = if($previous){[IO.Path]::GetFullPath($previous.Path)}else{''}
    if($oldPackagePath -and $oldPackagePath.StartsWith(
        ([IO.Path]::GetFullPath($actualDir).TrimEnd('\')+'\'),
        [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Previous version MSI must be stored outside the OSR installation folder.'
    }
    if(([IO.Path]::GetFullPath($target.Path)).StartsWith(([IO.Path]::GetFullPath($actualDir).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){
        throw 'Target MSI must be stored outside the installation folder.'
    }
    if (-not @($config.Questions).Count) { throw 'Define at least one required functional acceptance test.' }
    $script:Report.CurrentVersion = "$($before.Version)"
    $script:Report.TargetVersion = "$($target.Version)"
    $script:Report.NewInstallerSHA256 = $target.Sha256
    if ($previous) { $script:Report.PreviousMsiVersion="$($previous.Version)" }
    Add-Log "Installed version: $($before.Version) | Target: $($target.Version) | Package SHA256: $($target.Sha256) | Signature: $($sig.Signature)"
    if (-not $previous) {
        $environment=Get-OsrRecoveryEnvironment
        Add-Log ('Recovery capability: ' + $environment.Message)
        throw 'No verified automatic recovery provider is available. Search found no complete, trusted original MSI. A VM indicator or Windows backup command alone does not prove that a restorable snapshot exists. Upgrade BLOCKED.'
    }
    if ($Mode -eq 'Deploy') {
        if ($config.MaintenanceApproved -isnot [bool] -or -not $config.MaintenanceApproved) { throw 'Maintenance authorization must be confirmed before deployment.' }
        if (-not $isLabRepair -and ($config.RecoveryProcedureValidated -isnot [bool] -or -not $config.RecoveryProcedureValidated)) {
            throw 'The specific downgrade/reinstallation recovery path has not been independently tested for this OSR version pair. Upgrade BLOCKED.'
        }
    }
    $script:Report.LabPathAssessment=Assert-OsrLabPathBudget -Source $actualDir -Destination (Join-Path $backupPath 'files')
    $sourceBytes=0L
    Get-ChildItem -LiteralPath $actualDir -Recurse -File -Force -ErrorAction Stop | ForEach-Object{$sourceBytes+=$_.Length}
    $requiredBytes=$sourceBytes+(Get-Item -LiteralPath $previous.Path).Length+(Get-Item -LiteralPath $target.Path).Length+64MB
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($runDir))
    if($drive.AvailableFreeSpace -lt $requiredBytes){throw 'Insufficient space for the verified tree and both MSI packages.'}
    Add-Log ('Backup paths checked before service control; longest destination path: '+$script:Report.LabPathAssessment.LongestDestinationPath+' characters.')
    Update-Progress 'PREFLIGHT' 'MSI identity, versions, service state, and installation location verified.' 18
}
function New-RecoveryPoint {
    Update-Progress 'BACKUP' 'Creating an offline copy of the existing OSR installation...' 23
    $existingPath = [string]$config.InstallDirectory
    $script:stoppedForBackup = $true
    Stop-OsrServices
    Add-Log 'Both Freshworks services stopped. Native Windows WinRM was not modified.'
    [void](New-Item -Path $backupPath -ItemType Directory -Force)
    # Keep a verified copy of the recovery MSI inside the restricted recovery point.
    $savedMsi = Join-Path $backupPath 'previous-FO-OSR.msi'
    Copy-Item -LiteralPath $previous.Path -Destination $savedMsi -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $savedMsi -Algorithm SHA256).Hash -ine $previous.Sha256) {
        throw 'Recovery MSI copy integrity check failed.'
    }
    $script:previous.Path = $savedMsi
    $filesPath = Join-Path $backupPath 'files'
    Update-Progress 'BACKUP' 'Hashing, copying and verifying the offline installation tree...' 26
    $captureProgress={param($Phase,$Done,$Total) Update-Progress 'BACKUP' ("{0}: {1}{2}" -f $Phase,$Done,$(if($Total){' / '+$Total}else{' entries'})) 28}
    $script:labInventory = New-OsrLabFileSnapshot -Source $existingPath -Destination $filesPath -Progress $captureProgress
    $savedTarget=Join-Path $backupPath 'target-FO-OSR.msi'
    Update-Progress 'BACKUP' 'Preserving and verifying the target MSI...' 31
    Copy-Item -LiteralPath $target.Path -Destination $savedTarget -ErrorAction Stop
    if((Get-FileHash -LiteralPath $savedTarget).Hash -ine $target.Sha256){throw 'Target MSI copy integrity check failed.'}
    $script:target.Path=$savedTarget
    $script:Report.BackupIntegrity='INSTALLATION_TREE_AND_MEDIA_VERIFIED'
    $manifest = [ordered]@{
        Version = "$($before.Version)"; InstallDirectory=$existingPath
        PreviousMsi=$previous.Path; PreviousMsiSha256=$previous.Sha256
        Services=@(Get-OsrServiceRecords | Select-Object Name,DisplayName,StartMode,StartName,PathName)
        CreatedAt=(Get-Date).ToString('o')
    }
    $manifest.Operation=$Operation; $manifest.LabFileInventory=$labInventory
    Write-JsonAtomic (Join-Path $backupPath 'manifest.json') $manifest
    $script:Report.ManifestSHA256=(Get-FileHash -LiteralPath (Join-Path $backupPath 'manifest.json')).Hash
    foreach($name in @('osr.conf','application.conf')) {
        $file = Join-Path $existingPath ('osr\config\'+$name)
        if (Test-Path -LiteralPath $file) {
            Add-Log "Configuration file backed up: $name (contents not logged)."
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $filesPath 'osr') -PathType Container)) {
        throw 'Recovery point is missing its osr directory.'
    }
    $script:Report.RecoveryPoint=$backupPath
    $script:recoveryReady=$true
    Update-Progress 'BACKUP' 'Recovery point created; previous MSI verified.' 35
}
function Restore-IntegratedRecovery {
    $script:Report.Rollback='STARTED'
    Update-Progress 'ROLLBACK' 'Verifying the saved application recovery point before recovery changes...' 76
    try {
        Assert-SavedRecoveryPoint
        $actual=Get-OsrProduct -AllowAbsent
        if($isLabRepair){
            if($null -eq $actual){throw 'Same-version lab repair cannot restore an absent product.'}
            Assert-OsrLabEnvironment -ExpectedComputerName ([string]$config.LabExpectedComputerName) -System (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop)
            Assert-OsrSameVersionRepair -InstalledProduct $actual -Package $previous
        }else{
            if(-not $actual){Stop-OsrPresentServices}
            if($actual){
                $isOriginal=$actual.Version -eq $before.Version -and $actual.ProductCode -ieq $before.ProductCode
                $isTarget=$actual.Version -eq $target.Version -and $actual.ProductCode -ieq $target.ProductCode
                if(-not($isOriginal -or $isTarget)){throw 'Unexpected registered OSR identity. Recovery will not uninstall an unrelated product.'}
                Stop-OsrPresentServices
                Update-Progress 'ROLLBACK' 'Removing the recognized installation before reinstalling original media...' 78
                Invoke-CheckedMsi 'Uninstall' $actual.ProductCode 'rollback-uninstall.log'
                if($null -ne (Get-OsrProduct -AllowAbsent)){throw 'A product remains registered after removal. Manual intervention is required.'}
            }
            # Never delete unregistered residual folders automatically.
            if(Test-Path -LiteralPath ([string]$config.InstallDirectory)){
                throw 'Residual installation folder remains without a usable product. Preserve it and investigate; automatic deletion is disabled.'
            }
            Update-Progress 'ROLLBACK' 'Reinstalling the verified original MSI; missing product/services are supported...' 80
            Invoke-CheckedMsi 'Install' $previous.Path 'rollback-reinstall.log' $previous.Sha256
        }
        $restoredProduct=Get-OsrProduct
        if($restoredProduct.Version -ne $before.Version -or $restoredProduct.ProductCode -ine $before.ProductCode){throw 'Original product identity was not restored.'}
        $actualDirectory=Get-OsrInstallDirectory
        if([IO.Path]::GetFullPath($actualDirectory).TrimEnd('\') -ine [IO.Path]::GetFullPath([string]$config.InstallDirectory).TrimEnd('\')){
            throw 'Restored service executable directory differs from the captured location.'
        }
        Stop-OsrServices
        Update-Progress 'RESTORE' 'Restoring the captured original file tree and permissions...' 84
        $restoreProgress={param($Phase,$Done,$Total) Update-Progress 'RESTORE' ("{0}: {1}{2}" -f $Phase,$Done,$(if($Total){' / '+$Total}else{' entries'})) 86}
        Restore-OsrLabFileSnapshot -Source (Join-Path $backupPath 'files') -Destination $actualDirectory -Inventory $labInventory -Progress $restoreProgress
        $script:Report.FileRestoreVerified=$true
        if($isLabRepair){$script:Report.LabFileRestoreVerified=$true}
        Start-OsrServices
        $script:Report.Rollback='TECHNICALLY_RESTORED'
        $recoveryQuestion=if($isLabRepair){'LAB: File hashes and permissions match the captured baseline. Are both Freshworks services running and the expected configuration present? No orchestration execution is required.'}else{'Original version, file hashes and permissions are restored. Verify Freshservice connectivity and all required functional checks before accepting. ONLINE alone does not prove workflow success.'}
        $response=Await-Decision -Question $recoveryQuestion -Percent 94 -Stage 'RECOVERY_ACCEPTANCE'
        if($response -ne 'YES'){throw 'Recovery was not confirmed by the operator.'}
        $script:Report.Rollback='ORIGINAL_FILES_RESTORED_OPERATOR_ACCEPTED'
        Save-Report $(if($isLabRepair){'LAB_FILES_RESTORED'}else{'ROLLED_BACK'})
        Update-Progress 'DONE' 'Original application restored and operator-accepted; review the report scope.' 100 'DONE'
    }catch{
        $script:Report.Rollback='FAILED_REQUIRES_OPERATOR'
        Add-Log ('Recovery requires manual intervention: '+$_.Exception.Message)
        if(-not $rebootRequired){
            try{
                $remaining=Get-OsrProduct -AllowAbsent
                if($remaining -and ($remaining.ProductCode -ieq $before.ProductCode -or $remaining.ProductCode -ieq $target.ProductCode)){
                    Start-OsrServices; Add-Log 'Best-effort restart of the recognized product attempted.'
                }
            }catch{Add-Log 'Service restart could not complete. Inspect protected diagnostics.'}
        }
        Save-Report $(if($rebootRequired){'REBOOT_REQUIRED'}else{'RECOVERY_FAILED'})
        Update-Progress 'FAILED' 'Recovery needs operator review; backup retained. No further automatic MSI action.' 100 'FAILED'
    }
}

function Offer-Rollback([string]$Reason) {
    Add-Log "Deployment not validated: $Reason"
    $response = Await-Decision -Question "${Reason}`nWould you like to run the integrated rollback now?" -Percent 80 -Stage 'ROLLBACK_DECISION'
    if ($response -eq 'YES') { Restore-IntegratedRecovery }
    else {
        $script:Report.Rollback='DECLINED'
        Save-Report 'DEPLOYED_NOT_VALIDATED'
        Update-Progress 'DONE' 'Rollback declined. Deployment NOT VALIDATED; review operational state.' 100 'DONE'
    }
}
function Invoke-ManualAcceptance {
    $qs = @($config.Questions)
    for ($i=0; $i -lt $qs.Count; $i++) {
        $question = $qs[$i]
        $instruction = if ($isLabRepair) { 'Inspect local lab state, then select Yes or No. No production workflow is required.' } else { 'Perform the test in Freshservice, then select Yes or No.' }
        $answer = Await-Decision -Question ("Test {0}/{1}: {2}`n{3}" -f ($i+1),$qs.Count,$question,$instruction) -Percent (85 + [int](8*($i+1)/$qs.Count))
        $script:Report.Tests += @{Question=$question;Result= $(if($answer -eq 'YES'){'PASS'}else{'FAIL'});Time=(Get-Date).ToString('o')}
        if ($answer -ne 'YES') {
            Offer-Rollback -Reason "Functional test failed or was not confirmed: $question"
            return
        }
    }
    Save-Report $(if($isLabRepair){'LAB_REPAIR_ACCEPTED'}else{'ACCEPTED'})
    Update-Progress 'DONE' 'Operation accepted after operator validation. Review the report scope.' 100 'DONE'
}

try {
    $runMutex=New-Object Threading.Mutex($false,'Global\FreshworksOSRUpgradeManager-Operation')
    try{$lockTaken=$runMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{
        $lockTaken=$true; throw 'A previous process ended unexpectedly. Review its run before starting another operation.'
    }
    if(-not $lockTaken){throw 'Another application worker is active on this host.'}
    Require-BasicPreflight
    if ($Mode -eq 'Preflight') {
        Save-Report 'PREFLIGHT_PASSED'
        Update-Progress 'DONE' 'Preflight completed. No installation or backup changes.' 100 'DONE'
        return
    }
    Update-Progress 'BACKUP' 'Preparing offline OSR recovery point...' 20
    New-RecoveryPoint
    Update-Progress 'INSTALL' $(if($isLabRepair){'Starting same-version MSI lab repair...'}else{'Starting official Freshworks MSI upgrade...'}) 45
    if ((Get-FileHash -LiteralPath $target.Path -Algorithm SHA256).Hash -ine $target.Sha256) {
        throw 'The selected upgrade MSI changed after preflight.'
    }
    $script:deploymentStarted=$true
    if ($isLabRepair) {
        if ((Get-FileHash -LiteralPath $previous.Path -Algorithm SHA256).Hash -ine $previous.Sha256) { throw 'The saved repair MSI changed after capture.' }
        Invoke-CheckedMsi 'Repair' $previous.Path ([IO.Path]::GetFileName($msiLog)) $previous.Sha256
    } else {
        if($isReplacement){
            Assert-SavedRecoveryPoint
            Update-Progress 'REMOVE_OLD' 'Controlled replacement: uninstalling the captured original product...' 42
            Invoke-CheckedMsi 'Uninstall' $before.ProductCode 'replacement-uninstall.log'
            if($null -ne (Get-OsrProduct -AllowAbsent)){throw 'Previous product remains registered after removal.'}
            if(Test-Path -LiteralPath ([string]$config.InstallDirectory)){
                throw 'Old installation folder remains. Clean replacement is blocked; no automatic deletion will be attempted.'
            }
        }
        Update-Progress 'INSTALL' 'Installing the authenticated target MSI; no automatic reboot...' 55
        Invoke-CheckedMsi 'Install' $target.Path ([IO.Path]::GetFileName($msiLog)) $target.Sha256
    }
    Update-Progress 'HEALTH' 'Checking installed OSR version and starting Freshworks services...' 72
    $after=Get-OsrProduct
    if ($after.Version -ne $target.Version -or $after.ProductCode -ine $target.ProductCode) { throw 'Installed product identity does not match the target MSI.' }
    if($isReplacement){
        $newDirectory=Get-OsrInstallDirectory
        if([IO.Path]::GetFullPath($newDirectory).TrimEnd('\') -ine [IO.Path]::GetFullPath([string]$config.InstallDirectory).TrimEnd('\')){throw 'Target installed into an unexpected directory.'}
        Stop-OsrServices
        Assert-SavedRecoveryPoint
        $identityEntry=@($labInventory.Entries | Where-Object Path -ieq 'osr\config\osr.conf')
        if($identityEntry.Count -ne 1 -or $identityEntry[0].Directory -or $identityEntry[0].Length -eq 0){throw 'Captured identity file is missing or empty.'}
        $savedIdentity=Join-Path $backupPath 'files\osr\config\osr.conf'
        $destinationIdentity=Join-Path $newDirectory 'osr\config\osr.conf'
        Assert-OsrLabPaths -Source $savedIdentity -Destination $destinationIdentity
        if((Get-Item -LiteralPath $destinationIdentity -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Target identity cannot be a reparse point.'}
        Copy-Item -LiteralPath $destinationIdentity -Destination (Join-Path $backupPath 'target-default-osr.conf') -ErrorAction Stop
        Copy-Item -LiteralPath $savedIdentity -Destination $destinationIdentity -Force -ErrorAction Stop
        if((Get-FileHash -LiteralPath $destinationIdentity).Hash -ine $identityEntry[0].SHA256){throw 'Migrated identity hash mismatch.'}
        $script:Report.IdentityMigrated=$true
        Add-Log 'Saved osr.conf identity restored and hash-verified; target application.conf and binaries retained. Contents are not logged.'
    }
    Start-OsrServices
    Update-Progress 'ACCEPTANCE' 'Windows services running. Waiting for manual functional validation.' 83
    Invoke-ManualAcceptance
} catch {
    $failure=$_
    $err=$failure.Exception.Message
    $script:Report.Error=$err
    Restart-BeforeDeploymentFailure
    Write-WorkerFailure $failure
    try{Add-Log "ERROR: $err"}catch{Write-WorkerFailure $_}
    if($rebootRequired){
        Save-Report 'REBOOT_REQUIRED'
        Update-Progress 'BLOCKED' 'Installer reboot review required. No automatic reboot or recovery MSI was started.' 100 'FAILED'
    }
    elseif ($Mode -eq 'Deploy' -and $stoppedForBackup -and -not $deploymentStarted) {
        try{Add-Log $(if($Report.RestartError){'Service restart failed; manual intervention required.'}else{'Services restarted after pre-upgrade failure.'})}catch{Write-WorkerFailure $_}
        Save-Report 'PRE_DEPLOY_FAILED'
        Update-Progress 'FAILED' "Pre-deployment failed; check services: $err" 100 'FAILED'
    }
    elseif ($Mode -eq 'Deploy' -and $recoveryReady) {
        try { Offer-Rollback -Reason $err }
        catch {
            Save-Report 'DEPLOYED_NOT_VALIDATED'
            Update-Progress 'FAILED' 'Upgrade or operator validation failed. Review run logs and recovery state.' 100 'FAILED'
        }
    }
    else {
        Save-Report 'FAILED'
        Update-Progress 'FAILED' "Operation failed: $err" 100 'FAILED'
    }
}finally{
    Restart-BeforeDeploymentFailure
    if($lockTaken -and $runMutex){$runMutex.ReleaseMutex()}
    if($runMutex){$runMutex.Dispose()}
}
