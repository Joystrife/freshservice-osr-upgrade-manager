#Requires -Version 5.1
<#
.SYNOPSIS
Read-only regression tests for Windows Server Backup target selection.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\OSR.Recovery.WindowsServerBackup.psm1') -Force

function Assert-Throws {
    param([scriptblock]$Action,[string]$Label)
    $didThrow = $false
    try { & $Action | Out-Null } catch { $didThrow = $true }
    if(-not $didThrow) {throw "Expected rejection: $Label"}
    Write-Host "PASS: rejected $Label"
}

$external = Test-OsrWindowsBackupTarget -BackupTarget 'E:' -SystemDrive 'C:' -OsrDrive 'C:'
if($external.Kind -ne 'LOCAL_VOLUME' -or $external.Target -ne 'E:') {throw 'External volume classification failed.'}
Write-Host 'PASS: external fixed-volume syntax'

$unc = Test-OsrWindowsBackupTarget -BackupTarget '\\backupserver\osr-backups' -SystemDrive 'C:' -OsrDrive 'D:'
if($unc.Kind -ne 'NETWORK_SHARE') {throw 'UNC target classification failed.'}
Write-Host 'PASS: UNC share syntax'

Assert-Throws -Label 'target equals operating-system volume' -Action {
    Test-OsrWindowsBackupTarget -BackupTarget 'c:' -SystemDrive 'C:' -OsrDrive 'D:'
}
Assert-Throws -Label 'target equals OSR source volume' -Action {
    Test-OsrWindowsBackupTarget -BackupTarget 'D:\' -SystemDrive 'C:' -OsrDrive 'D:'
}
Assert-Throws -Label 'relative target' -Action {
    Test-OsrWindowsBackupTarget -BackupTarget '.\backup' -SystemDrive 'C:' -OsrDrive 'D:'
}
Assert-Throws -Label 'nested local directory' -Action {
    Test-OsrWindowsBackupTarget -BackupTarget 'E:\Backups' -SystemDrive 'C:' -OsrDrive 'D:'
}
Assert-Throws -Label 'UNC path deeper than the share root' -Action {
    Test-OsrWindowsBackupTarget -BackupTarget '\\server\share\nested' -SystemDrive 'C:' -OsrDrive 'D:'
}

$plan = Get-OsrWindowsBackupPlan -BackupTarget 'E:' -SystemDrive 'C:' -OsrDrive 'D:'
if($plan.CommandArguments -notcontains '-allCritical' -or
    $plan.CommandArguments -notcontains '-include:D:' -or
    $plan.CommandArguments -notcontains '-backupTarget:E:') {
    throw 'The backup preview omitted the source volumes or the destination.'
}
if($plan.WindowsBackupPrepared -or $plan.RestorationValidated) {
    throw 'Preview must never claim a completed backup or verified restoration.'
}
Write-Host 'PASS: backup plan includes system and separate OSR volume and does not claim execution'
Write-Host 'PASS: Windows Server Backup provider regression tests'
