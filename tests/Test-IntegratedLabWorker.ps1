#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\OSR.Upgrade.Core.psm1') -Force
Import-Module (Join-Path $root 'src\OSR.Recovery.LabFiles.psm1') -Force
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('OsrWorkerTest-' + [guid]::NewGuid().ToString('N'))
$workerText = [IO.File]::ReadAllText((Join-Path $root 'src\OSR.Upgrade.Worker.ps1'))
$tokens=$null; $parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseInput($workerText,[ref]$tokens,[ref]$parseErrors)
$decision=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Await-Decision'},$true)
# Only replace the human decision boundary. All worker branches and real file
# snapshot/restore functions execute; OSR discovery, services and MSI are mocked.
$replacement=@'
function Await-Decision {
    param([string]$Question,[int]$Percent,[string]$Stage='OPERATOR_TEST')
    if ($fixture.Decisions.Count -eq 0) { throw 'No synthetic operator decision available.' }
    return $fixture.Decisions.Dequeue()
}
'@
$instrumented=$workerText.Substring(0,$decision.Extent.StartOffset)+$replacement+$workerText.Substring($decision.Extent.EndOffset)
function Invoke-FixtureRun {
    param([string]$Name,[string[]]$Answers=@(),[string]$Operation='LabRepair',[string]$ExpectedStatus,
        [hashtable]$Overrides=@{},[hashtable]$Settings=@{},[string]$Mode='Deploy',[switch]$LongRunDirectory)
    $caseRoot=Join-Path $testRoot $Name
    $source=Join-Path $caseRoot 'installation'
    [void](New-Item -Path (Join-Path $source 'osr\config') -ItemType Directory -Force)
    $configFile=Join-Path $source 'osr\config\fixture.conf'
    Set-Content -LiteralPath $configFile -Value 'before repair'
    $msi=Join-Path $caseRoot 'fixture.msi'
    Set-Content -LiteralPath $msi -Value 'Synthetic text only; not an installable MSI.'
    $recoveryMsi=Join-Path $caseRoot 'recovery.msi'
    Set-Content -LiteralPath $recoveryMsi -Value 'Synthetic previous-version media; not installable.'
    $run=Join-Path $caseRoot 'run'
    if ($LongRunDirectory) { $run=Join-Path $caseRoot ('r'*(225-$caseRoot.Length-1)) }
    $fixture=@{
        Source=$source; Msi=$msi; RecoveryMsi=$recoveryMsi; Run=$run; Version=[version]'2.5.0.0'; TargetVersion=[version]'2.5.0.0'
        ProductCode='{11111111-2222-3333-4444-555555555555}'; TargetCode='{11111111-2222-3333-4444-555555555555}'
        Decisions=(New-Object 'System.Collections.Generic.Queue[string]'); Calls=(New-Object 'System.Collections.Generic.List[string]')
        Running=$true; ExitCode=0; TamperBackup=$false; StopFailure=$false; StartFailure=$false
        Manufacturer='Microsoft Corporation'; Model='Virtual Machine'
        LegacyCopyAllowed=$false
    }
    foreach ($answer in $Answers) { $fixture.Decisions.Enqueue($answer) }
    foreach ($key in $Overrides.Keys) { $fixture[$key]=$Overrides[$key] }
    $cfg=@{
        MsiPath=$msi; PreviousMsiPath=$recoveryMsi; InstallDirectory=$source; BackupRoot=$run
        ExpectedSha256=''; PreviousSha256=''; Questions=@('Inspect synthetic lab state')
        MaintenanceApproved=$true; RecoveryProcedureValidated=$false
        LabCheckpointConfirmed=$true; LabExpectedComputerName=$env:COMPUTERNAME
    }
    foreach ($key in $Settings.Keys) { $cfg[$key]=$Settings[$key] }
    $cfgPath=Join-Path $caseRoot 'settings.json'
    $cfg | ConvertTo-Json | Set-Content -LiteralPath $cfgPath -Encoding UTF8
    $initialSecurity=Get-OsrLabTreeInventory $source
    $workerPath=Join-Path $caseRoot 'worker.ps1'
    [IO.File]::WriteAllText($workerPath,$instrumented,[Text.Encoding]::UTF8)
    & {
        param($Worker,$ConfigPath,$RunPath,$SelectedOperation,$RunMode)
        function Import-Module { param($Name,[switch]$Force) }
        function Test-OsrAdministrator { $true }
        function Protect-OsrLabDirectory { param($Path) } # Fixtures contain no secrets; test current user may not be admin.
        function Get-CimInstance { param($ClassName,$ErrorAction) [pscustomobject]@{Manufacturer=$fixture.Manufacturer;Model=$fixture.Model} }
        function Get-OsrProduct { [pscustomobject]@{Version=$fixture.Version;ProductCode=$fixture.ProductCode} }
        function Get-OsrInstallDirectory { $fixture.Source }
        function Get-OsrServiceRecords {
            foreach ($name in @('Orchestration Server','Orchestration Server - WinRM_SSH')) {
                [pscustomobject]@{Name=$name;DisplayName=$name;State=$(if($fixture.Running){'Running'}else{'Stopped'});StartMode='Auto';StartName='Synthetic';PathName='Synthetic'}
            }
        }
        function Get-OsrMsiMetadata {
            param($Path)
            $version=if($Path -eq $fixture.RecoveryMsi){$fixture.Version}else{$fixture.TargetVersion}
            [pscustomobject]@{Path=$Path;Version=$version;ProductCode=$fixture.TargetCode;Sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
        }
        function Assert-OsrPackageAuthenticity { param($Path,$ExpectedSha256) [pscustomobject]@{Signature='Synthetic';VendorSignature=$true} }
        function Stop-OsrServices {
            $fixture.Calls.Add('Stop')
            $fixture.Running=$false
            if ($fixture.StopFailure) { throw 'Synthetic stop failure' }
        }
        function Start-OsrServices {
            $fixture.Calls.Add('Start')
            if ($fixture.StartFailure) { throw 'Synthetic restart failure' }
            $fixture.Running=$true
        }
        function Invoke-OsrMsi {
            param($Operation,$Target,$LogFile,$ExpectedSha256,[switch]$Interactive)
            $fixture.Calls.Add('MSI:'+ $Operation)
            if ($Operation -eq 'Install') { $fixture.Version=$fixture.TargetVersion }
            Set-Content -LiteralPath (Join-Path $fixture.Source 'osr\config\fixture.conf') -Value 'after simulated repair'
            Set-Content -LiteralPath (Join-Path $fixture.Source 'extra.tmp') -Value 'new file'
            if ($fixture.TamperBackup) { Set-Content -LiteralPath (Join-Path $fixture.Run 'recovery-point\files\osr\config\fixture.conf') -Value 'tampered' }
            return $fixture.ExitCode
        }
        function Invoke-OsrRobocopy {
            param($Source,$Destination,$LogFile,[switch]$Mirror)
            if (-not $fixture.LegacyCopyAllowed) { throw 'Unexpected legacy copy in a lab test.' }
            [void](New-Item -Path $Destination -ItemType Directory -Force)
            Get-ChildItem -LiteralPath $Source -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force }
            return 0
        }
        function Start-Process { throw 'No processes may be launched by this regression test.' }
        if ($SelectedOperation -eq 'Default') { & $Worker -Mode $RunMode -RunDirectory $RunPath -ConfigurationPath $ConfigPath }
        else { & $Worker -Mode $RunMode -RunDirectory $RunPath -ConfigurationPath $ConfigPath -Operation $SelectedOperation }
    } $workerPath $cfgPath $run $Operation $Mode
    $report=Get-Content -LiteralPath (Join-Path $run 'report.json') -Raw | ConvertFrom-Json
    if ($report.Status -ne $ExpectedStatus) {
        Write-Host ('Synthetic ACL baseline: '+($initialSecurity | ConvertTo-Json -Depth 5 -Compress))
        Write-Host ('Synthetic ACL actual: '+((Get-OsrLabTreeInventory $source) | ConvertTo-Json -Depth 5 -Compress))
        $activity=Get-Content -LiteralPath (Join-Path $run 'activity.log') -Raw
        throw ("{0}: expected {1}, got {2}. {3}" -f $Name,$ExpectedStatus,$report.Status,$activity)
    }
    if ($report.CrossVersionRollbackValidated) { throw 'Lab test promoted cross-version recovery.' }
    if ($ExpectedStatus -eq 'LAB_FILES_RESTORED') {
        if (-not $report.LabFileRestoreVerified -or -not $fixture.Running -or
            (Get-Content -LiteralPath $configFile -Raw).Trim() -ne 'before repair' -or
            (Test-Path -LiteralPath (Join-Path $source 'extra.tmp'))) { throw 'Actual fixture files were not restored.' }
    }
    if ($ExpectedStatus -in @('FAILED','PREFLIGHT_PASSED') -and $fixture.Calls.Count) { throw 'Preflight controlled a service or invoked MSI.' }
    if ($LongRunDirectory -and (Get-Content -LiteralPath (Join-Path $run 'activity.log') -Raw) -notmatch 'shorter recovery storage') { throw 'Path budget was not the cause of rejection.' }
    if ($Name -eq 'upgrade-recovery-gate' -and (Get-Content -LiteralPath (Join-Path $run 'activity.log') -Raw) -notmatch 'independently tested') { throw 'The original recovery procedure gate was not reached.' }
    if ($ExpectedStatus -eq 'LAB_REPAIR_ACCEPTED' -and ($fixture.Calls -notcontains 'MSI:Repair' -or -not $fixture.Running)) { throw 'Lab acceptance did not execute the repair path.' }
    if ($Operation -eq 'LabRepair' -and ($fixture.Calls -contains 'MSI:Install' -or $fixture.Calls -contains 'MSI:Uninstall')) { throw 'Lab test used install/uninstall instead of repair.' }
    if ($ExpectedStatus -eq 'ACCEPTED' -and $fixture.Calls -notcontains 'MSI:Install') { throw 'Authorized upgrade did not use its original MSI install path.' }
    Write-Host ('PASS: integrated worker - ' + $Name + ' -> ' + $report.Status)
}
try {
    Invoke-FixtureRun 'accept' -Answers YES -ExpectedStatus 'LAB_REPAIR_ACCEPTED'
    Invoke-FixtureRun 'reject-and-restore' -Answers NO,YES,YES -ExpectedStatus 'LAB_FILES_RESTORED'
    Invoke-FixtureRun 'decline-restore' -Answers NO,NO -ExpectedStatus 'DEPLOYED_NOT_VALIDATED'
    Invoke-FixtureRun 'msi-failure-restore' -Answers YES,YES -Overrides @{ExitCode=1603} -ExpectedStatus 'LAB_FILES_RESTORED'
    Invoke-FixtureRun 'tampered-backup' -Answers NO,YES -Overrides @{TamperBackup=$true} -ExpectedStatus 'RECOVERY_FAILED'
    Invoke-FixtureRun 'stop-failure' -Overrides @{StopFailure=$true} -ExpectedStatus 'PRE_DEPLOY_FAILED'
    Invoke-FixtureRun 'restart-failure' -Answers YES -Overrides @{StartFailure=$true} -ExpectedStatus 'RECOVERY_FAILED'
    Invoke-FixtureRun 'wrong-lab-version' -Overrides @{TargetVersion=[version]'2.6.0.0'} -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'wrong-product' -Overrides @{TargetCode='{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}'} -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'physical-host' -Overrides @{Model='Physical fixture'} -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'wrong-computer' -Settings @{LabExpectedComputerName='not-this-guest'} -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'missing-checkpoint' -Settings @{LabCheckpointConfirmed=$false} -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'string-checkpoint' -Settings @{LabCheckpointConfirmed='false'} -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'missing-approval' -Settings @{MaintenanceApproved=$false} -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'preflight' -Mode Preflight -ExpectedStatus 'PREFLIGHT_PASSED'
    Invoke-FixtureRun 'long-path-preflight' -Mode Preflight -LongRunDirectory -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'long-path-deploy' -LongRunDirectory -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'upgrade-same-version' -Operation Upgrade -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'upgrade-older-version' -Operation Upgrade -Overrides @{TargetVersion=[version]'2.4.0.0'} -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'default-remains-upgrade' -Operation Default -ExpectedStatus 'FAILED'
    # A newer trusted package still requires the original independent recovery gate.
    Invoke-FixtureRun 'upgrade-recovery-gate' -Operation Upgrade -Overrides @{Version=[version]'2.4.0.0'} -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'upgrade-recovery-malformed' -Operation Upgrade -Overrides @{Version=[version]'2.4.0.0'} -Settings @{RecoveryProcedureValidated='false'} -ExpectedStatus 'FAILED'
    Invoke-FixtureRun 'authorized-upgrade' -Operation Upgrade -Overrides @{Version=[version]'2.4.0.0';LegacyCopyAllowed=$true} -Settings @{RecoveryProcedureValidated=$true} -Answers YES -ExpectedStatus 'ACCEPTED'
} finally {
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notmatch '^OsrWorkerTest-[a-f0-9]{32}$') { throw 'Unsafe worker fixture cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
