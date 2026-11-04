@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -File "%~dp0src\Freshservice_OSR_Upgrade_GUI.ps1"
if errorlevel 1 pause
