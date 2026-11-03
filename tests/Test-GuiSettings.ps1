#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\OSR.Gui.Settings.psm1') -Force
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('OsrSettingsTest-'+[guid]::NewGuid().ToString('N'))
$path=Join-Path $testRoot 'preferences\settings.dat'
function Assert-Rejected([scriptblock]$Action,[string]$Label){
    $failed=$false
    try{& $Action | Out-Null}catch{$failed=$true}
    if(-not $failed){throw ('Expected rejection: '+$Label)}
    Write-Host ('PASS: settings rejection - '+$Label)
}
try{
    if((Read-OsrGuiSettings -Path $path).Count){throw 'Missing preferences must be empty.'}
    $settings=@{MsiPath='C:\Lab\target.msi';PreviousMsiPath='C:\Lab\original.msi';InstallDirectory='C:\Application';BackupRoot='C:\OSR\Runs';LabExpectedComputerName='synthetic-guest';DryRun=$false;MaintenanceApproved=$true;MigrationScopeApproved=$true;Operation='Replacement';Secret='must-not-persist'}
    Save-OsrGuiSettings -Settings $settings -Path $path
    $read=Read-OsrGuiSettings -Path $path
    if($read.Count -ne 5 -or $read.MsiPath -ne $settings.MsiPath -or $read.BackupRoot -ne $settings.BackupRoot){throw 'Safe preference round trip failed.'}
    $plain=[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($path),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
    if($plain -match 'must-not-persist|MigrationScopeApproved|MaintenanceApproved|DryRun|Replacement'){throw 'Unsafe fields were persisted.'}
    if([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path)).Contains('target.msi')){throw 'Preference paths were not encrypted.'}
    $acl=Get-Acl (Split-Path $path -Parent)
    if(-not $acl.AreAccessRulesProtected){throw 'Preference directory is not protected.'}
    $allowed=@([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')
    foreach($rule in $acl.Access){if($rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin $allowed){throw 'Unexpected preference access.'}}
    Save-OsrGuiSettings -Settings @{BackupRoot='C:\NewRoot'} -Path $path
    if((Read-OsrGuiSettings -Path $path).BackupRoot -ne 'C:\NewRoot' -or @(Get-ChildItem (Split-Path $path -Parent) -Filter '*.tmp').Count){throw 'Atomic update failed.'}
    Assert-Rejected {Save-OsrGuiSettings -Settings @{MsiPath="bad`nvalue"} -Path $path} 'multiline value'
    Assert-Rejected {Save-OsrGuiSettings -Settings @{MsiPath=$true} -Path $path} 'non-string value'
    Assert-Rejected {Save-OsrGuiSettings -Settings @{} -Path 'relative.dat'} 'relative storage'
    [IO.File]::WriteAllBytes($path,[byte[]]@(1,2,3))
    Assert-Rejected {Read-OsrGuiSettings -Path $path} 'corrupt encryption'
    [IO.File]::WriteAllBytes($path,(New-Object byte[] 65537))
    Assert-Rejected {Read-OsrGuiSettings -Path $path} 'oversized record'
    $badSchema=[Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes('{"SchemaVersion":2,"Values":{}}'),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes($path,$badSchema)
    Assert-Rejected {Read-OsrGuiSettings -Path $path} 'unknown schema'
    $junction=Join-Path $testRoot 'redirect'
    [void](New-Item -Path $junction -ItemType Junction -Target (Split-Path $path -Parent))
    try{Assert-Rejected {Save-OsrGuiSettings -Settings @{} -Path (Join-Path $junction 'settings.dat')} 'reparse ancestor'}finally{[IO.Directory]::Delete($junction)}
    Write-Host 'PASS: encrypted per-user path preferences, strict whitelist, protected ACL and atomic replacement'
}finally{
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notmatch '^OsrSettingsTest-[a-f0-9]{32}$'){throw 'Unsafe settings test cleanup path.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
