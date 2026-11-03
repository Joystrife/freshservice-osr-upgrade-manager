#Requires -Version 5.1
Set-StrictMode -Version Latest

function Assert-OsrLabEnvironment {
    param([string]$ExpectedComputerName,[Parameter(Mandatory)]$System)
    if ([string]::IsNullOrWhiteSpace($ExpectedComputerName) -or $ExpectedComputerName -ine $env:COMPUTERNAME) {
        throw 'Lab Repair requires the exact guest computer name.'
    }
    if ($System.Manufacturer -ne 'Microsoft Corporation' -or $System.Model -ne 'Virtual Machine') {
        throw 'Lab Repair requires a dedicated Microsoft Hyper-V guest.'
    }
}

function Assert-OsrLabPaths {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    foreach ($path in @($Source,$Destination)) {
        if ($path -notmatch '^[A-Za-z]:\\') { throw 'Lab paths must be absolute local paths.' }
        $ancestor = [IO.Path]::GetFullPath($path)
        if ($ancestor.TrimEnd('\') -eq [IO.Path]::GetPathRoot($ancestor).TrimEnd('\')) { throw 'A lab path cannot be a volume root.' }
        while ($ancestor) {
            if ((Test-Path -LiteralPath $ancestor) -and
                ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Lab paths cannot traverse reparse points.'
            }
            $ancestor = Split-Path -Path $ancestor -Parent
        }
    }
    $a = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    $b = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
    if ($a -ieq $b -or $a.StartsWith($b+'\',[StringComparison]::OrdinalIgnoreCase) -or
        $b.StartsWith($a+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Lab source and destination cannot overlap.' }
}

function Protect-OsrLabDirectory {
    param([Parameter(Mandatory)][string]$Path)
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($sidText in @('S-1-5-18','S-1-5-32-544')) {
        $sid = New-Object Security.Principal.SecurityIdentifier($sidText)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        [void]$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
    if (-not (Get-Acl -LiteralPath $Path).AreAccessRulesProtected) { throw 'Lab directory permissions were not protected.' }
}

function Assert-OsrLabPathBudget {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    Assert-OsrLabPaths -Source $Source -Destination $Destination
    $sourceRoot=[IO.Path]::GetFullPath($Source).TrimEnd('\')
    $destinationRoot=[IO.Path]::GetFullPath($Destination).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw 'Lab source tree is missing.' }
    if ($sourceRoot.Length -ge 248 -or $destinationRoot.Length -ge 248) {
        throw 'Lab directory path exceeds the conservative Windows PowerShell 5.1 limit. Choose a shorter recovery storage directory.'
    }
    $pending=New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($sourceRoot)
    $longest=$destinationRoot.Length
    $count=0
    while ($pending.Count) {
        foreach ($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction Stop)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Lab trees cannot contain reparse points.' }
            $targetLength=$destinationRoot.Length+$item.FullName.Length-$sourceRoot.Length
            $limit=if($item.PSIsContainer){248}else{260}
            if ($item.FullName.Length -ge $limit -or $targetLength -ge $limit) {
                throw ('Lab path exceeds the conservative Windows PowerShell 5.1 limit (source {0}, destination {1} characters). Choose a shorter recovery storage directory; no file may be skipped.' -f $item.FullName.Length,$targetLength)
            }
            if ($targetLength -gt $longest) { $longest=$targetLength }
            $count++
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
        }
    }
    return [pscustomobject]@{CheckedEntries=$count;LongestDestinationPath=$longest;FilePathLimitExclusive=260;DirectoryPathLimitExclusive=248}
}

function Get-OsrLabTreeInventory {
    param([Parameter(Mandatory)][string]$Root,[scriptblock]$Progress)
    $full = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw 'Lab tree is missing.' }
    if ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Lab tree cannot be a reparse point.' }
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($full)
    if($Progress){& $Progress 'Hashing files' 0 0}
    while ($pending.Count) {
        foreach ($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction Stop)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Lab trees cannot contain reparse points.' }
            $entry = [pscustomobject]@{
                Path=$item.FullName.Substring($full.Length+1); Directory=[bool]$item.PSIsContainer
                Length=0L; SHA256=''; SDDL=(Get-Acl -LiteralPath $item.FullName).Sddl
            }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            else {
                $entry.Length=$item.Length
                $entry.SHA256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
            }
            $entries.Add($entry)
            if($Progress -and $entries.Count % 50 -eq 0){& $Progress 'Hashing files' $entries.Count 0}
        }
    }
    if (@($entries | Where-Object { -not $_.Directory }).Count -eq 0) { throw 'An empty lab tree is not a recovery point.' }
    if($Progress){& $Progress 'File inventory complete' $entries.Count $entries.Count}
    return [pscustomobject]@{SchemaVersion=1;RootSDDL=(Get-Acl -LiteralPath $full).Sddl;Entries=@($entries.ToArray())}
}

function Resolve-OsrLabChildPath {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RelativePath)
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '[:/]' -or
        @($RelativePath.Split('\') | Where-Object { $_ -in @('','.', '..') }).Count) {
        throw 'Invalid relative path in lab inventory.'
    }
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $child = [IO.Path]::GetFullPath((Join-Path $fullRoot $RelativePath))
    if (-not $child.StartsWith($fullRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Lab inventory path escapes its root.' }
    return $child
}

function ConvertTo-OsrLabComparableSecurity {
    param([Parameter(Mandatory)][string]$Sddl)
    $descriptor = New-Object Security.AccessControl.RawSecurityDescriptor($Sddl)
    # Windows may set this bookkeeping bit when Set-Acl reapplies inherited ACEs.
    # Keep owner, group, ACE order/flags/rights and inheritance protection intact.
    $flags = $descriptor.ControlFlags -band (-bnot [Security.AccessControl.ControlFlags]::DiscretionaryAclAutoInherited)
    $descriptor.SetFlags([Security.AccessControl.ControlFlags]$flags)
    return $descriptor.GetSddlForm([Security.AccessControl.AccessControlSections]::All)
}

function Assert-OsrLabTreeEqual {
    param([Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$Actual,[switch]$Security)
    if ($Expected.SchemaVersion -ne 1 -or $Actual.SchemaVersion -ne 1) { throw 'Unsupported lab inventory schema.' }
    $expectedEntries = @($Expected.Entries)
    $actualEntries = @($Actual.Entries)
    if ($expectedEntries.Count -eq 0 -or $expectedEntries.Count -ne $actualEntries.Count) { throw 'Lab inventory count differs.' }
    $index = @{}
    foreach ($entry in $actualEntries) {
        if ($index.ContainsKey($entry.Path)) { throw 'Duplicate lab inventory path.' }
        $index[$entry.Path]=$entry
    }
    $seen = @{}
    foreach ($entry in $expectedEntries) {
        if ($seen.ContainsKey($entry.Path)) { throw 'Duplicate expected lab inventory path.' }
        $seen[$entry.Path]=$true
        if (-not $index.ContainsKey($entry.Path)) { throw 'A lab inventory entry is missing.' }
        $other=$index[$entry.Path]
        if ($entry.Directory -ne $other.Directory -or $entry.Length -ne $other.Length -or $entry.SHA256 -ne $other.SHA256) {
            throw 'Lab inventory content differs.'
        }
        if ($Security -and (ConvertTo-OsrLabComparableSecurity $entry.SDDL) -cne (ConvertTo-OsrLabComparableSecurity $other.SDDL)) { throw 'Lab inventory permissions differ.' }
    }
    if ($Security -and (ConvertTo-OsrLabComparableSecurity $Expected.RootSDDL) -cne (ConvertTo-OsrLabComparableSecurity $Actual.RootSDDL)) { throw 'Lab root permissions differ.' }
}

function Copy-OsrLabTree {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination,[Parameter(Mandatory)]$Inventory,[scriptblock]$Progress)
    Assert-OsrLabPaths -Source $Source -Destination $Destination
    [void](Assert-OsrLabPathBudget -Source $Source -Destination $Destination)
    # Validate every path before the first write.
    foreach ($entry in @($Inventory.Entries)) {
        [void](Resolve-OsrLabChildPath -Root $Source -RelativePath $entry.Path)
        [void](Resolve-OsrLabChildPath -Root $Destination -RelativePath $entry.Path)
    }
    [void](New-Item -Path $Destination -ItemType Directory -Force -ErrorAction Stop)
    foreach ($entry in @($Inventory.Entries | Where-Object Directory | Sort-Object { $_.Path.Length })) {
        [void](New-Item -Path (Resolve-OsrLabChildPath $Destination $entry.Path) -ItemType Directory -Force -ErrorAction Stop)
    }
    $fileEntries=@($Inventory.Entries | Where-Object { -not $_.Directory })
    $copied=0
    if($Progress){& $Progress 'Copying files' 0 $fileEntries.Count}
    foreach ($entry in $fileEntries) {
        Copy-Item -LiteralPath (Resolve-OsrLabChildPath $Source $entry.Path) -Destination (Resolve-OsrLabChildPath $Destination $entry.Path) -ErrorAction Stop
        $copied++
        if($Progress -and ($copied % 50 -eq 0 -or $copied -eq $fileEntries.Count)){& $Progress 'Copying files' $copied $fileEntries.Count}
    }
}

function New-OsrLabFileSnapshot {
    param([string]$Source,[string]$Destination,[scriptblock]$Progress)
    Assert-OsrLabPaths -Source $Source -Destination $Destination
    if (Test-Path -LiteralPath $Destination) { throw 'Lab snapshot destination already exists.' }
    [void](Assert-OsrLabPathBudget -Source $Source -Destination $Destination)
    $inventory = Get-OsrLabTreeInventory -Root $Source -Progress $Progress
    Copy-OsrLabTree -Source $Source -Destination $Destination -Inventory $inventory -Progress $Progress
    if($Progress){& $Progress 'Verifying offline source' 0 0}
    Assert-OsrLabTreeEqual -Expected $inventory -Actual (Get-OsrLabTreeInventory $Source -Progress $Progress) -Security
    if($Progress){& $Progress 'Verifying backup' 0 0}
    Assert-OsrLabTreeEqual -Expected $inventory -Actual (Get-OsrLabTreeInventory $Destination -Progress $Progress)
    return $inventory
}

function Restore-OsrLabFileSnapshot {
    param([string]$Source,[string]$Destination,[Parameter(Mandatory)]$Inventory,[scriptblock]$Progress)
    Assert-OsrLabPaths -Source $Source -Destination $Destination
    [void](Assert-OsrLabPathBudget -Source $Source -Destination $Destination)
    # Rehash the backup and validate manifest paths before deleting or overwriting anything.
    Assert-OsrLabTreeEqual -Expected $Inventory -Actual (Get-OsrLabTreeInventory $Source -Progress $Progress)
    foreach ($entry in @($Inventory.Entries)) { [void](Resolve-OsrLabChildPath $Destination $entry.Path) }
    $current = Get-OsrLabTreeInventory $Destination
    $expected = @{}
    foreach ($entry in @($Inventory.Entries)) { $expected[$entry.Path]=[bool]$entry.Directory }
    foreach ($entry in @($current.Entries | Sort-Object { $_.Path.Length } -Descending)) {
        if (-not $expected.ContainsKey($entry.Path) -or $expected[$entry.Path] -ne [bool]$entry.Directory) {
            $targetPath = Resolve-OsrLabChildPath $Destination $entry.Path
            if ($entry.Directory -and @(Get-ChildItem -LiteralPath $targetPath -Force).Count) { throw 'An unexpected directory is not empty; restore stopped.' }
            Remove-Item -LiteralPath $targetPath -Force -ErrorAction Stop
        }
    }
    Copy-OsrLabTree -Source $Source -Destination $Destination -Inventory $Inventory -Progress $Progress
    # Restore parent security before descendants: parent ACL writes can propagate
    # inherited ACEs and must never overwrite an already restored child ACL.
    $rootSecurity = New-Object Security.AccessControl.DirectorySecurity
    $rootSecurity.SetSecurityDescriptorSddlForm([string]$Inventory.RootSDDL)
    Set-Acl -LiteralPath $Destination -AclObject $rootSecurity -ErrorAction Stop
    $secured=0
    foreach ($entry in @($Inventory.Entries | Sort-Object { $_.Path.Length })) {
        $security = if ($entry.Directory) { New-Object Security.AccessControl.DirectorySecurity } else { New-Object Security.AccessControl.FileSecurity }
        $security.SetSecurityDescriptorSddlForm([string]$entry.SDDL)
        Set-Acl -LiteralPath (Resolve-OsrLabChildPath $Destination $entry.Path) -AclObject $security -ErrorAction Stop
        $secured++
        if($Progress -and ($secured % 50 -eq 0 -or $secured -eq @($Inventory.Entries).Count)){& $Progress 'Restoring permissions' $secured @($Inventory.Entries).Count}
    }
    Assert-OsrLabTreeEqual -Expected $Inventory -Actual (Get-OsrLabTreeInventory $Destination -Progress $Progress) -Security
}

Export-ModuleMember -Function Assert-OsrLabEnvironment,Assert-OsrLabPaths,Assert-OsrLabPathBudget,Protect-OsrLabDirectory,Get-OsrLabTreeInventory,Resolve-OsrLabChildPath,Assert-OsrLabTreeEqual,New-OsrLabFileSnapshot,Restore-OsrLabFileSnapshot
