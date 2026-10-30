#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
Read-only Windows Server Backup capability and recovery planning provider.
.DESCRIPTION
This module DOES NOT create backups, stop services, or restore a system.
It detects Windows facilities and prepares a command preview for an operator.
A Windows Server Backup backup is NOT proof of successful bare-metal recovery.
#>

function Test-OsrWindowsBackupTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupTarget,
        [Parameter(Mandatory)][string]$SystemDrive,
        [Parameter(Mandatory)][string]$OsrDrive
    )
    $target = $BackupTarget.Trim().TrimEnd('\')
    $sys = $SystemDrive.Trim().TrimEnd('\')
    $osr = $OsrDrive.Trim().TrimEnd('\')
    if ($sys -notmatch '^[A-Za-z]:$' -or $osr -notmatch '^[A-Za-z]:$') {
        throw 'System and OSR source volumes must have conventional Windows drive letters.'
    }
    if ($target -match '^[A-Za-z]:$') {
        $target = $target.ToUpperInvariant()
        if ($target -ieq $sys -or $target -ieq $osr) {
            throw 'The backup target must not be the Windows system volume or the OSR source volume.'
        }
        return [pscustomobject]@{Target=$target;Kind='LOCAL_VOLUME';Valid=$true}
    }
    # Accept only a UNC share root, never an arbitrary relative path or a URI.
    if ($target -match '^\\\\[^\\/]+\\[^\\/]+$') {
        return [pscustomobject]@{Target=$target;Kind='NETWORK_SHARE';Valid=$true}
    }
    throw 'Backup target must be a separate drive (for example E:) or a UNC share (for example \\server\backup).'
}

function Get-OsrWindowsBackupCapability {
    [CmdletBinding()]
    param([string]$InstallDirectory)
    $windowsDrive = [string]$env:SystemDrive
    if (-not $windowsDrive -or $windowsDrive -notmatch '^[A-Za-z]:$') {
        $windowsDrive = [IO.Path]::GetPathRoot([Environment]::SystemDirectory).TrimEnd('\')
    }
    $sourceDrive = $windowsDrive
    if ($InstallDirectory -and $InstallDirectory -match '^[A-Za-z]:\\') {
        $sourceDrive = $InstallDirectory.Substring(0,2)
    }
    $wbadmin = $null
    try { $wbadmin = Get-Command wbadmin.exe -ErrorAction SilentlyContinue } catch {}
    $featureState = 'UNKNOWN'
    try {
        $getFeature = Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue
        if ($getFeature) {
            $feature = Get-WindowsFeature -Name Windows-Server-Backup -ErrorAction Stop
            if ($null -ne $feature) {
                $featureState = if ($feature.Installed) { 'INSTALLED' } else { 'NOT_INSTALLED' }
            }
        }
    } catch {
        $featureState = 'UNKNOWN'
    }
    $candidates = @()
    try {
        $disks = @(Get-CimInstance Win32_LogicalDisk -ErrorAction Stop |
            Where-Object { $_.DriveType -eq 3 -and $_.DeviceID -match '^[A-Za-z]:$' })
        $candidates = @(
            foreach ($disk in $disks) {
                $id = [string]$disk.DeviceID
                if ($id -ieq $windowsDrive -or $id -ieq $sourceDrive) { continue }
                [pscustomobject]@{
                    Drive = $id
                    FreeBytes = [uint64]$disk.FreeSpace
                    SizeBytes = [uint64]$disk.Size
                    VerifiedBackupDestination = $false
                }
            }
        )
    } catch { $candidates = @() }
    $present = $null -ne $wbadmin
    $status = if ($featureState -eq 'NOT_INSTALLED') {
        'FEATURE_NOT_INSTALLED'
    } elseif (-not $present) {
        'BACKUP_COMMAND_NOT_FOUND'
    } elseif ($featureState -eq 'INSTALLED') {
        'BACKUP_FEATURE_AVAILABLE'
    } else {
        'BACKUP_COMMAND_DETECTED_FEATURE_UNVERIFIED'
    }
    return [pscustomobject]@{
        Provider = 'WINDOWS_SERVER_BACKUP'
        Status = $status
        CommandAvailable = [bool]$present
        WindowsFeature = $featureState
        SystemDrive = $windowsDrive.ToUpperInvariant()
        OsrDrive = $sourceDrive.ToUpperInvariant()
        CandidateTargets = @($candidates)
        CandidateTargetCount = @($candidates).Count
        CanCreateBackupNow = $false
        RecoveryMode = 'WINRE_OR_EXTERNAL_RECOVERY_CONTROLLER'
        FullSystemRestoreAvailableInRunningWindows = $false
        Explanation = 'Read-only detection only. Candidate disks are not verified backup targets. A compatible backup and an independently tested restore procedure are required before a live upgrade.'
    }
}

function Get-OsrWindowsBackupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupTarget,
        [Parameter(Mandatory)][string]$SystemDrive,
        [Parameter(Mandatory)][string]$OsrDrive
    )
    $checked = Test-OsrWindowsBackupTarget -BackupTarget $BackupTarget -SystemDrive $SystemDrive -OsrDrive $OsrDrive
    $args = New-Object 'System.Collections.Generic.List[string]'
    foreach($s in @('start','backup',('-backupTarget:' + $checked.Target),'-allCritical','-vssCopy','-quiet')) {
        $args.Add($s)
    }
    if ($SystemDrive.TrimEnd('\') -ine $OsrDrive.TrimEnd('\')) {
        $args.Add('-include:' + $OsrDrive.TrimEnd('\').ToUpperInvariant())
    }
    $preview = 'wbadmin.exe ' + (($args.ToArray() | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }) -join ' ')
    return [pscustomobject]@{
        Provider = 'WINDOWS_SERVER_BACKUP'
        Target = $checked.Target
        TargetKind = $checked.Kind
        CommandArguments = @($args.ToArray())
        CommandPreview = $preview
        WindowsBackupPrepared = $false
        RestorationValidated = $false
        RecoveryMode = 'WINRE_OR_EXTERNAL_RECOVERY_CONTROLLER'
        Note = 'Command preview only. No backup is executed by this provider in this release.'
    }
}

Export-ModuleMember -Function Get-OsrWindowsBackupCapability,Get-OsrWindowsBackupPlan,Test-OsrWindowsBackupTarget
