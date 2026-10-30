# Technical Design

## Project scope

Freshservice OSR Upgrade Manager is an English-language, Windows PowerShell 5.1 and Windows Forms application for controlled lifecycle operations on Freshworks Freshservice Orchestration Server.

The design consists of four components:

| Component | Responsibility |
| --- | --- |
| `Freshservice_OSR_Upgrade_GUI.ps1` | Graphical interface, user-driven execution, progress, default-on Dry Run, UAC elevation and read-only discovery |
| `OSR.Upgrade.Core.psm1` | OSR registration, native Freshworks services, Windows Installer package inspection and basic application recovery operations |
| `OSR.Upgrade.Worker.ps1` | Authorized MSI-based upgrade worker, file recovery point, operational checks and operator approval |
| `OSR.Recovery.WindowsServerBackup.psm1` | Microsoft backup capability assessment, source/target validation and command planning; **read-only in v0.4** |

## Current workflow

**Dry Run:** read-only environment inspection → simulated backup → simulated Freshworks service stops → simulated MSI upgrade → simulated restarts → simulated functional acceptance → simulated rollback choice.

**Live mode:** UAC → operator approval → version/MSI/service preflight → verified original previous-version MSI → stop Freshworks services → copy OSR files → MSI upgrade → restart Freshworks services → functional acceptance → keep or attempt approved application recovery.

**Important:** The Live MSI path has not been validated for all Freshworks versions and is still gated by confirmed prior media and an independently tested version-specific recovery procedure.

## Recovery providers

The recovery manager will eventually evaluate discovery, planning, backup creation, validation and restoration as independent stages. It must not select a provider solely on `Win32_ComputerSystem.Manufacturer` or other vendor labels.

The Windows Server Backup provider introduced in v0.4 performs only **discovery and non-executing planning**. It reports candidate backup targets but does not mark them safe or restore-ready.

The two Freshworks Windows services are `Orchestration Server` and `Orchestration Server - WinRM_SSH`. The native Windows `WinRM` service is not stopped.

See [Recovery Architecture](RECOVERY_ARCHITECTURE.md), [Recovery Providers](RECOVERY_PROVIDERS.md) and [Roadmap](../ROADMAP.md).

## Verification

GitHub Actions validates PowerShell 5.1 source syntax and runs regression tests for incomplete uninstall registry entries and Windows Server Backup target validation. These tests do not install MSI packages or verify live backup/recovery.

## References

- [Freshworks Orchestration Server setup](https://support.freshservice.com/support/solutions/articles/50000003259-setting-up-the-orchestration-server)
- [Microsoft Windows Server Backup](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/windows-server-backup-command-reference)
