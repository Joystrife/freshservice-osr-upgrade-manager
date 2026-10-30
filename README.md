# Freshservice OSR Upgrade Manager

**Environment-aware deployment and recovery management for the Freshworks Freshservice Orchestration Server.**

[![PowerShell 5.1 checks](https://github.com/Joystrife/freshservice-osr-upgrade-manager/actions/workflows/powershell-syntax.yml/badge.svg)](https://github.com/Joystrife/freshservice-osr-upgrade-manager/actions/workflows/powershell-syntax.yml)

**Release: v0.4.0 — experimental development preview.** This is a community project, not an official Freshworks application. The GUI runs on Windows PowerShell 5.1 and Windows Forms. **Windows server upgrades, backups and recovery have not been validated end-to-end in a production environment.**

## Vision

The application aims to reduce the number of manual tasks required to maintain a Freshservice Orchestration Server:

**Detect environment → Select official installer → Assess recovery → Create a recoverable point → Deploy → Verify → Accept or Restore**

A future recovery-provider architecture will select capabilities based on **what can actually be created and restored**, not merely which hypervisor or cloud vendor the host reports.

## Current capabilities

| Capability | Status |
| --- | --- |
| English-language Windows Forms GUI | Implemented |
| Default-on, in-memory Dry Run | Implemented |
| Administrator elevation through Windows UAC when entering Live Mode | Implemented; Windows acceptance testing ongoing |
| Installed OSR version and Freshworks service discovery | Implemented |
| Official MSI metadata and signature/checksum validation | Implemented |
| Automatic search for a matching previous original OSR MSI | Implemented (bounded local search; cannot download old versions) |
| Controlled Windows service stop/start around MSI deployment | Implemented; real deployment not validated |
| Manual post-installation functional acceptance | Implemented |
| Previous-MSI-based application recovery engine | Implemented but **requires independently validated downgrade procedure** |
| Windows Server Backup (WSB) feature, command and destination candidate discovery | **New in v0.4.0: read-only only** |
| WSB backup command preview with source/target volume validation | **New in v0.4.0: no command execution** |
| Automatic creation of a Windows Server Backup | Not implemented |
| Full-system recovery automatically executed through WinRE or an external controller | Not implemented |
| AWS / Hyper-V / VMware provider integration | Planned, not implemented |
| First-time OSR installation or relocation | Planned, not implemented |

**A Windows Server Backup command or a hypervisor name is not sufficient evidence that a usable recovery point exists.** The current live-upgrade workflow remains gated by a verified older MSI **and** an independently validated, version-specific application recovery procedure. A WSB capability assessment does not unlock it.

## Quick start: safe Dry Run

Download or clone the repository on a Windows host. Run from the project root:

```powershell
powershell.exe -NoProfile -STA -File ".\src\Freshservice_OSR_Upgrade_GUI.ps1"
```

- **DRY RUN** is checked on startup. The simulated upgrade, backup, service changes and rollback do not modify the server; logs remain in memory.
- **Auto-find** searches for a trustworthy original previous-version MSI without changing software.
- **Check Windows backup** detects Windows Server Backup and candidate backup volumes. This is also read-only.
- If Live Mode is requested, UAC requires a confirmed elevated administrator session. Declining elevation leaves Dry Run enabled.
- Do **not** perform a production upgrade unless its supported recovery procedure has been independently tested and approved.

## Windows Server Backup integration — v0.4.0

`src/OSR.Recovery.WindowsServerBackup.psm1` introduces a Microsoft-native provider:

1. Checks the presence of `wbadmin.exe` and the Windows Server Backup feature when the relevant Windows feature command is available.
2. Detects Windows and OSR installation volumes.
3. Lists other local fixed volumes as **unverified** destination candidates.
4. Builds a non-executing `wbadmin start backup` command preview that includes critical OS volumes and, when separate, the OSR source volume.
5. Rejects targets on source volumes and invalid local/UNC destinations.

This version does **not** create full Windows backups, install Windows features, start or stop backup jobs, or restore a machine. Full-system recovery via `wbadmin start sysrecovery` must run from Windows Recovery Environment. A production-grade remote recovery controller is a separate milestone.

See [Recovery Architecture](docs/RECOVERY_ARCHITECTURE.md) and [Roadmap](ROADMAP.md).

## Source layout

```text
src/
  Freshservice_OSR_Upgrade_GUI.ps1       # Windows Forms GUI and in-memory Dry Run
  OSR.Upgrade.Worker.ps1                 # Controlled upgrade + operator decisions
  OSR.Upgrade.Core.psm1                  # MSI, services, product and local recovery
  OSR.Recovery.WindowsServerBackup.psm1  # Read-only Windows backup provider v0.4
tests/
  Test-RegistryDiscovery.ps1
  Test-WindowsBackupProvider.ps1
docs/
  DESIGN.md
  INSTALLATION.md
  RECOVERY_ARCHITECTURE.md
  RECOVERY_PROVIDERS.md
.github/workflows/
  powershell-syntax.yml
ROADMAP.md
CHANGELOG.md
```

## Security and responsible operation

Never commit MSI installers, recovery-point files, registry exports, service credentials, private keys, backup archives, machine identifiers or execution logs. Preserve restrictive Windows file permissions on backup data. Dry Run does not validate a real upgrade; a successful application MSI install does not prove the orchestration workflows still function.

GitHub Actions executes **Windows PowerShell 5.1 syntax checks and mock-style regression tests**. These tests do not create backups, stop services, or run installations.

## Official references

- [Freshworks — Setting up the Orchestration Server](https://support.freshservice.com/support/solutions/articles/50000003259-setting-up-the-orchestration-server)
- [Microsoft — Windows Server Backup command reference](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/windows-server-backup-command-reference)
- [Microsoft — wbadmin start backup](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wbadmin-start-backup)
- [Microsoft — wbadmin start sysrecovery](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wbadmin-start-sysrecovery)

## License

A project-wide license has not been selected. Public visibility does not, by itself, grant permission to redistribute or modify the code. A license will be added once the project owner confirms the applicable rights and preferred terms.
