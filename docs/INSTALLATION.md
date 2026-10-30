# Running the Upgrade Manager

1. Copy the project to a Windows host with an existing Freshservice Orchestration Server installation.
2. Open an **authorized elevated Windows PowerShell 5.1 session** in STA mode.
3. Run `src/Freshservice_OSR_Upgrade_GUI.ps1`.
4. Use **Browse** to select the official `FO-OSR.msi` and confirm the detected existing installation directory.
5. Select independently approved backup evidence and a tested recovery script.
6. Run **Preflight** before starting the upgrade.
7. Deploy only in an approved maintenance window.
8. Execute the prompted functional tests and answer accurately. If a test fails, the operator is offered a rollback choice.

## Important

The initial version only upgrades **in place**; the chosen installation directory is a consistency check, not an instruction to relocate the MSI installation.

A recovery script must be specific to the supported vendor/version recovery procedure and independently validated. Do not publish site-specific recovery scripts, credentials, MSI files, logs, or backups.
