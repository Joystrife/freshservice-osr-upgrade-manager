#Requires -Version 5.1
Set-StrictMode -Version Latest

function Test-OsrAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OsrRegistryValue {
    param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][string]$PropertyName)
    # Uninstall registry keys are not uniform. In StrictMode, reading a missing
    # property directly (for example DisplayName or InstallSource) throws.
    if ($null -eq $Entry) { return $null }
    $property = $Entry.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertFrom-OsrUninstallEntries {
    param([AllowEmptyCollection()][object[]]$Entries)
    $products = @(
        foreach ($entry in @($Entries)) {
            if ($null -eq $entry) { continue }
            $name = [string](Get-OsrRegistryValue -Entry $entry -PropertyName 'DisplayName')
            $version = [string](Get-OsrRegistryValue -Entry $entry -PropertyName 'DisplayVersion')
            if ($name -eq 'Orchestration Server' -and -not [string]::IsNullOrWhiteSpace($version)) {
                $entry
            }
        }
    )
    if ($products.Count -ne 1) {
        throw "Expected exactly one registered Orchestration Server installation with a version; found $($products.Count)."
    }
    $app = $products[0]
    $versionText = [string](Get-OsrRegistryValue -Entry $app -PropertyName 'DisplayVersion')
    try { $installedVersion = [version]$versionText }
    catch { throw "Invalid installed Orchestration Server version in the registry: $versionText" }
    $childName = [string](Get-OsrRegistryValue -Entry $app -PropertyName 'PSChildName')
    return [pscustomobject]@{
        Version = $installedVersion
        Name = [string](Get-OsrRegistryValue -Entry $app -PropertyName 'DisplayName')
        RegistryKey = [string](Get-OsrRegistryValue -Entry $app -PropertyName 'PSPath')
        ProductCode = if ($childName -match '^\{[0-9A-Fa-f-]{36}\}$') { $childName } else { $null }
        InstallLocation = [string](Get-OsrRegistryValue -Entry $app -PropertyName 'InstallLocation')
        UninstallString = [string](Get-OsrRegistryValue -Entry $app -PropertyName 'UninstallString')
        InstallSource = [string](Get-OsrRegistryValue -Entry $app -PropertyName 'InstallSource')
        LocalPackage = [string](Get-OsrRegistryValue -Entry $app -PropertyName 'LocalPackage')
    }
}

function Get-OsrProduct {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    # No registry writes. Other installed programs may not have a DisplayName,
    # DisplayVersion, InstallSource or InstallLocation: skip them safely.
    $entries = @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue)
    return ConvertFrom-OsrUninstallEntries -Entries $entries
}

function Get-OsrServiceRecords {
    $expected = @('Orchestration Server','Orchestration Server - WinRM_SSH')
    $all = @(Get-CimInstance Win32_Service | Where-Object { $expected -contains $_.DisplayName })
    if ($all.Count -ne 2) { throw "Expected both Freshworks Orchestration services; found $($all.Count)." }
    return $all
}

function Get-OsrInstallDirectory {
    $records = @(Get-OsrServiceRecords)
    $main = @($records | Where-Object { $_.DisplayName -eq 'Orchestration Server' })[0]
    $path = [string]$main.PathName
    if ($path -match '^\s*"([^\"]+?\.exe)"') { $exe = $Matches[1] }
    elseif ($path -match '^\s*(.+?\.exe)(?:\s|$)') { $exe = $Matches[1] }
    else { throw 'Cannot determine Orchestration Server executable path.' }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing service executable: $exe" }
    $exeDir = Split-Path -Path $exe -Parent
    if ((Split-Path $exeDir -Leaf) -ine 'osr') { throw "Unexpected installation layout: $exeDir" }
    return (Split-Path $exeDir -Parent)
}

function Get-OsrMsiMetadata {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "MSI not found: $Path" }
    if ([IO.Path]::GetExtension($Path) -ine '.msi') { throw 'The selected file must be an MSI.' }
    $installer = $null; $database = $null; $view = $null; $record = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.OpenDatabase((Resolve-Path -LiteralPath $Path).ProviderPath,0)
        $view = $database.OpenView('SELECT `Property`, `Value` FROM `Property`')
        $view.Execute()
        $properties = @{}
        while ($null -ne ($record = $view.Fetch())) {
            $properties[$record.StringData(1)] = $record.StringData(2)
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($record)
            $record = $null
        }
        if ($properties['ProductName'] -ne 'Orchestration Server' -or $properties['Manufacturer'] -notmatch 'Freshworks') {
            throw 'The MSI is not identified as Freshworks Orchestration Server.'
        }
        if (-not $properties['ProductVersion']) { throw 'MSI ProductVersion missing.' }
        return [pscustomobject]@{
            Path = (Resolve-Path -LiteralPath $Path).ProviderPath
            ProductName = [string]$properties['ProductName']
            Manufacturer = [string]$properties['Manufacturer']
            Version = [version]$properties['ProductVersion']
            ProductCode = [string]$properties['ProductCode']
            Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        }
    }
    finally {
        if ($null -ne $record) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($record) }
        if ($null -ne $view) { $view.Close(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($view) }
        if ($null -ne $database) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($database) }
        if ($null -ne $installer) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($installer) }
    }
}

function Assert-OsrPackageAuthenticity {
    param([Parameter(Mandatory)][string]$Path,[string]$ExpectedSha256)
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $validVendor = ($signature.Status -eq 'Valid' -and $null -ne $signature.SignerCertificate -and
        $signature.SignerCertificate.Subject -match 'Freshworks')
    if ($ExpectedSha256) {
        if ($ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Approved SHA-256 must contain exactly 64 hexadecimal characters.' }
        if ($actual -ine $ExpectedSha256) { throw "MSI checksum differs from independently approved SHA-256: $Path" }
    }
    elseif (-not $validVendor) {
        throw "MSI is not validated by a Freshworks code signature. Supply an independently verified SHA-256: $Path"
    }
    return [pscustomobject]@{ Hash=$actual; Signature=[string]$signature.Status; VendorSignature=[bool]$validVendor }
}

function Assert-OsrSafePath {
    param([string]$InstallDirectory,[string]$BackupRoot)
    $source = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\')
    $destination = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
    if ($source.Equals($destination,[StringComparison]::OrdinalIgnoreCase) -or
        $destination.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Recovery directory cannot be the installation directory or one of its subdirectories.'
    }
}

function Invoke-OsrRobocopy {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination,[switch]$Mirror,[string]$LogFile)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Backup source missing: $Source" }
    [void](New-Item -Path $Destination -ItemType Directory -Force)
    $arguments = @('"'+$Source+'"','"'+$Destination+'"', $(if($Mirror){'/MIR'}else{'/E'}), '/COPYALL','/DCOPY:DAT','/XJ','/R:1','/W:1','/NP')
    if ($LogFile) { $arguments += '/LOG+:"'+$LogFile+'"' }
    $process = Start-Process -FilePath 'robocopy.exe' -ArgumentList ($arguments -join ' ') -PassThru -Wait -WindowStyle Hidden
    if ($process.ExitCode -ge 8) { throw "Robocopy failure (exit code $($process.ExitCode))." }
    return $process.ExitCode
}

function Stop-OsrServices {
    # The Freshworks services are managed; the native Windows WinRM service is NEVER stopped.
    $desired = @('Orchestration Server - WinRM_SSH','Orchestration Server')
    foreach ($display in $desired) {
        $svc = @(Get-Service | Where-Object { $_.DisplayName -eq $display })
        if ($svc.Count -ne 1) { throw "Service not found: $display" }
        if ($svc[0].Status -ne 'Stopped') {
            Stop-Service -InputObject $svc[0] -ErrorAction Stop
            $svc[0].WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(90))
        }
    }
    foreach ($svc in @(Get-OsrServiceRecords)) {
        if ($svc.State -ne 'Stopped') { throw "Service did not stop: $($svc.DisplayName)" }
    }
}

function Start-OsrServices {
    foreach ($display in @('Orchestration Server','Orchestration Server - WinRM_SSH')) {
        $svc = @(Get-Service | Where-Object { $_.DisplayName -eq $display })
        if ($svc.Count -ne 1) { throw "Service missing: $display" }
        if ($svc[0].Status -ne 'Running') {
            Start-Service -InputObject $svc[0] -ErrorAction Stop
            $svc[0].WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(90))
        }
    }
    foreach ($svc in @(Get-OsrServiceRecords)) { if ($svc.State -ne 'Running') { throw "Service not running: $($svc.DisplayName)" } }
}

function Invoke-OsrMsi {
    param([Parameter(Mandatory)][ValidateSet('Install','Uninstall')][string]$Operation,
        [Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$LogFile,
        [switch]$Interactive)
    # Always disallow reboot. Nonzero/3010 are returned for the caller to handle.
    $verb = if($Operation -eq 'Install'){'/i'}else{'/x'}
    $ui = if($Interactive){''}else{'/qn'}
    $args = "$verb `"$Target`" $ui /norestart /L*v `"$LogFile`""
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -PassThru -Wait -ErrorAction Stop
    return [int]$p.ExitCode
}


function Find-OsrPreviousMsi {
    <#
    .SYNOPSIS
    Read-only discovery of an ORIGINAL previous OSR installer.
    .DESCRIPTION
    Searches only a few locally relevant locations; does not scan the full disk,
    download software, trust the Windows Installer cache or modify the system.
    A matching version is not proof of authenticity: the package must have a
    valid Freshworks signature or an independently supplied SHA-256.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][version]$InstalledVersion,
        [string]$UpgradeMsiPath,
        [string]$RecoveryRoot,
        [string]$ExpectedSha256,
        [string]$PreferredPath
    )
    $paths = New-Object 'System.Collections.Generic.List[string]'
    $folders = New-Object 'System.Collections.Generic.List[string]'
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $remarks = New-Object 'System.Collections.Generic.List[string]'
    function Add-OriginalFile([string]$File) {
        if([string]::IsNullOrWhiteSpace($File)){return}
        try {
            $full=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($File))
            if($full -match '(?i)\\Windows\\Installer\\') {return}
            if($full -notmatch '(?i)\.msi$'){return}
            if($seen.Add($full) -and (Test-Path -LiteralPath $full -PathType Leaf)) { $paths.Add($full) }
        } catch { }
    }
    function Add-SearchFolder([string]$Folder) {
        if([string]::IsNullOrWhiteSpace($Folder)){return}
        try {
            $full=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Folder))
            if($full -match '(?i)\\Windows\\Installer(\\|$)'){return}
            if((Test-Path -LiteralPath $full -PathType Container) -and -not $folders.Contains($full)){
                $folders.Add($full)
            }
        } catch { }
    }
    Add-OriginalFile $PreferredPath
    try {
        $product=Get-OsrProduct
        if($product.InstallSource){
            if($product.InstallSource -match '(?i)\.msi$'){ Add-OriginalFile $product.InstallSource }
            else {Add-SearchFolder $product.InstallSource}
        }
        if($product.LocalPackage){
            $remarks.Add('Windows Installer cached package was intentionally excluded; it may not be a full redistributable installer.')
        }
    } catch { $remarks.Add('OSR registration could not be inspected.') }
    if($UpgradeMsiPath) {
        try {Add-SearchFolder (Split-Path -Path ([IO.Path]::GetFullPath($UpgradeMsiPath)) -Parent)} catch { }
    }
    if($env:USERPROFILE){Add-SearchFolder (Join-Path $env:USERPROFILE 'Downloads')}
    if($env:PUBLIC){Add-SearchFolder (Join-Path $env:PUBLIC 'Downloads')}
    foreach($folder in $folders){
        # Deliberately bounded, nonrecursive discovery: unrelated drives are never crawled.
        foreach($pattern in @('FO-OSR*.msi','*Orchestration*.msi')){
            foreach($f in @(Get-ChildItem -LiteralPath $folder -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 30)) {
                Add-OriginalFile $f.FullName
            }
        }
    }
    if($RecoveryRoot -and (Test-Path -LiteralPath $RecoveryRoot -PathType Container)){
        foreach($run in @(Get-ChildItem -LiteralPath $RecoveryRoot -Directory -Filter 'Run-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 30)){
            Add-OriginalFile (Join-Path $run.FullName 'recovery-point\previous-FO-OSR.msi')
        }
    }
    $newPath=''
    try {if($UpgradeMsiPath){$newPath=[IO.Path]::GetFullPath($UpgradeMsiPath)}} catch { }
    $candidates=New-Object 'System.Collections.Generic.List[object]'
    foreach($path in $paths){
        if($newPath -and $path -ieq $newPath){continue}
        try {
            $meta=Get-OsrMsiMetadata -Path $path
            if($meta.Version -ne $InstalledVersion){continue}
            $trusted=$false; $reason=''
            try {
                $evidence=Assert-OsrPackageAuthenticity -Path $meta.Path -ExpectedSha256 $ExpectedSha256
                $trusted=$true
                $reason=if($evidence.VendorSignature){'Valid Freshworks signature'}else{'Independently verified SHA-256'}
            } catch { $reason=$_.Exception.Message }
            $candidates.Add([pscustomobject]@{
                Path=$meta.Path; Version="$($meta.Version)"; Sha256=$meta.Sha256
                Verified=$trusted; Verification=$reason
            })
        } catch { $remarks.Add('Skipped an unreadable or non-Freshworks MSI candidate.') }
    }
    $best=@($candidates | Sort-Object -Property @{Expression='Verified';Descending=$true}, @{Expression='Path';Descending=$false} | Select-Object -First 1)
    return [pscustomobject]@{
        Found=($best.Count -gt 0)
        Verified=($best.Count -gt 0 -and [bool]$best[0].Verified)
        Path=if($best.Count){[string]$best[0].Path}else{''}
        Version=if($best.Count){[string]$best[0].Version}else{''}
        Verification=if($best.Count){[string]$best[0].Verification}else{''}
        Candidates=$candidates.Count
        Notes=@($remarks.ToArray())
    }
}

function Get-OsrRecoveryEnvironment {
    <# Read-only diagnostic. A VM marker is NOT a recoverable checkpoint. #>
    $vm='Unknown'; $backup='Unavailable'
    try {
        $system=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $vm=("$($system.Manufacturer) / $($system.Model)").Trim()
    } catch { }
    if(Get-Command wbadmin.exe -ErrorAction SilentlyContinue){$backup='Windows Server Backup command available; no restorable backup verified'}
    $hyperv = [bool](Get-Command Get-VM -ErrorAction SilentlyContinue)
    return [pscustomobject]@{
        Machine=$vm
        WindowsBackup=$backup
        HyperVModulePresent=$hyperv
        SnapshotRecoveryReady=$false
        Message='No full-machine rollback is claimed by this diagnostic. Hypervisor checkpoints require independent host-side access and a supported restore procedure.'
    }
}

Export-ModuleMember -Function Test-OsrAdministrator,Get-OsrProduct,Get-OsrServiceRecords,Get-OsrInstallDirectory,Get-OsrMsiMetadata,Assert-OsrPackageAuthenticity,Assert-OsrSafePath,Invoke-OsrRobocopy,Stop-OsrServices,Start-OsrServices,Invoke-OsrMsi,Find-OsrPreviousMsi,Get-OsrRecoveryEnvironment