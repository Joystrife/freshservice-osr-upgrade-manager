# Architecture and execution model

Freshservice OSR Upgrade Manager is a Windows PowerShell 5.1 / Windows Forms GUI for operator-supervised **in-place** upgrades of the Freshworks Orchestration Server.

## Code modules

- `src/Freshservice_OSR_Upgrade_GUI.ps1`: English-language GUI, file selection, default-on in-memory Dry Run, read-only recovery media discovery, progress and operator prompts.
- `src/OSR.Upgrade.Core.psm1`: installed version, Windows services, MSI metadata and signature/hash, original MSI discovery and recovery environment diagnostics.
- `src/OSR.Upgrade.Worker.ps1`: authorized live preflight, protected recovery point, two-service stop/start, MSI execution, operator acceptance and integrated MSI-based application recovery.

## Automatic original-MSI discovery (v0.3)

The GUI's **Auto-find** function and the worker independently inspect the registered installation source, the selected upgrade package directory, common Downloads directories and earlier application recovery-point folders. They do **not** scan arbitrary disks or download historical software. A candidate is only accepted when it matches the exact installed version and Freshworks MSI identity and is authenticated by vendor signature or an independently supplied SHA-256.

The Windows Installer cache is not treated as fully reusable historical installation media.

## Recovery readiness

A backup of application files does not revert all changes Windows Installer makes. The application recovery procedure requires a verified original MSI plus a separately validated version-specific uninstall/reinstall/restore sequence.

Virtualization and Windows Backup checks are **diagnostic only**. They do not prove that a restorable snapshot exists and they cannot enable live deployment on their own. Full-VM restoration needs an independent controller that remains operational after the OSR guest has stopped or been restored. See [Recovery Providers](RECOVERY_PROVIDERS.md).

## Operational states

`PREFLIGHT` → `RECOVERY_DISCOVERY` → `BACKUP` → `INSTALL` → `HEALTH` → `ACCEPTANCE` → `DONE` or an approved `ROLLBACK` decision.

A manual functional test failure offers rollback, not an automatic destructive decision. Declining it records a NOT VALIDATED result.

**Release status:** Experimental. Cross-platform static checks passed; Windows runtime and version-specific recovery are still to be validated.
