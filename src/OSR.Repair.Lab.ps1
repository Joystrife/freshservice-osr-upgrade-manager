#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$MsiPath = 'C:\OSR-Lab\FO-OSR.msi',
    [string]$BackupRoot = 'C:\OSR-Lab\backups',
    [string]$ExpectedComputerName,
    [switch]$CheckpointConfirmed,
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'OSR.Upgrade.Core.psm1') -Force

# This entry point never invokes the production upgrade worker or edits its gates.
$product = Get-OsrProduct
$package = Get-OsrMsiMetadata -Path $MsiPath
[void](Assert-OsrPackageAuthenticity -Path $package.Path)
Assert-OsrSameVersionRepair -InstalledProduct $product -Package $package
$source = Get-OsrInstallDirectory
$services = @(Get-OsrServiceRecords)
Assert-OsrSafePath -InstallDirectory $source -BackupRoot $BackupRoot
$system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
if ($system.Manufacturer -ne 'Microsoft Corporation' -or $system.Model -ne 'Virtual Machine') {
    throw 'This lab entry point requires a Microsoft Hyper-V guest.'
}
if (-not $Execute) {
    [pscustomobject]@{
        Mode='DRY_RUN'; ComputerName=$env:COMPUTERNAME
        InstalledVersion=[string]$product.Version; PackageVersion=[string]$package.Version
        ProductCode=$product.ProductCode; InstallDirectory=$source
        BackupRoot=$BackupRoot; PlannedOperation='Same-version MSI repair (/fomus)'
        ServiceStates=@($services | Select-Object DisplayName,State)
        BackupCreated=$false; RestorationValidated=$false; CrossVersionRollbackValidated=$false
    }
    return
}
if (-not (Test-OsrAdministrator)) { throw 'Live lab repair requires Administrator privileges.' }
if ([string]::IsNullOrWhiteSpace($ExpectedComputerName) -or $ExpectedComputerName -ine $env:COMPUTERNAME) {
    throw 'Explicitly bind the live lab test to this guest using ExpectedComputerName.'
}
if (-not $CheckpointConfirmed) { throw 'Confirm an existing host-side baseline checkpoint before live lab repair.' }
if ($BackupRoot -notmatch '^[A-Za-z]:\\') { throw 'The lab backup root must be an absolute local path.' }
foreach ($pathToCheck in @($source,$BackupRoot)) {
    $ancestor = [IO.Path]::GetFullPath($pathToCheck)
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Source and backup paths must not traverse reparse points.'
            }
        }
        $ancestor = Split-Path -Path $ancestor -Parent
    }
}
foreach ($service in $services) {
    if ($service.State -ne 'Running') { throw 'Both Freshworks services must be running before the lab test.' }
}
$runDirectory = Join-Path $BackupRoot ('Repair-' + [guid]::NewGuid().ToString('N'))
Assert-OsrSafePath -InstallDirectory $source -BackupRoot $runDirectory
$sourceFull = [IO.Path]::GetFullPath($source).TrimEnd('\')
$backupFull = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
if ($sourceFull.StartsWith($backupFull+'\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'The backup root must not contain the installation tree.'
}

function Get-LabFileInventory([string]$Root) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($rootFull)
    while ($pending.Count) {
        foreach ($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction Stop)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not supported by this lab capture.' }
            if ($item.PSIsContainer) { $pending.Push($item.FullName); continue }
            [pscustomobject]@{
                Path=$item.FullName.Substring($rootFull.Length+1)
                Length=$item.Length
                SHA256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
                SourceSDDL=(Get-Acl -LiteralPath $item.FullName).Sddl
            }
        }
    }
}
function Assert-LabInventoryEqual([object[]]$Expected,[object[]]$Actual) {
    if ($Expected.Count -eq 0 -or $Expected.Count -ne $Actual.Count) { throw 'Backup file count is empty or does not match.' }
    $index = @{}
    foreach ($file in $Actual) { $index[$file.Path] = $file }
    foreach ($file in $Expected) {
        if (-not $index.ContainsKey($file.Path) -or $index[$file.Path].Length -ne $file.Length -or $index[$file.Path].SHA256 -ne $file.SHA256) {
            throw 'Backup verification failed: a file is missing or changed.'
        }
    }
}

# Protect every newly created directory before writing configuration data.
$createdRun = New-Item -Path $runDirectory -ItemType Directory -ErrorAction Stop
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
foreach ($sidText in @('S-1-5-18','S-1-5-32-544')) {
    $sid = New-Object Security.Principal.SecurityIdentifier($sidText)
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    [void]$acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $createdRun.FullName -AclObject $acl -ErrorAction Stop
$effectiveAcl = Get-Acl -LiteralPath $createdRun.FullName
if (-not $effectiveAcl.AreAccessRulesProtected) { throw 'Backup permissions are not protected.' }
$reportPath = Join-Path $runDirectory 'report.json'
$report = [ordered]@{
    Operation='LAB_SAME_VERSION_REPAIR'; Version=[string]$product.Version
    Status='STARTED'; BackupIntegrity='NOT_VERIFIED'; RestorationValidated=$false
    CrossVersionRollbackValidated=$false; MsiExitCode=$null; Error=$null; RestartError=$null
}
$servicesMayBeStopped = $false
try {
    $servicesMayBeStopped = $true
    Stop-OsrServices
    $before = @(Get-LabFileInventory -Root $source)
    $filesPath = Join-Path $runDirectory 'files'
    [void](New-Item -Path $filesPath -ItemType Directory -ErrorAction Stop)
    foreach ($file in $before) {
        $destination = Join-Path $filesPath $file.Path
        [void](New-Item -Path (Split-Path $destination -Parent) -ItemType Directory -Force -ErrorAction Stop)
        # Keep inherited protected backup permissions; do not copy source ACLs.
        Copy-Item -LiteralPath (Join-Path $source $file.Path) -Destination $destination -ErrorAction Stop
    }
    $afterCapture = @(Get-LabFileInventory -Root $source)
    $captured = @(Get-LabFileInventory -Root $filesPath)
    Assert-LabInventoryEqual -Expected $before -Actual $afterCapture
    Assert-LabInventoryEqual -Expected $before -Actual $captured
    $savedMsi = Join-Path $runDirectory 'original-FO-OSR.msi'
    Copy-Item -LiteralPath $package.Path -Destination $savedMsi -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $savedMsi -Algorithm SHA256).Hash -ne $package.Sha256) { throw 'Saved MSI integrity check failed.' }
    [pscustomobject]@{Version=[string]$product.Version;Files=$before;Services=$services | Select-Object Name,DisplayName,State,StartMode;Scope='Installation files only; empty directories, directory ACLs, registry and external dependencies not captured'} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDirectory 'manifest.json') -Encoding UTF8
    $report.BackupIntegrity = 'INSTALLATION_TREE_VERIFIED'
    # Use the verified saved installer to avoid changes to the original after capture.
    $code = Invoke-OsrMsi -Operation Repair -Target $savedMsi -ExpectedSha256 $package.Sha256 -LogFile (Join-Path $runDirectory 'repair-msi.log')
    $report.MsiExitCode = $code
    if ($code -eq 3010) { throw 'Repair requires a reboot; no automatic reboot was requested. Operator review required.' }
    if ($code -ne 0) { throw ('MSI repair failed with exit code ' + $code) }
    Assert-OsrSameVersionRepair -InstalledProduct (Get-OsrProduct) -Package $package
    $report.Status = 'REPAIR_COMPLETED_REQUIRES_REVIEW'
} catch {
    $report.Status = 'FAILED_REQUIRES_OPERATOR'
    $report.Error = $_.Exception.Message
} finally {
    if ($servicesMayBeStopped) {
        try { Start-OsrServices } catch {
            $report.RestartError = $_.Exception.Message
            $report.Status = 'FAILED_REQUIRES_OPERATOR'
        }
    }
    $report.FinishedAt = [DateTime]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Output ('Protected lab report: ' + $reportPath)
    Write-Output ('Status: ' + $report.Status)
}
if ($report.Status -eq 'FAILED_REQUIRES_OPERATOR') { throw 'Lab repair was not validated. Review the protected report; no automatic restore was attempted.' }
