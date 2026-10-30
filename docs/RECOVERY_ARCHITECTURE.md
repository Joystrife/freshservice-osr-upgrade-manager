# Recovery Architecture

## Purpose

Freshservice OSR Upgrade Manager is moving from a single MSI-based recovery sequence to an extensible **Recovery Provider Manager**. Its job is to assess recoverability before authorizing a disruptive Orchestration Server upgrade.

The application must remain independent of the infrastructure vendor. AWS, Hyper-V, VMware and physical Windows servers are deployment contexts, not implicit proof of recovery capability.

## Provider contract

Each recovery provider is designed around five stages:

| Phase | Meaning | Can authorize deployment? |
| --- | --- | --- |
| `DISCOVER` | Inspect the environment and identify available recovery technology | No |
| `PLAN` | Select source volumes, backup destination, prerequisites and recovery procedure | No |
| `PREPARE` | Create a backup/snapshot and capture its immutable identifier | No |
| `VERIFY` | Verify backup completion, source coverage, readable catalog and tested restoration procedure | Potentially, if policy allows |
| `RESTORE` | Invoke a validated and authorized recovery sequence | Only after operator approval |

The GUI must never equate `DISCOVERED` with `RESTORE_READY`.

## v0.4.0 implementation: Windows Server Backup discovery

Module: `src/OSR.Recovery.WindowsServerBackup.psm1`.

Implemented operations:

- Check for `wbadmin.exe`.
- Inspect `Windows-Server-Backup` feature when Windows Server feature management is available.
- Determine Windows and OSR source drive letters.
- List other local fixed disks as **potential**, unverified backup destinations.
- Prepare a command preview using `-allCritical`, `-vssCopy` and `-include` when OSR is on a different drive.
- Reject backup destinations within source volumes or outside accepted drive/UNC-share syntax.
- Return status flags that explicitly prohibit claiming backup or restoration success.

Not implemented:

- Feature installation, backup creation, catalog validation, verification of free space, testing restoration, full-system recovery, or external recovery controller.
- Automatically selecting a destination from candidates.
- Elevating a candidate volume to a trusted backup target merely because it appears in WMI.
- Automatic server rollback using `wbadmin start sysrecovery`.

The **Check Windows backup** GUI button is read-only in both Dry Run and Live Mode. It does not change the Windows Backup schedule, services, disk settings or files.

## Future Windows Server Backup preparation

1. Select an approved, independent backup target; do not write to a volume being protected.
2. Confirm free space, access permissions, backup job concurrency and retention.
3. Include all Windows critical volumes and any separate OSR installation volume.
4. Initiate a Windows Server Backup operation using an elevated `wbadmin` context.
5. Wait for actual completion, inspect backup catalog/version identifier and report any partial errors.
6. Record backup ID, target, time and covered volumes in a protected local manifest.
7. Only mark the recovery point as ready once the restore path can actually be executed.

A confirmed WSB backup and a working full-system recovery are separate facts.

## Windows recovery boundary

Microsoft documents `wbadmin start backup` for online backup. The full-system `wbadmin start sysrecovery` command runs from Windows Recovery Environment (WinRE), not inside the running server. As a result, the OSR GUI cannot simply reverse a system update by executing this command in the same Windows session.

Future hands-free full-system rollback requires a separately running, authorized controller capable of placing the machine into a recovery environment, executing the restore and reconnecting to confirm health. Such a controller is **not implemented** in v0.4.0.

## Extensibility

| Provider | Discovery | Backup preparation | Restore |
| --- | --- | --- | --- |
| Windows Server Backup | Implemented (read-only) | Planned | Planned; WinRE/external controller |
| Previous-version MSI + OSR files | Implemented | Implemented; real runtime unverified | Implemented; requires approved version-specific procedure |
| AWS EC2/EBS | Platform diagnostic only | Not implemented | Not implemented |
| Hyper-V | Diagnostic only | Not implemented | Not implemented |
| VMware | Not implemented | Not implemented | Not implemented |

## Safety rules

- Default to in-memory Dry Run.
- Do not auto-install Windows Server features or trigger WSB during a diagnostic.
- Do not infer a restorable backup from a Windows Backup command, VSS, an EC2 instance or a hypervisor model.
- Require real, independent proof of recovery before authorizing a live upgrade with a new provider.
- Never invoke full-system rollback without explicit operator authorization.
- Do not log plaintext credentials, secrets or contents of protected OSR configuration.

## References

- [Microsoft — wbadmin start backup](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wbadmin-start-backup)
- [Microsoft — wbadmin get versions](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wbadmin-get-versions)
- [Microsoft — wbadmin start sysrecovery](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wbadmin-start-sysrecovery)
