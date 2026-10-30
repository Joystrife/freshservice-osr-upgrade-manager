# Recovery Provider Architecture

## Objective

Reduce operator effort while ensuring that **Recovery Ready** refers to a recovery procedure the application can actually execute and validate, not merely to the presence of files, a backup utility or a virtual machine.

## Provider A — Verified original MSI + application snapshot (experimental)

**Implemented in v0.3.0.** The system attempts read-only discovery of the original previously installed OSR MSI. It verifies the Freshworks product identity and exact installed version and requires either a valid Freshworks Authenticode signature or an independently validated SHA-256.

During an authorized live upgrade, the worker stops the two Freshworks services, creates a protected application-file snapshot, copies the original MSI and uses the new MSI. A recovery attempt involves the previous verified MSI, backed-up OSR files and operator confirmation. The procedure is **not** automatically assumed compatible across arbitrary version pairs. An independently validated downgrade remains mandatory.

No full-machine, OS registry, service database, external connectivity or virtualization state is reverted by this provider.

## Provider B — Hypervisor-level recovery (design target, not implemented)

The target architecture uses an authorized **out-of-band controller** running on the virtualization management side (for example a Hyper-V host or a protected management service). This controller would create a production checkpoint *before* upgrade, verify its identity/readiness, and remain running even if the guest OSR VM stops or loses connectivity.

In case of a failed application acceptance test, the GUI could request a recovery through that controller. Because restoring a VM may terminate the guest, the controller must own the restore job, provide confirmation after restart and handle loss of the GUI session. A Hyper-V production checkpoint is not an independent long-term backup and must comply with the host's storage and retention policy.

**No host credentials, VM names, hypervisor addresses or privileged task scheduling are embedded in this repository.** A genuine provider must implement authorization, durable execution, compatibility checks and post-restore verification before it can be treated as ready.

## Provider C — Windows Server Backup (diagnostic only)

The GUI can detect availability of `wbadmin.exe`. This does **not** establish that an appropriate, successful, recent and recoverable system backup exists. An image-based restore can require a recovery environment and may terminate the current OS session. Consequently it is not offered as automatic rollback in v0.3.0.

## Readiness states (target)

| State | Meaning | Upgrade authorization |
| --- | --- | --- |
| `DISCOVERED` | Candidate backup/package exists, authenticity or restore path not verified | Block |
| `VERIFIED` | Components and identity verified but no validated restoration procedure | Block |
| `RECOVERY_READY` | Approved provider can carry out and verify restore for this version/host | Eligible after authorization |
| `UNAVAILABLE` | No recoverable provider | Block |

A UI checkbox alone must never turn an unavailable provider into a recoverable provider.

## Sources

- Microsoft: [Hyper-V checkpoints](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/checkpoints)
- Microsoft: [Windows Installer rollback limitations](https://learn.microsoft.com/en-us/windows/win32/msi/rollback-installation)
- Microsoft: [`wbadmin`](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wbadmin)