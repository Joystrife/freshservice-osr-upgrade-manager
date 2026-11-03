#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('OsrPortableTest-'+[guid]::NewGuid().ToString('N'))
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Assert-Rejected([scriptblock]$Action,[string]$Label) {
    $rejected=$false
    try { & $Action | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw ('Expected rejection: '+$Label) }
    Write-Host ('PASS: portable rejection - '+$Label)
}
function Get-BytesHash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
}
function New-FixtureZip([string[]]$Names) {
    $memory=New-Object IO.MemoryStream
    $zip=New-Object IO.Compression.ZipArchive($memory,[IO.Compression.ZipArchiveMode]::Create,$true)
    try {
        foreach ($name in $Names) {
            $entry=$zip.CreateEntry($name)
            $stream=$entry.Open()
            try { $data=[Text.Encoding]::UTF8.GetBytes('synthetic fixture'); $stream.Write($data,0,$data.Length) } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    try { return ,$memory.ToArray() } finally { $memory.Dispose() }
}
try {
    $build=Join-Path $testRoot 'build'
    & (Join-Path $root 'scripts\Build-PortableExecutable.ps1') -OutputDirectory $build | Out-Null
    $exe=Join-Path $build 'OSR-Upgrade-Manager-0.5.1-preview.3-portable.exe'
    $expectedExeHash=([IO.File]::ReadAllText((Join-Path $build 'SHA256SUMS.txt')).Trim() -split '\s+')[0]
    if ((Get-FileHash -LiteralPath $exe).Hash -ne $expectedExeHash) { throw 'Executable checksum differs.' }
    $assembly=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($exe))
    $type=$assembly.GetType('PortableLauncher',$true)
    $flags=[Reflection.BindingFlags]'Static,NonPublic'
    $extract=$type.GetMethod('ExtractPayload',$flags)
    $expectedPayloadHash=$type.GetField('PayloadSha256',$flags).GetRawConstantValue()
    $stream=$assembly.GetManifestResourceStream('OSR.Payload.zip')
    $memory=New-Object IO.MemoryStream
    try { $stream.CopyTo($memory); $payload=$memory.ToArray() } finally { $stream.Dispose(); $memory.Dispose() }
    if ((Get-BytesHash $payload) -ne $expectedPayloadHash) { throw 'Embedded payload checksum differs.' }
    function Invoke-Extraction([byte[]]$Bytes,[string]$Hash,[string]$Destination) {
        $inputStream=New-Object IO.MemoryStream(,$Bytes)
        try { return $extract.Invoke($null,@($inputStream.PSObject.BaseObject,$Hash,$Destination)) } finally { $inputStream.Dispose() }
    }
    $target=Join-Path $testRoot 'extracted'
    $first=Invoke-Extraction $payload $expectedPayloadHash $target
    $second=Invoke-Extraction $payload $expectedPayloadHash $target
    if ($first -eq $second -or @(Get-ChildItem -LiteralPath $first -Recurse -File).Count -ne 9) { throw 'Each launch must extract nine files into a unique directory.' }
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $first 'src') -File)) {
        if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $root ('src\'+$file.Name))).Hash) { throw ('Packaged source differs: '+$file.Name) }
    }
    $acl=Get-Acl -LiteralPath $first
    if (-not $acl.AreAccessRulesProtected) { throw 'Extracted package ACL is not protected.' }
    $allowed=@([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')
    foreach ($rule in $acl.Access) {
        if ($rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin $allowed) { throw 'Unexpected extracted package access.' }
    }
    Write-Host 'PASS: compiled x64 launcher, executable/payload checksums, exact source parity, protected unique extraction'
    $badTarget=Join-Path $testRoot 'must-not-exist'
    $tampered=[byte[]]$payload.Clone(); $tampered[0]=$tampered[0] -bxor 1
    Assert-Rejected { Invoke-Extraction $tampered $expectedPayloadHash $badTarget } 'corrupted payload before writes'
    $names=@('src/Freshservice_OSR_Upgrade_GUI.ps1','src/OSR.Gui.Settings.psm1','src/OSR.Upgrade.Core.psm1','src/OSR.Upgrade.Worker.ps1','src/OSR.Recovery.LabFiles.psm1','src/OSR.Recovery.WindowsServerBackup.psm1','LICENSE','VERSION','README.md')
    foreach ($entries in @(
        @{Label='path traversal';Names=@('../escape.ps1')},
        @{Label='absolute path';Names=@('C:/escape.ps1')},
        @{Label='alternate data stream';Names=@('README.md:evil')},
        @{Label='unexpected executable';Names=@($names)+'extra.exe'},
        @{Label='duplicate entry';Names=@($names)+'README.md'},
        @{Label='missing module';Names=@('README.md')}
    )) {
        $bytes=New-FixtureZip $entries.Names
        Assert-Rejected { Invoke-Extraction $bytes (Get-BytesHash $bytes) $badTarget } $entries.Label
    }
    if (Test-Path -LiteralPath $badTarget) { throw 'Invalid payload made filesystem changes.' }
    $junction=Join-Path $testRoot 'junction'
    [void](New-Item -Path $junction -ItemType Junction -Target $target)
    try { Assert-Rejected { Invoke-Extraction $payload $expectedPayloadHash (Join-Path $junction 'child') } 'reparse-point extraction ancestor' }
    finally { [IO.Directory]::Delete($junction) }
    $longTarget=Join-Path $testRoot ('x'*(210-$testRoot.Length))
    Assert-Rejected { Invoke-Extraction $payload $expectedPayloadHash $longTarget } 'overlong extraction destination'
    [xml]$manifest=Get-Content -LiteralPath (Join-Path $root 'launcher\PortableLauncher.manifest') -Raw
    if ($manifest.assembly.trustInfo.security.requestedPrivileges.requestedExecutionLevel.level -ne 'asInvoker') { throw 'Launcher must not request administrator at startup.' }
    $source=[IO.File]::ReadAllText((Join-Path $root 'launcher\PortableLauncher.cs'))
    if ($source -notmatch '-NoProfile -STA -ExecutionPolicy RemoteSigned -File' -or $source -match 'ExecutionPolicy Bypass|Verb\s*=\s*"runas"') { throw 'Unexpected launcher privilege or execution policy behavior.' }
    Write-Host 'PASS: asInvoker manifest and Windows PowerShell startup boundary; no OSR action was executed'
} finally {
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notmatch '^OsrPortableTest-[a-f0-9]{32}$') { throw 'Unsafe portable test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
