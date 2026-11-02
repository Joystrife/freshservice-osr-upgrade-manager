#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $root 'dist\portable' }
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$exe=Join-Path $output 'OSR-Upgrade-Manager-0.5.0-portable.exe'
$checksum=Join-Path $output 'SHA256SUMS.txt'
if ((Test-Path -LiteralPath $exe) -or (Test-Path -LiteralPath $checksum)) { throw 'Output already exists; choose a fresh output directory.' }
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'The Windows .NET Framework 4.x C# compiler is required; nothing was installed.' }
[void](New-Item -Path $output -ItemType Directory -Force)
$stage=Join-Path $output ('.portable-build-'+[guid]::NewGuid().ToString('N'))
try {
    $payload=Join-Path $stage 'payload'
    [void](New-Item -Path (Join-Path $payload 'src') -ItemType Directory -Force)
    $runtimeFiles=@('Freshservice_OSR_Upgrade_GUI.ps1','OSR.Upgrade.Core.psm1','OSR.Upgrade.Worker.ps1','OSR.Recovery.LabFiles.psm1','OSR.Recovery.WindowsServerBackup.psm1')
    foreach ($name in $runtimeFiles) {
        $source=Join-Path $root ('src\'+$name)
        if ((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Runtime files cannot be reparse points.' }
        Copy-Item -LiteralPath $source -Destination (Join-Path $payload 'src')
    }
    foreach ($name in @('LICENSE','VERSION')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination $payload }
    Copy-Item -LiteralPath (Join-Path $root 'docs\PORTABLE_EXECUTABLE.md') -Destination (Join-Path $payload 'README.md')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=Join-Path $stage 'payload.zip'
    # Explicit entry names keep the launcher manifest independent of ZIP tools/platforms.
    $archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in @(Get-ChildItem -LiteralPath $payload -Recurse -File | Sort-Object FullName)) {
            $name=$file.FullName.Substring($payload.Length+1).Replace('\','/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$name,[IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $archive.Dispose() }
    $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    $sourceCode=[IO.File]::ReadAllText((Join-Path $root 'launcher\PortableLauncher.cs'))
    if (-not $sourceCode.Contains('__PAYLOAD_SHA256__')) { throw 'Launcher checksum placeholder is missing.' }
    $generated=Join-Path $stage 'PortableLauncher.cs'
    [IO.File]::WriteAllText($generated,$sourceCode.Replace('__PAYLOAD_SHA256__',$hash),[Text.Encoding]::UTF8)
    & $compiler /nologo /target:winexe /platform:x64 /optimize+ /warnaserror+ "/out:$exe" "/win32manifest:$(Join-Path $root 'launcher\PortableLauncher.manifest')" "/resource:$zip,OSR.Payload.zip" /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll $generated
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw 'Portable launcher compilation failed.' }
    $exeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    [IO.File]::WriteAllText($checksum,($exeHash+'  '+[IO.Path]::GetFileName($exe)+[Environment]::NewLine),[Text.Encoding]::ASCII)
    Write-Output $exe
    Write-Output $checksum
} finally {
    $resolved=[IO.Path]::GetFullPath($stage)
    if (-not $resolved.StartsWith($output+'\',[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notmatch '^\.portable-build-[a-f0-9]{32}$') { throw 'Unsafe build cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
