#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\OSR.Recovery.LabFiles.psm1') -Force
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('OsrLabFiles-' + [guid]::NewGuid().ToString('N'))
function Assert-Throws([scriptblock]$Action,[string]$Label) {
    $thrown=$false
    try { & $Action | Out-Null } catch { $thrown=$true }
    if (-not $thrown) { throw ('Expected rejection: ' + $Label) }
    Write-Host ('PASS: rejected ' + $Label)
}
try {
    $source=Join-Path $testRoot 'source'
    $backup=Join-Path $testRoot 'backup'
    [void](New-Item -Path (Join-Path $source 'osr\empty') -ItemType Directory -Force)
    $file=Join-Path $source 'osr\fixture.conf'
    Set-Content -LiteralPath $file -Value 'original synthetic configuration'
    $inventory=New-OsrLabFileSnapshot -Source $source -Destination $backup
    Set-Content -LiteralPath $file -Value 'modified by simulated repair'
    Set-Content -LiteralPath (Join-Path $source 'extra.tmp') -Value 'extra synthetic data'
    Remove-Item -LiteralPath (Join-Path $source 'osr\empty')
    Restore-OsrLabFileSnapshot -Source $backup -Destination $source -Inventory $inventory
    Assert-OsrLabTreeEqual -Expected $inventory -Actual (Get-OsrLabTreeInventory $source) -Security
    if (Test-Path -LiteralPath (Join-Path $source 'extra.tmp')) { throw 'Extra file was not removed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $source 'osr\empty') -PathType Container)) { throw 'Empty directory was not restored.' }
    Write-Host 'PASS: actual synthetic file restoration restores content, empty directories and permissions and removes extras'
    Set-Content -LiteralPath $file -Value 'live content must remain untouched'
    Set-Content -LiteralPath (Join-Path $backup 'osr\fixture.conf') -Value 'tampered backup'
    Assert-Throws { Restore-OsrLabFileSnapshot -Source $backup -Destination $source -Inventory $inventory } 'tampered backup before destination writes'
    if ((Get-Content -LiteralPath $file -Raw).Trim() -ne 'live content must remain untouched') { throw 'Destination changed after backup verification failed.' }
    foreach ($path in @('..\escape','C:\outside','\\server\share','osr\..\escape','osr:stream','osr//file')) {
        Assert-Throws { Resolve-OsrLabChildPath -Root $source -RelativePath $path } ('unsafe inventory path ' + $path)
    }
    Assert-Throws { Assert-OsrLabPaths -Source $source -Destination (Join-Path $source 'backup') } 'nested destination'
    Assert-Throws { Assert-OsrLabPaths -Source $source -Destination $testRoot } 'ancestor destination'
    Assert-Throws { Assert-OsrLabPaths -Source $source -Destination '.\relative' } 'relative destination'
    $pathSource=Join-Path $testRoot 'path-source'
    [void](New-Item -Path $pathSource -ItemType Directory)
    $probeName=('f'*60)+'.txt'
    Set-Content -LiteralPath (Join-Path $pathSource $probeName) -Value 'Synthetic path-budget fixture'
    # Exactly 261 characters in the proposed file path, regardless of TEMP length.
    $destinationLength=261-1-$probeName.Length
    $longDestination=Join-Path $testRoot ('d'*($destinationLength-$testRoot.Length-1))
    if (($longDestination+'\'+$probeName).Length -ne 261) { throw 'Long-path fixture length is incorrect.' }
    Assert-Throws { New-OsrLabFileSnapshot -Source $pathSource -Destination $longDestination } '261-character backup path before copy'
    if (Test-Path -LiteralPath $longDestination) { throw 'Long-path rejection created the backup destination.' }
    $shortDestination=Join-Path $testRoot 'short-backup'
    $pathInventory=New-OsrLabFileSnapshot -Source $pathSource -Destination $shortDestination
    Assert-OsrLabTreeEqual -Expected $pathInventory -Actual (Get-OsrLabTreeInventory $shortDestination)
    Write-Host 'PASS: the same source captures and verifies with a shorter destination'
    $junction=Join-Path $source 'link'
    [void](New-Item -Path $junction -ItemType Junction -Target $backup)
    try {
        Assert-Throws { Get-OsrLabTreeInventory -Root $source } 'junction inside source'
        Assert-Throws { Assert-OsrLabPaths -Source $source -Destination (Join-Path $junction 'child') } 'junction ancestor'
    } finally { [IO.Directory]::Delete($junction) }
} finally {
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notmatch '^OsrLabFiles-[a-f0-9]{32}$') { throw 'Unsafe test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
