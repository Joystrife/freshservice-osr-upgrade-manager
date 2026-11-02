#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$module = Import-Module (Join-Path $root 'src\OSR.Upgrade.Core.psm1') -Force -PassThru

& $module {
    $script:installedFixture = [pscustomobject]@{Version=[version]'2.5.0.0';ProductCode='{11111111-2222-3333-4444-555555555555}'}
    $script:packageFixture = [pscustomobject]@{Version=[version]'2.5.0.0';ProductCode='{11111111-2222-3333-4444-555555555555}'}
    $script:isAdminFixture = $true
    $script:trustFixture = $true
    $script:processCallsFixture = 0
    $script:argumentsFixture = ''
    function Test-OsrAdministrator { return $script:isAdminFixture }
    function Get-OsrProduct { return $script:installedFixture }
    function Get-OsrMsiMetadata { param($Path) return $script:packageFixture }
    function Assert-OsrPackageAuthenticity { param($Path,$ExpectedSha256) if (-not $script:trustFixture) { throw 'Untrusted fixture package.' } }
    function Start-Process {
        param($FilePath,$ArgumentList,[switch]$PassThru,[switch]$Wait,$ErrorAction)
        if ($FilePath -ne 'msiexec.exe') { throw 'Unexpected process.' }
        $script:processCallsFixture++
        $script:argumentsFixture = $ArgumentList
        return [pscustomobject]@{ExitCode=3010}
    }
    function Assert-RepairBlocked([string]$Label) {
        $callsBefore = $script:processCallsFixture
        $blocked = $false
        try { Invoke-OsrMsi -Operation Repair -Target 'C:\Synthetic\OSR.msi' -LogFile 'C:\Synthetic\repair.log' | Out-Null } catch { $blocked=$true }
        if (-not $blocked -or $script:processCallsFixture -ne $callsBefore) { throw ('Repair was not blocked before process launch: ' + $Label) }
        Write-Host ('PASS: repair blocked before process launch - ' + $Label)
    }
    $exitCode = Invoke-OsrMsi -Operation Repair -Target 'C:\Synthetic\OSR.msi' -LogFile 'C:\Synthetic\repair.log'
    if ($exitCode -ne 3010 -or $script:processCallsFixture -ne 1 -or
        $script:argumentsFixture -notmatch '^/fomus ' -or $script:argumentsFixture -notmatch '/norestart' -or
        $script:argumentsFixture -notmatch '/qn') { throw 'Repair command or reboot-required exit code handling changed.' }
    Write-Host 'PASS: trusted same-product repair command and reboot-required exit code'
    foreach ($version in @('2.4.0.0','2.6.0.0')) {
        $script:packageFixture.Version = [version]$version
        Assert-RepairBlocked ('different version ' + $version)
    }
    $script:packageFixture.Version = [version]'2.5.0.0'
    $script:packageFixture.ProductCode = '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}'
    Assert-RepairBlocked 'different product identity'
    $script:packageFixture.ProductCode = $script:installedFixture.ProductCode
    $script:trustFixture = $false
    Assert-RepairBlocked 'untrusted MSI'
    $script:trustFixture = $true
    $script:isAdminFixture = $false
    Assert-RepairBlocked 'non-administrator'
    $script:isAdminFixture = $true
    $script:installedFixture.ProductCode = ''
    Assert-RepairBlocked 'missing installed ProductCode'
    $null = Invoke-OsrMsi -Operation Install -Target 'C:\Synthetic\OSR.msi' -LogFile 'C:\Synthetic\install.log'
    if ($script:argumentsFixture -notmatch '^/i ') { throw 'Install verb changed.' }
    $null = Invoke-OsrMsi -Operation Uninstall -Target '{11111111-2222-3333-4444-555555555555}' -LogFile 'C:\Synthetic\uninstall.log'
    if ($script:argumentsFixture -notmatch '^/x ') { throw 'Uninstall verb changed.' }
    Write-Host 'PASS: existing install/uninstall verbs preserved'
}
Remove-Module $module.Name -Force

# Execute only the default/read-only and rejected paths with synthetic discovery.
& {
    param($LabScript)
    function Import-Module { param($Name,[switch]$Force) }
    function Get-OsrProduct { [pscustomobject]@{Version=[version]'2.5.0.0';ProductCode='{11111111-2222-3333-4444-555555555555}'} }
    function Get-OsrMsiMetadata { param($Path) [pscustomobject]@{Path=$Path;Version=[version]'2.5.0.0';ProductCode='{11111111-2222-3333-4444-555555555555}'} }
    function Assert-OsrPackageAuthenticity { param($Path) }
    function Assert-OsrSameVersionRepair { param($InstalledProduct,$Package) }
    function Get-OsrInstallDirectory { 'C:\SyntheticOSR' }
    function Get-OsrServiceRecords { [pscustomobject]@{DisplayName='Synthetic service';State='Running'} }
    function Assert-OsrSafePath { param($InstallDirectory,$BackupRoot) }
    function Get-CimInstance { param($ClassName,$ErrorAction) [pscustomobject]@{Manufacturer='Microsoft Corporation';Model='Virtual Machine'} }
    function Test-OsrAdministrator { $true }
    function New-Item { throw 'Unexpected filesystem write.' }
    function Copy-Item { throw 'Unexpected file copy.' }
    function Set-Content { throw 'Unexpected report write.' }
    function Stop-OsrServices { throw 'Unexpected service stop.' }
    function Start-OsrServices { throw 'Unexpected service start.' }
    function Invoke-OsrMsi { throw 'Unexpected MSI operation.' }
    function Start-Process { throw 'Unexpected process.' }
    $plan = & $LabScript
    if ($plan.Mode -ne 'DRY_RUN' -or $plan.BackupCreated -or $plan.RestorationValidated -or $plan.CrossVersionRollbackValidated) { throw 'Default plan claimed execution or recovery.' }
    Write-Host 'PASS: default lab run is read-only and does not claim recovery'
    $blocked = $false
    try { & $LabScript -Execute | Out-Null } catch {
        if ($_.Exception.Message -like '*ExpectedComputerName*') { $blocked=$true } else { throw }
    }
    if (-not $blocked) { throw 'Live execution requires an explicit guest identity.' }
    $blocked = $false
    try { & $LabScript -Execute -ExpectedComputerName $env:COMPUTERNAME | Out-Null } catch {
        if ($_.Exception.Message -like '*baseline checkpoint*') { $blocked=$true } else { throw }
    }
    if (-not $blocked) { throw 'Live execution requires checkpoint confirmation.' }
    Write-Host 'PASS: missing guest binding or checkpoint confirmation blocks live execution before writes'
} (Join-Path $root 'src\OSR.Repair.Lab.ps1')

# Test the actual inventory comparison without touching an installed application.
$tokens = $null
$parseErrors = $null
$labAst = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'src\OSR.Repair.Lab.ps1'),[ref]$tokens,[ref]$parseErrors)
$comparisonDefinition = $labAst.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-LabInventoryEqual'
},$true)
if ($null -eq $comparisonDefinition) { throw 'Inventory comparison was not found.' }
. ([scriptblock]::Create($comparisonDefinition.Extent.Text))
$referenceFiles = @([pscustomobject]@{Path='osr\config\fixture.conf';Length=10;SHA256=('A'*64)})
Assert-LabInventoryEqual -Expected $referenceFiles -Actual $referenceFiles
foreach ($invalidFiles in @(
    @{Label='missing file';Files=@()},
    @{Label='additional file';Files=@($referenceFiles[0], [pscustomobject]@{Path='unexpected';Length=1;SHA256=('A'*64)})},
    @{Label='modified content';Files=@([pscustomobject]@{Path=$referenceFiles[0].Path;Length=10;SHA256=('B'*64)})},
    @{Label='modified length';Files=@([pscustomobject]@{Path=$referenceFiles[0].Path;Length=11;SHA256=('A'*64)})},
    @{Label='renamed file';Files=@([pscustomobject]@{Path='other.conf';Length=10;SHA256=('A'*64)})}
)) {
    $blocked = $false
    try { Assert-LabInventoryEqual -Expected $referenceFiles -Actual $invalidFiles.Files } catch { $blocked=$true }
    if (-not $blocked) { throw ('Invalid inventory was accepted: ' + $invalidFiles.Label) }
    Write-Host ('PASS: inventory rejects ' + $invalidFiles.Label)
}
