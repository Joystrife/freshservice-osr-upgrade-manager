# 0.5.0 Known Issues and Validation Limits

This list applies to `v0.5.0`. A successful lab trial is evidence for that scenario, not a general production-readiness claim.

| Area | Current boundary |
| --- | --- |
| Cross-version Upgrade/rollback | Not validated; original OSR 2.4 media was unavailable for the intended 2.4/2.5 pair |
| Same-version Lab Repair | Operator-accepted GUI/worker repair and file-restoration trials, including the portable Workspace GUI; additional failures/reboots still need qualification |
| Application capture | Installation files, empty directories and security metadata; registry, external dependencies and account secrets are excluded |
| Independent verification | Live file comparisons were performed by the worker; the complete retained payload was not independently rehashed outside it |
| Recovery after crash | No restartable recovery session or external recovery controller |
| Windows Server Backup | Discovery and command planning only; no creation or WinRE recovery execution |
| Lab isolation | Guest-name/Hyper-V checks and checkpoint confirmation are operator safeguards, not attestation or automated checkpoint verification |
| Cancellation/concurrency | No robust cancellation or host-wide interprocess lock; do not run concurrent live instances |
| Packaging | Source ZIP and unsigned portable EXE; no Authenticode publisher identity or established SmartScreen reputation |

## Path length

An early real capture failed at a 261-character destination under the longer ProgramData run root. Services were restarted and no MSI was reached. The corrected lab root is `<SystemDrive>\OSRLab\Runs`.

The main worker now scans proposed paths before service control, and capture/restore recheck them. File paths of 260 or more characters and directory paths of 248 or more are conservatively rejected for Windows PowerShell 5.1 compatibility. This release does not enable long-path policy, skip offending files or promise arbitrary long-path support. Choose a shorter approved local root when a path-budget error is reported.

## Simulation versus readiness

Dry Run intentionally walks the UI despite missing inputs or readiness warnings. An equal-version Upgrade may end in simulated acceptance while the real worker correctly refuses it. A discovered authentic MSI, including one copied into an incomplete old run, proves only that media's identity/authenticity, not completeness of that run's application backup.

## Permissions and state

Re-enabling Dry Run does not drop an already elevated process token. The privilege indicator describes Windows privileges; the mode indicator describes simulation versus real execution. Close and restart normally to obtain a non-elevated process.

Live preflight writes run diagnostics even though it does not modify OSR. Missing optional uninstall registry fields are handled; a blank InstallLocation can be resolved through the Freshworks service path. If required discovery is ambiguous or inaccessible, a live operation must remain blocked.

Configuration/log files may legitimately change when services run. Service status and tenant ONLINE state do not establish complete configuration equivalence, workflow execution or recovery coverage. No production workflow execution was part of the recorded lab qualification.

## Evidence still needed

- Missing/corrupt-file recovery and genuine MSI/service failure injection in the lab.
- Repeated trials across representative supported Windows Server deployments and upgrade version pairs.
- Independent payload/configuration comparison, reboot and crash-recovery qualification.
- The development portable launcher has automated build, payload-integrity and extraction checks. Workspace startup, read-only inspection, simulations and same-version file restoration were observed in the lab. Standard-user/UAC cancellation and representative Windows policy acceptance are still incompletely qualified. See [Portable Executable](PORTABLE_EXECUTABLE.md).

See [Manual Test Results](MANUAL_TEST_RESULTS.md) for the actual observations rather than inferred guarantees.
