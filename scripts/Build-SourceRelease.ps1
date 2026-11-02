#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory,[string]$SourceCommit=$env:GITHUB_SHA)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory=Join-Path $root 'dist' }
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
[void](New-Item -Path $output -ItemType Directory -Force)
$version=([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
if ($version -ne '0.5.0') { throw 'This source release builder is pinned to version 0.5.0.' }
$zipPath=Join-Path $output 'OSR-Upgrade-Manager-0.5.0-source.zip'
$checksumPath=Join-Path $output 'SHA256SUMS.txt'
if ((Test-Path -LiteralPath $zipPath) -or (Test-Path -LiteralPath $checksumPath)) { throw 'Release output already exists. Use a new output directory.' }
$stage=Join-Path $output ('.stage-'+[guid]::NewGuid().ToString('N'))
try {
    [void](New-Item -Path $stage -ItemType Directory)
    foreach ($directory in @('src','tests','docs','scripts','launcher','.github')) {
        $sourceDirectory=Join-Path $root $directory
        foreach ($file in @(Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File -Force |
            Where-Object { $_.Extension -in @('.ps1','.psm1','.cs','.manifest','.md','.svg','.png','.yml') })) {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not allowed in source packages.' }
            $relative=$file.FullName.Substring($root.Length+1)
            $target=Join-Path $stage $relative
            [void](New-Item -Path (Split-Path $target -Parent) -ItemType Directory -Force)
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
    }
    foreach ($name in @('Start-Manager.cmd','README.md','CHANGELOG.md','ROADMAP.md','SECURITY.md','LICENSE','VERSION','.gitignore','.gitattributes')) {
        Copy-Item -LiteralPath (Join-Path $root $name) -Destination $stage
    }
    $hashLines=@(Get-ChildItem -LiteralPath $stage -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash+'  '+$_.FullName.Substring($stage.Length+1).Replace('\','/')
    })
    [IO.File]::WriteAllLines((Join-Path $stage 'PACKAGE-FILES.sha256'),$hashLines,[Text.Encoding]::UTF8)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage,$zipPath,[IO.Compression.CompressionLevel]::Optimal,$false)
    $archive=[IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $names=@($archive.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
        foreach ($required in @('Start-Manager.cmd','LICENSE','VERSION','docs/USER_GUIDE.md','src/OSR.Upgrade.Worker.ps1','src/OSR.Recovery.LabFiles.psm1')) {
            if ($names -notcontains $required) { throw ('Missing release file: '+$required) }
        }
        if ($names | Where-Object { $_ -match '\.(msi|exe|log|json|conf|reg|vhdx|pfx|key)$|(^|/)\.git/' }) { throw 'Runtime or sensitive data found in source archive.' }
    } finally { $archive.Dispose() }
    $hash=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    [IO.File]::WriteAllText($checksumPath,($hash+'  '+[IO.Path]::GetFileName($zipPath)+[Environment]::NewLine),[Text.Encoding]::ASCII)
    Write-Host ('Built 0.5.0 source package; source commit: '+$SourceCommit)
    Write-Output $zipPath
    Write-Output $checksumPath
} finally {
    $resolved=[IO.Path]::GetFullPath($stage)
    if (-not $resolved.StartsWith($output+'\',[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notmatch '^\.stage-[a-f0-9]{32}$') { throw 'Unsafe staging cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
