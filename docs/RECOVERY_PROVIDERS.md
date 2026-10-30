# Recovery Provider Inventory

This document tracks **implemented functionality**, not the desired end-state.

| Provider | Status | Backup creation | Full restoration |
| --- | --- | --- | --- |
| Windows Server Backup | Read-only capability and plan provider introduced in v0.4 | Not implemented | Not implemented; full recovery requires WinRE or an external controller |
| Original previous OSR MSI | Bounded local discovery + verified original package | Protected OSR file copy; real operation not validated | Application-level MSI recovery logic implemented; requires independent version-specific validation |
| AWS EC2/EBS | Hardware/platform diagnostic only | Not implemented | Not implemented |
| Hyper-V | Presence may be detected | Not implemented | Not implemented |
| VMware | Not implemented | Not implemented | Not implemented |

## Provider selection

A provider can progress through `DISCOVERED`, `PLAN_CREATED`, `BACKUP_COMPLETED`, `RECOVERY_VERIFIED` and `RESTORE_AVAILABLE` states only after the corresponding real operations and evidence checks succeed.

A detected backup tool or virtual-machine model does **not** satisfy these checks.

## Windows Server Backup

The v0.4 module detects an installed Windows Backup feature, queries candidate separate fixed volumes and validates example target syntax. It generates a **command preview only**. It never installs the Windows feature, executes `wbadmin`, creates backup files or changes Windows configuration.

Microsoft documents `wbadmin start backup` for backup and `wbadmin start sysrecovery` from the recovery console. Consequently, autonomous full-system recovery will require an out-of-guest control mechanism.

## Operational design requirement

Only allow a live upgrade when the chosen provider can actually prepare and recover an appropriate point according to an independently validated method. The previous MSI flow remains the only live recovery implementation in v0.4 and is still explicitly gated.

[Read the full recovery architecture](RECOVERY_ARCHITECTURE.md).
