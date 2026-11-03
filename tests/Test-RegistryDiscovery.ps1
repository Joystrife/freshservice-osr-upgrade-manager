#Requires -Version 5.1
<#
.SYNOPSIS
Regression tests for OSR registry detection when uninstall entries omit optional properties.
.DESCRIPTION
Runs without an installed OSR, Administrator rights, or any registry writes.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\OSR.Upgrade.Core.psm1'
$module = Import-Module -Name $modulePath -Force -PassThru

function Invoke-ConvertRegistryEntries([object[]]$Entries) {
    return & $module {
        param([object[]]$Records)
        ConvertFrom-OsrUninstallEntries -Entries $Records
    } $Entries
}

$entries = @(
    [pscustomobject]@{ PSPath = 'HKLM:\Uninstall\Unnamed' },
    [pscustomobject]@{ DisplayName = 'Another Application' },
    [pscustomobject]@{
        PSPath = 'HKLM:\Uninstall\OSR'
        PSChildName = '{11111111-2222-3333-4444-555555555555}'
        DisplayName = 'Orchestration Server'
        DisplayVersion = '2.4.0.0'
    }
)
$record = Invoke-ConvertRegistryEntries -Entries $entries
if ([string]$record.Version -ne '2.4.0.0') { throw 'Did not detect the correct OSR version.' }
if ($record.Name -ne 'Orchestration Server') { throw 'Did not detect the correct product name.' }
if ($record.InstallSource -ne '') { throw 'Missing optional InstallSource must be empty.' }
if ($record.InstallLocation -ne '') { throw 'Missing optional InstallLocation must be empty.' }
if ($record.LocalPackage -ne '') { throw 'Missing optional LocalPackage must be empty.' }
if ($record.ProductCode -ne '{11111111-2222-3333-4444-555555555555}') {
    throw 'Product code was not preserved.'
}
Write-Host 'PASS: missing DisplayName and optional registry properties'

$entriesWithNoVersion = @(
    [pscustomobject]@{DisplayName='Orchestration Server'},
    [pscustomobject]@{DisplayName='Other app';DisplayVersion='1.2.3'}
)
$detectedExpectedError = $false
try {
    $null = Invoke-ConvertRegistryEntries -Entries $entriesWithNoVersion
} catch {
    if ($_.Exception.Message -like 'Expected exactly one registered Orchestration Server*') {
        $detectedExpectedError = $true
    } else { throw }
}
if (-not $detectedExpectedError) { throw 'Missing OSR version must produce a clear detection error.' }
Write-Host 'PASS: incomplete OSR record produces a clear error'

$duplicateEntries = @(
    [pscustomobject]@{ DisplayName = 'Orchestration Server'; DisplayVersion = '2.4.0.0' },
    [pscustomobject]@{ DisplayName = 'Orchestration Server'; DisplayVersion = '2.5.0.0' }
)
$detectedExpectedError = $false
try {
    $null = Invoke-ConvertRegistryEntries -Entries $duplicateEntries
} catch {
    if ($_.Exception.Message -like 'Expected exactly one registered Orchestration Server*') {
        $detectedExpectedError = $true
    } else { throw }
}
if (-not $detectedExpectedError) { throw 'Multiple OSR records must be rejected.' }
Write-Host 'PASS: ambiguous OSR registration is rejected'

& $module {
    function Test-Path { param($LiteralPath,$ErrorAction) $true }
    function Get-ChildItem { param($LiteralPath,$ErrorAction) [pscustomobject]@{PSPath='synthetic-registry-key'} }
    function Get-ItemProperty { param($LiteralPath,$ErrorAction) [pscustomobject]@{DisplayName='Unrelated application'} }
    if($null -ne (Get-OsrProduct -AllowAbsent)){throw 'Absent OSR was not reported as absent.'}
    function Get-ItemProperty { param($LiteralPath,$ErrorAction) throw 'synthetic registry access denied' }
    $failed=$false
    try{Get-OsrProduct -AllowAbsent | Out-Null}catch{if($_.Exception.Message -match 'access denied'){$failed=$true}else{throw}}
    if(-not $failed){throw 'Registry access error was hidden as product absence.'}
    function Get-ItemProperty { param($LiteralPath,$ErrorAction) [pscustomobject]@{DisplayName='Orchestration Server'} }
    $failed=$false
    try{Get-OsrProduct -AllowAbsent | Out-Null}catch{$failed=$true}
    if(-not $failed){throw 'Malformed named product was hidden as product absence.'}
}
Write-Host 'PASS: recovery absence requires successful registry enumeration; access/malformed errors remain fatal'

Write-Host 'PASS: all OSR registry detection regression tests'
