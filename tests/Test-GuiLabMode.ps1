#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
$guiText=[IO.File]::ReadAllText((Join-Path $root 'src\Freshservice_OSR_Upgrade_GUI.ps1'))
# Construct actual WinForms controls and handlers without displaying a window.
$guiText=$guiText.Replace('[void]$form.ShowDialog()','')
$tempFile=Join-Path ([IO.Path]::GetTempPath()) ('OsrGuiTest-'+[guid]::NewGuid().ToString('N')+'.ps1')
# Keep forms alive until assertions finish; no user input or dialogs are invoked.
$guiText=$guiText.Replace('$form.Dispose()','')
[IO.File]::WriteAllText($tempFile,$guiText,[Text.Encoding]::UTF8)
try {
    & {
        function Import-Module { param($Name,[switch]$Force) }
        function Test-OsrAdministrator { $true }
        function Get-OsrInstallDirectory { 'C:\SyntheticOSR' }
        . $tempFile -NoPreferences
        try {
            $sharedLog=$tempFile+'.log'
            try{
                [IO.File]::WriteAllText($sharedLog,"complete Ω`npartial",[Text.Encoding]::UTF8)
                $writer=[IO.File]::Open($sharedLog,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
                try{
                    $lines=@(Read-GuiActivityLines $sharedLog)
                    if($lines.Count -ne 1 -or $lines[0] -ne 'complete Ω'){throw 'Shared journal read corrupted Unicode or exposed an unfinished line.'}
                    [void]$writer.Seek(0,[IO.SeekOrigin]::End)
                    $bytes=[Text.Encoding]::UTF8.GetBytes(" completed`n")
                    $writer.Write($bytes,0,$bytes.Length);$writer.Flush()
                    $lines=@(Read-GuiActivityLines $sharedLog)
                    if($lines.Count -ne 2 -or $lines[1] -ne 'partial completed'){throw 'Next journal poll lost a completed line.'}
                }finally{$writer.Dispose()}
            }finally{if(Test-Path -LiteralPath $sharedLog){[IO.File]::Delete($sharedLog)}}
            Write-Host 'PASS: shared log reads coexist with an open writer and defer incomplete lines'
            if(-not $script:WorkspaceDiagnostic -or -not $script:chkDryRun.Checked -or $script:chkDryRun.Enabled -or
                $script:btnStart.Visible -or $script:txtMsi.Visible){throw 'Diagnostic workspace did not default to read-only.'}
            $script:chkDryRun.Checked=$false
            if(-not $script:chkDryRun.Checked){throw 'Diagnostic allowed live mode.'}
            $blocked=$false
            try{New-Run 'Preflight'}catch{if($_.Exception.Message -match 'Diagnostic is read-only'){$blocked=$true}else{throw}}
            if(-not $blocked){throw 'Diagnostic launched a worker.'}
            Select-WorkspaceOperation 'Upgrade'
            $initialLogWidth=$script:lstLog.Width
            $initialLogHeight=$script:lstLog.Height
            $initialInputWidth=$script:txtMsi.Width
            $initialBrowseMargin=$form.ClientSize.Width-$script:btnMsi.Right
            $form.ClientSize=New-Object Drawing.Size(($form.ClientSize.Width+320),($form.ClientSize.Height+180))
            $form.PerformLayout()
            $script:logPanel.PerformLayout()
            if ($script:lstLog.Width -le $initialLogWidth -or $script:lstLog.Height -le $initialLogHeight -or
                $script:txtMsi.Width -le $initialInputWidth -or
                $form.ClientSize.Width-$script:btnMsi.Right -ne $initialBrowseMargin -or
                $script:lstLog.Top -lt $script:logToolbar.Bottom) { throw 'Log panel or input rows did not resize without overlap.' }
            function Set-GuiClipboardText([string]$Text) { $script:clipboardFixture=$Text }
            $script:clipboardFixture='existing clipboard fixture'
            Copy-GuiLog
            if ($script:clipboardFixture -ne 'existing clipboard fixture') { throw 'Empty log cleared the clipboard.' }
            $unicodeLine='Synthetic '+[char]0xE9+' log entry'
            [void]$script:lstLog.Items.Add('First complete log line')
            [void]$script:lstLog.Items.Add($unicodeLine)
            [void]$script:lstLog.Items.Add('Third complete log line')
            $script:lstLog.SetSelected(2,$true)
            $script:lstLog.SetSelected(0,$true)
            $script:btnCopySelectedLogs.PerformClick()
            if ($script:clipboardFixture -ne ('First complete log line'+[Environment]::NewLine+'Third complete log line')) { throw 'Selected log lines were not copied in display order.' }
            $script:btnCopyAllLogs.PerformClick()
            if ($script:clipboardFixture -ne ('First complete log line'+[Environment]::NewLine+$unicodeLine+[Environment]::NewLine+'Third complete log line')) { throw 'Complete Unicode log text was not copied.' }
            $script:lstLog.ClearSelected()
            $onKeyDown=$script:lstLog.GetType().GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
            $selectKey=New-Object Windows.Forms.KeyEventArgs([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::A)
            [void]$onKeyDown.Invoke($script:lstLog,[object[]]@($selectKey.PSObject.BaseObject))
            if ($script:lstLog.SelectedItems.Count -ne 3 -or -not $selectKey.SuppressKeyPress) { throw 'Ctrl+A did not select all log lines.' }
            $script:clipboardFixture='unchanged'
            $copyKey=New-Object Windows.Forms.KeyEventArgs([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::C)
            [void]$onKeyDown.Invoke($script:lstLog,[object[]]@($copyKey.PSObject.BaseObject))
            if ($script:clipboardFixture -ne (Get-GuiLogText) -or -not $copyKey.SuppressKeyPress) { throw 'Ctrl+C did not copy selected log text.' }
            function Set-GuiClipboardText([string]$Text) { throw 'Synthetic busy clipboard' }
            Copy-GuiLog
            if ($script:lblLogCopy.Text -notmatch 'Clipboard unavailable') { throw 'Clipboard failure was not handled.' }
            $script:lstLog.Items.Clear()
            Write-Host 'PASS: responsive log/input layout, selected/all Unicode copy, keyboard shortcuts and clipboard failure handling'
            if($script:WorkspaceAdvanced){throw 'Advanced options must start collapsed.'}
            $script:txtSHA.Text='synthetic retained input'
            $onClick=$script:btnAdvanced.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
            [void]$onClick.Invoke($script:btnAdvanced,[object[]]@([EventArgs]::Empty))
            if($script:txtSHA.Text -ne 'synthetic retained input'){throw 'Collapsing advanced options discarded input.'}
            $script:txtSHA.Text=''
            if(-not $script:WorkspaceAdvanced -or $script:txtSHA.Bounds.Height -lt 20){throw 'Advanced options did not expand.'}
            [void]$onClick.Invoke($script:btnAdvanced,[object[]]@([EventArgs]::Empty))
            Set-GuiBusy $true
            Select-WorkspaceOperation 'LabRepair'
            if((Get-GuiOperation) -ne 'Upgrade' -or $script:workspaceTabs[1].Enabled){throw 'Busy workspace allowed an operation change.'}
            Set-GuiBusy $false
            Update-GuiMode
            if (-not $script:chkDryRun.Checked -or (Get-GuiOperation) -ne 'Upgrade') { throw 'GUI defaults changed.' }
            $script:cboOperation.SelectedIndex=1
            if ((Get-GuiOperation) -ne 'LabRepair' -or -not $script:chkDryRun.Checked -or
                $script:txtMandatory.Text -match 'native Freshservice orchestration action' -or
                $script:chkRecovery.Text -notmatch 'checkpoint') { throw 'Lab UI selection was not applied.' }
            if ($script:txtRecoveryRoot.Text -ne $script:LabRunBase) { throw 'Lab selection did not choose the shorter default recovery root.' }
            function Get-OsrProduct { [pscustomobject]@{Version=[version]'2.5.0.0';ProductCode='synthetic'} }
            function Get-OsrMsiMetadata { throw 'Empty repair target must not reach MSI metadata inspection.' }
            function Get-OsrServiceRecords { @() }
            function Get-OsrWindowsBackupCapability { [pscustomobject]@{Status='SYNTHETIC';CandidateTargetCount=0} }
            $script:txtMsi.Text='   '
            foreach($previous in @('','C:\synthetic-recovery-only.msi')){
                $script:txtPrevious.Text=$previous
                $found=Find-RecoveryInstallerInGui
                if($found.Found -or $found.Verified -or $found.Verification -notmatch 'Same-version MSI' -or
                    $script:txtPrevious.Text -ne $previous){throw 'Missing repair target was not explained without promoting recovery media.'}
            }
            $script:lstLog.Items.Clear()
            Inspect-DryRunReadOnly
            $inspection=Get-GuiLogText
            if($inspection -notmatch 'Select the Same-version MSI field first' -or
                $inspection -match 'automatic recovery discovery unavailable|Cannot bind argument|A verified recovery MSI is locally available'){
                throw 'Dry Run did not explain the missing repair target clearly.'
            }
            if(-not $script:chkDryRun.Checked){throw 'Missing repair media changed the simulation mode.'}
            $script:txtMsi.Text='';$script:txtPrevious.Text='';$script:lstLog.Items.Clear()
            Write-Host 'PASS: missing same-version target produces actionable guidance; recovery-only input does not establish readiness'
            $script:txtLabComputer.Text='synthetic-guest'
            $script:chkApproval.Checked=$true
            $script:chkRecovery.Checked=$true
            $cfg=Get-GuiRunConfiguration -Questions @('synthetic acceptance')
            if ($cfg.RecoveryProcedureValidated -or -not $cfg.LabCheckpointConfirmed -or
                $cfg.LabExpectedComputerName -ne 'synthetic-guest') { throw 'Lab configuration promoted a checkpoint to validated recovery.' }
            $resume=Export-GuiResumeState
            $state=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($resume)) | ConvertFrom-Json
            if ($state.Operation -ne 'LabRepair' -or $state.LabExpectedComputerName -ne 'synthetic-guest') { throw 'Lab elevation payload is incomplete.' }
            $script:cboOperation.SelectedIndex=0
            if (-not $script:chkDryRun.Checked -or $script:chkApproval.Checked -or $script:chkRecovery.Checked) { throw 'Changing operation did not reset approvals and simulation.' }
            if ($script:txtRecoveryRoot.Text -ne $script:UpgradeRunBase) { throw 'Upgrade default recovery root changed.' }
            $script:chkRecovery.Checked=$true
            $upgradeCfg=Get-GuiRunConfiguration -Questions @('synthetic upgrade acceptance')
            if (-not $upgradeCfg.RecoveryProcedureValidated -or $upgradeCfg.LabCheckpointConfirmed) { throw 'Upgrade recovery gate configuration changed.' }
            Restore-GuiResumeState $resume
            Update-GuiMode
            if ((Get-GuiOperation) -ne 'LabRepair' -or $script:txtLabComputer.Text -ne 'synthetic-guest' -or
                $script:btnStart.Text -ne 'START LAB REPAIR' -or $script:chkDryRun.Checked) { throw 'Elevated lab state was not restored.' }
            $script:chkDryRun.Checked=$true
            if ($script:btnStart.Text -ne 'Start dry run' -or $script:lblStatus.Text -notmatch 'simulated') { throw 'Returning to simulation did not refresh the UI.' }
            $blocked=$false
            try { New-Run 'Deploy' } catch { if ($_.Exception.Message -match 'Dry Run is active') { $blocked=$true } else { throw } }
            if (-not $blocked) { throw 'GUI launched a worker during Dry Run.' }
            Select-WorkspaceOperation 'Diagnostic'
            if(-not $script:WorkspaceDiagnostic -or -not $script:chkDryRun.Checked -or $script:chkApproval.Checked -or
                $script:chkRecovery.Checked){throw 'Returning from lab to Diagnostic retained live state.'}
            Write-Host 'PASS: compact Workspace diagnostic lock, busy tabs, advanced value retention and approval resets'
            Select-WorkspaceOperation 'Upgrade'
            $script:chkApproval.Checked=$true
            $script:chkRecovery.Checked=$true
            $script:cboStrategy.SelectedIndex=1
            if((Get-GuiOperation) -ne 'Replacement' -or -not $script:chkDryRun.Checked -or $script:chkApproval.Checked -or $script:chkRecovery.Checked -or $script:chkMigration.Checked){throw 'Strategy selection did not reset live authorization.'}
            $script:chkMigration.Checked=$true
            $replacementResume=Export-GuiResumeState
            $script:cboStrategy.SelectedIndex=0
            Restore-GuiResumeState $replacementResume
            Update-GuiMode
            if((Get-GuiOperation) -ne 'Replacement' -or -not $script:chkMigration.Checked -or $script:btnStart.Text -notmatch 'REPLACEMENT'){throw 'Replacement elevation state was not preserved.'}
            $replacementConfig=Get-GuiRunConfiguration -Questions @('synthetic replacement acceptance')
            if(-not $replacementConfig.MigrationScopeApproved){throw 'Replacement migration scope was not exported.'}
            Select-WorkspaceOperation 'Diagnostic'
            if(-not $script:chkDryRun.Checked -or $script:chkMigration.Checked){throw 'Diagnostic retained replacement authorization.'}
            Write-Host 'PASS: replacement strategy reset, explicit migration approval and elevation handoff'
            if($env:OSR_GUI_PREVIEW_PATH){
                $script:lblLogCopy.Text='Activity log | Ctrl+C: copy selected | Ctrl+A: select all'
                $form.Size=New-Object Drawing.Size(1060,850)
                $form.Show()
                [Windows.Forms.Application]::DoEvents()
                Update-WorkspaceLayout
                try {
                    foreach($previewMode in @('Diagnostic','LabRepair','Upgrade','Replacement')){
                        Select-WorkspaceOperation $(if($previewMode -eq 'Replacement'){'Upgrade'}else{$previewMode})
                        if($previewMode -eq 'Replacement'){$script:cboStrategy.SelectedIndex=1}
                        if($previewMode -eq 'LabRepair'){
                            $script:WorkspaceAdvanced=$true
                            $form.Size=$form.MinimumSize
                            Update-WorkspaceLayout
                        }else{
                            $script:WorkspaceAdvanced=$false
                            $form.Size=New-Object Drawing.Size(1060,850)
                            Update-WorkspaceLayout
                        }
                        [Windows.Forms.Application]::DoEvents()
                        $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
                        $previewDirectory=Split-Path $env:OSR_GUI_PREVIEW_PATH -Parent
                        $previewName=[IO.Path]::GetFileNameWithoutExtension($env:OSR_GUI_PREVIEW_PATH)+'-'+$previewMode+'.png'
                        try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save((Join-Path $previewDirectory $previewName))}finally{$bitmap.Dispose()}
                    }
                }finally{$form.Hide()}
            }
            Write-Host 'PASS: actual GUI controls preserve Dry Run, operation reset, elevation payload and lab-specific labels'
        } finally { $form.Dispose() }
        function Read-OsrGuiSettings { @{MsiPath='C:\Synthetic\remembered.msi';PreviousMsiPath='C:\Synthetic\old.msi';InstallDirectory='C:\SyntheticOSR';BackupRoot='C:\Remembered\Runs';LabExpectedComputerName='remembered-guest';DryRun=$false;Operation='Replacement';MaintenanceApproved=$true} }
        function Save-OsrGuiSettings {param($Settings) $script:SavedTestPreferences=$Settings}
        . $tempFile
        try{
            if($script:txtMsi.Text -ne 'C:\Synthetic\remembered.msi' -or $script:txtRecoveryRoot.Text -ne 'C:\Remembered\Runs' -or
                -not $script:WorkspaceDiagnostic -or -not $script:chkDryRun.Checked -or $script:chkApproval.Checked -or
                $script:chkRecovery.Checked -or $script:chkMigration.Checked -or $script:cboStrategy.SelectedIndex -ne 0){throw 'Preference startup restored unsafe operation state or lost ordinary inputs.'}
            Save-GuiPreferences
            if($script:SavedTestPreferences.Count -ne 5 -or $script:SavedTestPreferences.MsiPath -ne 'C:\Synthetic\remembered.msi'){throw 'GUI preference save did not use the safe mapping.'}
            Write-Host 'PASS: remembered inputs reopen in Diagnostic/Dry Run with all live authorization cleared'
        }finally{$form.Dispose()}
    }
} finally {
    if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force }
}
