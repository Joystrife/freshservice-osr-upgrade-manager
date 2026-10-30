#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Preflight','Deploy')][string]$Mode,
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][string]$ConfigurationPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'OSR.Upgrade.Core.psm1') -Force

$runDir = [IO.Path]::GetFullPath($RunDirectory)
[void](New-Item -Path $runDir -ItemType Directory -Force)
$config = Get-Content -LiteralPath $ConfigurationPath -Raw -ErrorAction Stop | ConvertFrom-Json
$stateFile = Join-Path $runDir 'state.json'
$responseFile = Join-Path $runDir 'response.json'
$logFile = Join-Path $runDir 'activity.log'
$reportFile = Join-Path $runDir 'report.json'
$msiLog = Join-Path $runDir 'upgrade-msi.log'
$backupPath = Join-Path $runDir 'recovery-point'
$before = $null; $after = $null; $target = $null; $previous = $null
$recoveryReady = $false; $stoppedForBackup = $false; $deploymentStarted = $false
$script:Report = [ordered]@{
    Mode=$Mode; Host=$env:COMPUTERNAME; StartedAt=(Get-Date).ToString('o')
    CurrentVersion=$null; TargetVersion=$null; PreviousMsiVersion=$null
    NewInstallerSHA256=$null; RecoveryPoint=$null; MsiExitCode=$null
    PreviousMsiAutoDiscovered=$false; RecoveryProvider='UNDETERMINED'
    Tests=@(); Rollback='NOT_REQUESTED'; Status='RUNNING'; FinishedAt=$null
}

function Add-Log([string]$Message) {
    ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message) |
        Add-Content -LiteralPath $logFile -Encoding UTF8
}
function Write-JsonAtomic([string]$Path,[object]$Data) {
    $tmp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $json = ConvertTo-Json -InputObject $Data -Depth 10
    [IO.File]::WriteAllText($tmp,$json,[Text.Encoding]::UTF8)
    if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
    [IO.File]::Move($tmp,$Path)
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
    $script:before = Get-OsrProduct
    $actualDir = Get-OsrInstallDirectory
    if (([IO.Path]::GetFullPath([string]$config.InstallDirectory)).TrimEnd('\') -ine ([IO.Path]::GetFullPath($actualDir)).TrimEnd('\')) {
        throw "Selected directory does not match the current OSR installation: $actualDir"
    }
    foreach($svc in @(Get-OsrServiceRecords)) {
        if ($svc.State -ne 'Running') { throw "Service is not running before upgrade: $($svc.DisplayName)" }
    }
    Update-Progress 'PREFLIGHT' 'Inspecting Freshworks MSI packages and signatures...' 12
    $script:target = Get-OsrMsiMetadata -Path ([string]$config.MsiPath)
    $sig = Assert-OsrPackageAuthenticity -Path $target.Path -ExpectedSha256 ([string]$config.ExpectedSha256)
    if ($target.Version -le $before.Version) { throw "Upgrade MSI $($target.Version) is not newer than installed $($before.Version)." }
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
        $script:Report.RecoveryProvider='APPLICATION_MSI_VERIFIED'
    }
    Assert-OsrSafePath -InstallDirectory $actualDir -BackupRoot $runDir
    $oldPackagePath = if($previous){[IO.Path]::GetFullPath($previous.Path)}else{''}
    if($oldPackagePath -and $oldPackagePath.StartsWith(
        ([IO.Path]::GetFullPath($actualDir).TrimEnd('\')+'\'),
        [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Previous version MSI must be stored outside the OSR installation folder.'
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
        if (-not [bool]$config.MaintenanceApproved) { throw 'Maintenance authorization must be confirmed before deployment.' }
        if (-not [bool]$config.RecoveryProcedureValidated) {
            throw 'The specific downgrade/reinstallation recovery path has not been independently tested for this OSR version pair. Upgrade BLOCKED.'
        }
    }
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
    [void](Invoke-OsrRobocopy -Source $existingPath -Destination $filesPath -LogFile (Join-Path $runDir 'backup-robocopy.log'))
    $manifest = [ordered]@{
        Version = "$($before.Version)"; InstallDirectory=$existingPath
        PreviousMsi=$previous.Path; PreviousMsiSha256=$previous.Sha256
        Services=@(Get-OsrServiceRecords | Select-Object Name,DisplayName,StartMode,StartName,PathName)
        CreatedAt=(Get-Date).ToString('o')
    }
    Write-JsonAtomic (Join-Path $backupPath 'manifest.json') $manifest
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
    Update-Progress 'ROLLBACK' 'Restoring the earlier OSR version with the integrated recovery engine...' 77
    try {
        $actual = Get-OsrProduct
        if ($actual.Version -ne $before.Version) {
            Stop-OsrServices
            if (-not $actual.ProductCode) { throw 'Cannot determine upgraded product code for MSI removal.' }
            Add-Log 'Removing upgraded version through Windows Installer.'
            $exit = Invoke-OsrMsi -Operation Uninstall -Target $actual.ProductCode -LogFile (Join-Path $runDir 'rollback-uninstall.log')
            if ($exit -ne 0) { throw "Upgraded MSI removal failed: exit code $exit. Automatic recovery stopped." }
            Add-Log 'Reinstalling previous validated MSI. The vendor downgrade path must be validated in staging.'
            $exit = Invoke-OsrMsi -Operation Install -Target $previous.Path -LogFile (Join-Path $runDir 'rollback-reinstall.log')
            if ($exit -ne 0) { throw "Previous MSI reinstallation failed: exit code $exit." }
        }
        Stop-OsrServices
        $files = Join-Path $backupPath 'files'
        [void](Invoke-OsrRobocopy -Source $files -Destination ([string]$config.InstallDirectory) -Mirror -LogFile (Join-Path $runDir 'rollback-files.log'))
        Start-OsrServices
        $confirmed = Get-OsrProduct
        if ($confirmed.Version -ne $before.Version) { throw "Restoration version mismatch: $($confirmed.Version) != $($before.Version)." }
        $script:Report.Rollback='TECHNICALLY_RESTORED'
        $response = Await-Decision -Question 'Do the critical Freshservice orchestrations work after the restoration?' -Percent 94 -Stage 'RECOVERY_ACCEPTANCE'
        if ($response -ne 'YES') { throw 'Recovery was not confirmed by the administrator.' }
        $script:Report.Rollback='FUNCTIONALLY_RESTORED'
        Save-Report 'ROLLED_BACK'
        Update-Progress 'DONE' 'Previous installation restored and operator-validated.' 100 'DONE'
    } catch {
        $script:Report.Rollback='FAILED_REQUIRES_OPERATOR'
        Add-Log "Recovery requires manual intervention: $($_.Exception.Message)"
        try { Start-OsrServices; Add-Log 'Best-effort service restart attempted.' } catch { Add-Log "Could not start OSR services: $($_.Exception.Message)" }
        Save-Report 'RECOVERY_FAILED'
        Update-Progress 'FAILED' 'Recovery could not complete. Manual intervention required; inspect local logs.' 100 'FAILED'
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
        $answer = Await-Decision -Question ("Test {0}/{1}: {2}`nPerform the test in Freshservice, then select Yes or No." -f ($i+1),$qs.Count,$question) -Percent (85 + [int](8*($i+1)/$qs.Count))
        $script:Report.Tests += @{Question=$question;Result= $(if($answer -eq 'YES'){'PASS'}else{'FAIL'});Time=(Get-Date).ToString('o')}
        if ($answer -ne 'YES') {
            Offer-Rollback -Reason "Functional test failed or was not confirmed: $question"
            return
        }
    }
    Save-Report 'ACCEPTED'
    Update-Progress 'DONE' 'Upgrade accepted after operator functional validation.' 100 'DONE'
}

try {
    Require-BasicPreflight
    if ($Mode -eq 'Preflight') {
        Save-Report 'PREFLIGHT_PASSED'
        Update-Progress 'DONE' 'Preflight completed. No installation or backup changes.' 100 'DONE'
        return
    }
    Update-Progress 'BACKUP' 'Preparing offline OSR recovery point...' 20
    New-RecoveryPoint
    Update-Progress 'INSTALL' 'Starting official Freshworks MSI upgrade...' 45
    if ((Get-FileHash -LiteralPath $target.Path -Algorithm SHA256).Hash -ine $target.Sha256) {
        throw 'The selected upgrade MSI changed after preflight.'
    }
    $script:deploymentStarted=$true
    $code = Invoke-OsrMsi -Operation Install -Target $target.Path -LogFile $msiLog -Interactive
    $script:Report.MsiExitCode=$code
    if ($code -notin @(0,3010)) { throw "MSI upgrade failed: exit code $code" }
    if ($code -eq 3010) {
        throw 'MSI requires a reboot (3010). Reboot was not performed automatically; operator recovery decision required.'
    }
    Update-Progress 'HEALTH' 'Checking installed OSR version and starting Freshworks services...' 72
    $after=Get-OsrProduct
    if ($after.Version -ne $target.Version) { throw "Installed version $($after.Version) does not match MSI version $($target.Version)." }
    Start-OsrServices
    Update-Progress 'ACCEPTANCE' 'Windows services running. Waiting for manual functional validation.' 83
    Invoke-ManualAcceptance
} catch {
    $err=$_.Exception.Message
    Add-Log "ERROR: $err"
    if ($Mode -eq 'Deploy' -and $stoppedForBackup -and -not $deploymentStarted) {
        try { Start-OsrServices; Add-Log 'Services restarted after pre-upgrade failure.' } catch { Add-Log "Service restart failed: $($_.Exception.Message)" }
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
}