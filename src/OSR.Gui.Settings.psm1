#Requires -Version 5.1
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Security
$script:SettingNames=@('MsiPath','PreviousMsiPath','InstallDirectory','BackupRoot','LabExpectedComputerName')
function Get-OsrGuiSettingsPath {
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'FreshworksOSRUpgradeManager\Preferences\settings.dat'
}
function Assert-OsrSettingsPath([string]$Path){
    if($Path -notmatch '^[A-Za-z]:\\'){throw 'Preferences require an absolute local path.'}
    $current=[IO.Path]::GetFullPath($Path)
    while($current){
        if((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
            throw 'Preferences cannot traverse reparse points.'
        }
        $current=Split-Path $current -Parent
    }
}
function Select-OsrSafeSettings($Settings){
    $result=@{}
    foreach($name in $script:SettingNames){
        $value=if($Settings -is [Collections.IDictionary]){$Settings[$name]}elseif($Settings.PSObject.Properties[$name]){$Settings.$name}else{$null}
        if($null -ne $value){
            if($value -isnot [string] -or $value.Length -gt 4096 -or $value -match '[\x00\r\n]'){throw 'Invalid preference value.'}
            $result[$name]=$value
        }
    }
    return $result
}
function Read-OsrGuiSettings {
    param([string]$Path=(Get-OsrGuiSettingsPath))
    Assert-OsrSettingsPath $Path
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return @{}}
    if((Get-Item -LiteralPath $Path).Length -gt 65536){throw 'Preferences exceed the supported size.'}
    $encrypted=[IO.File]::ReadAllBytes($Path)
    $bytes=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $record=[Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
    if($record.SchemaVersion -ne 1){throw 'Unsupported preferences schema.'}
    return Select-OsrSafeSettings $record.Values
}
function Save-OsrGuiSettings {
    param([Parameter(Mandatory)]$Settings,[string]$Path=(Get-OsrGuiSettingsPath))
    Assert-OsrSettingsPath $Path
    $safe=Select-OsrSafeSettings $Settings
    $parent=Split-Path $Path -Parent
    [void][IO.Directory]::CreateDirectory($parent)
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $user=[Security.Principal.WindowsIdentity]::GetCurrent().User
    foreach($sid in @($user,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')),(New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))){
        [void]$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
    }
    [IO.Directory]::SetAccessControl($parent,$acl)
    $json=ConvertTo-Json -InputObject @{SchemaVersion=1;Values=$safe} -Depth 3 -Compress
    $bytes=[Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($json),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllBytes($temp,$bytes)
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
Export-ModuleMember -Function Get-OsrGuiSettingsPath,Read-OsrGuiSettings,Save-OsrGuiSettings
