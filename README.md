# Freshservice OSR Upgrade Manager

A generic Windows PowerShell 5.1 / Windows Forms application for **operator-supervised upgrades** of the Freshworks Freshservice Orchestration Server.

## Planned workflow

1. Choose the official `FO-OSR.msi` using **Browse**.
2. Detect or select the **existing installation directory**.
3. Run preflight checks (MSI version, identity, services, integrity).
4. Supply evidence of an approved backup and an independently validated recovery script.
5. Start the vendor MSI upgrade and monitor progress and logs.
6. Perform configurable manual acceptance tests in Freshservice.
7. If a test fails, choose whether to invoke the **approved rollback** procedure.
8. Export an audit report.

## Scope

The initial version targets **in-place upgrades** of an existing Windows Orchestration Server installation. Selecting a directory does **not** relocate an installed application. First-time installation and custom MSI directory properties need separate vendor validation.

An automatic downgrade is **not included**. Recovery requires an approved, independently tested script and restorable configuration. A successful MSI result does not by itself establish functional success.

## Requirements

- Authorized elevated Windows PowerShell 5.1 interactive session (STA)
- Official Freshworks installer
- Approved maintenance window, backup and restoration plan
- Manual functional acceptance tests after deployment

## Run

```powershell
powershell.exe -NoProfile -STA -File ".\src\Freshservice_OSR_Upgrade_GUI.ps1"
```

## Project safety

Do not commit MSI installers, deployment logs, host identifiers, configuration backups, credentials or private recovery scripts. Source code should remain vendor-generic.

## Status

**Early-stage / not production validated.** Test on an approved non-production system and verify the Freshworks-supported upgrade path before use in production.

## References

- [Freshworks Orchestration Server setup](https://support.freshservice.com/support/solutions/articles/50000003259-setting-up-the-orchestration-server)
- [Microsoft msiexec reference](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/msiexec)
