#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $runtime -PathType Leaf)) { throw 'Windows PowerShell 5.1 is required.' }
$files=@(Get-ChildItem -Path (Join-Path $root 'src'),(Join-Path $root 'tests'),$PSScriptRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1','.psm1') })
foreach ($file in $files) {
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
}
Write-Host ('PASS: syntax for '+$files.Count+' source/test/build files')
$tests=@(Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter 'Test-*.ps1' -File | Sort-Object Name)
if ($tests.Count -ne 7) { throw 'Expected the seven V3 regression suites.' }
foreach ($test in $tests) {
    Write-Host ('RUN '+$test.Name)
    & $runtime -NoProfile -STA -ExecutionPolicy RemoteSigned -File $test.FullName
    if ($LASTEXITCODE -ne 0) { throw ('Regression failed: '+$test.Name) }
}
Write-Host 'PASS: all seven Windows PowerShell 5.1 regression suites'
