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
        . $tempFile
        try {
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
            if (-not $script:chkDryRun.Checked -or (Get-GuiOperation) -ne 'Upgrade') { throw 'GUI defaults changed.' }
            $script:cboOperation.SelectedIndex=1
            if ((Get-GuiOperation) -ne 'LabRepair' -or -not $script:chkDryRun.Checked -or
                $script:txtMandatory.Text -match 'native Freshservice orchestration action' -or
                $script:chkRecovery.Text -notmatch 'checkpoint') { throw 'Lab UI selection was not applied.' }
            if ($script:txtRecoveryRoot.Text -ne $script:LabRunBase) { throw 'Lab selection did not choose the shorter default recovery root.' }
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
            Write-Host 'PASS: actual GUI controls preserve Dry Run, operation reset, elevation payload and lab-specific labels'
        } finally { $form.Dispose() }
    }
} finally {
    if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force }
}
