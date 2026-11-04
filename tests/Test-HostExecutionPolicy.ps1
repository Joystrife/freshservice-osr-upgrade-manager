#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$targets = @(
    'Start-Manager.cmd',
    'src\Freshservice_OSR_Upgrade_GUI.ps1',
    'launcher\PortableLauncher.cs'
)
foreach ($relative in $targets) {
    $path = Join-Path $root $relative
    $content = [IO.File]::ReadAllText($path)
    if ($content -match '(?i)-ExecutionPolicy\s+(?:Bypass|Unrestricted|RemoteSigned|AllSigned|Restricted|Default)') {
        throw "Runtime launcher overrides the host execution policy: $relative"
    }
    Write-Host "PASS: no process execution-policy override in $relative"
}
$gui = [IO.File]::ReadAllText((Join-Path $root 'src\Freshservice_OSR_Upgrade_GUI.ps1'))
if ($gui -notmatch '-NoProfile -File' -or $gui -notmatch '-NoProfile -STA -File') {
    throw 'Expected inherited-policy worker and elevated GUI launch arguments.'
}
Write-Host 'PASS: worker and elevated GUI use inherited policy'
