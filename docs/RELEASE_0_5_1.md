# 0.5.1 preview: controlled application replacement

This experimental prerelease is version **0.5.1-preview.3**, displayed as **0.5.1 Preview 3**. It is not version 5.1.3. One integrated replacement-and-recovery trial completed in the dedicated Windows Server 2019 VM. No production readiness, AD workflow validation or full-system recovery is claimed.

## Integrated Preview 3 lab result

The operator supplied the complete activity journal for the 2026-11-03 trial. It records a verified 11,859-entry backup, explicit removal of 2.4, installation of the authenticated 2.5 target, identity-file migration and service startup. A screenshot showed the dedicated lab entry ONLINE. The required orchestration-action test was deliberately not accepted because that business workflow was not exercised.

After operator-approved recovery, the worker removed the recognized target, reinstalled the original MSI and restored the original tree and permissions. The restored 11,859-entry inventory passed comparison. The journal records recovery acceptance and completion at 13:35:35; a screenshot showed the lab entry ONLINE again. This is one observed trial on one VM and this inspected media pair. The final `report.json` was not supplied for independent review. Retain the run's protected logs and report as local evidence.

Download the portable EXE, readable source ZIP and `SHA256SUMS.txt` from the release assets. Windows PowerShell 5.1, 64-bit Windows and .NET Framework 4.7.2 or later are required. No Freshworks MSI or credentials are included. See [portable instructions](PORTABLE_EXECUTABLE.md).

## Preview 2: interrupted backup diagnostics

The first integrated VM trial ended during source hashing after 11,800 entries, without a final report. Both Freshworks services remained stopped and were restarted manually. The activity log contains no exception, so the root cause remains unknown; that trial did not qualify replacement or recovery.

Preview 2 captures worker standard error/output separately in the protected run directory and records exception type/message/stack in `worker-failure.log`. The GUI displays the worker exit code when its final report is absent. Before-deployment failure handling attempts to restart Freshworks services before writing diagnostics; the `finally` path also attempts this cleanup if it has not already run. A hard process termination or operating-system failure cannot be recovered by this in-process cleanup.

State/report writes now use atomic replacement with bounded retries for transient I/O sharing failures. Synthetic regressions inject persistent activity-log and state-write failures during capture and check that services restart without MSI execution. These fixes do not establish the cause of the original VM interruption. Retain the old run for investigation and use the clearly labelled Preview 2 for the next controlled trial.

## What changed

Preview 3 addresses activity-log contention. The Preview 2 VM trial failed before deployment with an explicit sharing violation on `activity.log`; its log records that services were restarted. The GUI now reads the activity log with explicit read/write/delete sharing, and the writer retries transient I/O failures for a bounded interval. Incomplete trailing lines are deferred until the next poll. Tests cover reading with an open writer, subsequent line completion, transient write contention and persistent diagnostic failure. The conflicting process in the VM was not identified directly; GUI polling was a plausible contributor. No replacement MSI stage was reached in that failed trial.

- Upgrade now offers an explicit **Controlled replacement** strategy for the inspected, signed 2.4.0.0 -> 2.5.0.0 MSI pair. Exact versions, ProductCodes and SHA-256 values are checked. Other packages are rejected by this strategy.
- The known failing native in-place 2.4 -> 2.5 path is blocked. Its lab log showed an existing `osr/Osr.jar` during archive extraction, followed by installer cleanup and exit 1603. Exit 1603 by itself is not a diagnosis.
- Before uninstalling, the worker captures and verifies the offline installation tree, its security metadata and protected copies of both installers. File path budget and available disk space are checked before services stop.
- Replacement explicitly uninstalls the old product, confirms removal, installs the new product, then copies **only `osr/config/osr.conf`** from the verified backup. New binaries and the new `application.conf` defaults remain. Proxy settings, custom application settings, registry data and external dependencies are outside this migration scope. Explicit scope approval is required.
- Recovery accepts a recognized original/target registration or an absent product. It removes a recognized installation when necessary, reinstalls the verified original MSI, restores the complete original tree and permissions, and verifies the restored inventory. Ambiguous registrations, unrelated products, corrupt backups and residual unregistered folders stop automatic recovery for manual review. Residual folders are never automatically deleted.
- MSI results 3010/1641 stop the sequence for reboot review. No automatic reboot or further MSI action follows. Concurrent workers are refused; interrupted operations require manual investigation.
- The default recovery root is `%SystemDrive%\OSR\Runs`, including Upgrade. Hashing, copying, verification and permission restoration report progress. Reports distinguish file verification, identity migration and operator acceptance; Freshservice connectivity is not automatically tested.
- Ordinary paths and the lab computer name are saved on close using per-user Windows DPAPI encryption under `%LOCALAPPDATA%\FreshworksOSRUpgradeManager\Preferences\settings.dat`. Mode, strategy, approvals, hashes, acceptance questions and credentials are not persisted. Every ordinary startup opens Diagnostic with Dry Run enabled. UAC handoff preserves the current explicitly selected operation separately.

## Evidence and limits

Before the integrated Preview 3 trial, the dedicated Windows Server 2019 lab independently exercised the same explicit replacement and recovery sequence through separate PowerShell commands. Both types of trial establish bounded application/connectivity evidence, not business-workflow qualification.

Synthetic worker tests cover accepted replacement, rejected acceptance followed by recovery, missing/partial installations, unrecognized registration, corrupt capture, missing approvals, failed MSI operations and reboot-required outcomes. These tests do not execute a real OSR MSI. The Windows PowerShell 5.1 release checks also exercise preferences, GUI state transitions and portable payload integrity.

## VM qualification procedure

1. Preserve an external baseline/recovery option for the dedicated lab. Keep original signed 2.4 and 2.5 installers outside the application installation directory. Do not use a production workflow for this test.
2. Start from a running 2.4 installation. Record version, both Freshworks service states and the lab entry's connectivity. Record any custom/proxy settings; this preview does not migrate them.
3. Open **Upgrade**, select **Controlled replacement**, choose the 2.5 target and 2.4 recovery MSI, and use a short protected recovery root. Start with Dry Run and read-only inspection.
4. Run live preflight. It inspects prerequisites and writes a diagnostic report; it does not install or back up OSR.
5. Only after confirming the maintenance authorization, independently tested recovery procedure and identity-only scope, start replacement. Expect service interruption. Keep the application open and retain all recovery files.
6. Verify actual installed version, both services, expected configuration and Freshservice connectivity. Complete the required functional checks before answering Yes. ONLINE is evidence of connectivity only.
7. In a separate controlled trial, answer No to acceptance and Yes to recovery. Verify original version, restored configuration, services, connectivity and required checks before accepting recovery. Preserve the protected reports and MSI logs; redact before sharing.

Do not mark the recovery procedure as independently tested merely to bypass a gate. If it is unavailable, remain in Dry Run. Full machine snapshots, Windows backup execution and crash-resume orchestration are outside this release.
