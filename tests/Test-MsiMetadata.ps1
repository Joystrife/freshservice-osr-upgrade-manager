#Requires -Version 5.1
<#
.SYNOPSIS
Reads a synthetic MSI database through the real Windows Installer COM API.
.DESCRIPTION
Creates only a temporary metadata fixture. Never installs or repairs software.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\OSR.Upgrade.Core.psm1') -Force
$fixturePath = Join-Path ([IO.Path]::GetTempPath()) ('OSR-Metadata-Test-' + [guid]::NewGuid().ToString('N') + '.msi')
$installer = $null
$database = $null
$view = $null
try {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.OpenDatabase($fixturePath,3)
    $statements = @(
        'CREATE TABLE `Property` (`Property` CHAR(72) NOT NULL, `Value` CHAR(255) PRIMARY KEY `Property`)',
        "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('ProductName', 'Orchestration Server')",
        "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('Manufacturer', 'Freshworks Synthetic Fixture')",
        "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('ProductVersion', '2.5.0.0')",
        "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('ProductCode', '{11111111-2222-3333-4444-555555555555}')"
    )
    foreach ($statement in $statements) {
        $view = $database.OpenView($statement)
        [void]$view.Execute()
        [void]$view.Close()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($view)
        $view = $null
    }
    [void]$database.Commit()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($database)
    $database = $null
    $items = @(Get-OsrMsiMetadata -Path $fixturePath)
    if ($items.Count -ne 1 -or $null -eq $items[0]) { throw 'MSI metadata must emit exactly one non-null record.' }
    $metadata = $items[0]
    if ($metadata.Path -ne $fixturePath -or $metadata.Version -ne [version]'2.5.0.0' -or
        $metadata.ProductCode -ne '{11111111-2222-3333-4444-555555555555}' -or
        $metadata.Sha256 -ne (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash) {
        throw 'Synthetic MSI metadata did not match the expected record.'
    }
    Write-Host 'PASS: real MSI COM metadata returns exactly one record with Path, version, identity and hash'
} finally {
    if ($null -ne $view) { [void]$view.Close(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($view) }
    if ($null -ne $database) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($database) }
    if ($null -ne $installer) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($installer) }
    if (Test-Path -LiteralPath $fixturePath) { Remove-Item -LiteralPath $fixturePath -Force }
}
