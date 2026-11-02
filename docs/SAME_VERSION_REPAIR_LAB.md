# Same-Version Repair Lab

Status: experimental lab tooling; one successful same-version repair trial is recorded in [Manual Test Results](MANUAL_TEST_RESULTS.md). Restoration and failure scenarios have not yet been validated. This is separate from Smart Application Backup v0.5 and does not implement a production recovery provider.

## Purpose

Exercise the existing OSR core discovery and service-control functions with the original installer for the installed version. The dedicated entry point is `src/OSR.Repair.Lab.ps1`. The production worker and GUI retain their existing upgrade gates: equal or older target versions remain blocked.

The MSI helper now accepts an explicit `Repair` operation. Before launching Windows Installer, this operation requires an administrator token, Freshworks package authenticity, the exact installed version and the same registered ProductCode. It invokes `/fomus` with `/norestart`; a reboot-required exit code is returned for operator review. Actual Freshworks maintenance behavior must be observed in the lab, not assumed from these switches.

## Prerequisites

- A dedicated Hyper-V guest with OSR installed and both Freshworks services running.
- A verified original MSI for exactly the installed version and product identity.
- A baseline checkpoint created and independently confirmed on the Hyper-V host. The runner cannot verify that checkpoint from inside the guest; `CheckpointConfirmed` is an operator attestation, not independent proof.
- No production workflow assigned to the lab entry. Do not test app-node execution as part of this protocol.
- A selected local backup root outside the installation tree. No production hosts, credentials or tenant identifiers belong in the repository.

## First run: read-only plan

Copy the source package into `C:\OSR-Lab\Manager` inside the guest. Keep the original MSI at `C:\OSR-Lab\FO-OSR.msi`. In Windows PowerShell inside the guest:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "C:\OSR-Lab\Manager\src\OSR.Repair.Lab.ps1"
```

Without `Execute`, the script only inspects the guest and package and returns an in-memory plan. It does not create reports or backups, control services or launch an installer. Verify exact version, product identity, discovered installation directory and both service states before proceeding.

## Explicit live lab run

Only after reviewing the plan and confirming the baseline checkpoint, run the following inside the intended guest in an elevated Windows PowerShell session:

```powershell
& "C:\OSR-Lab\Manager\src\OSR.Repair.Lab.ps1" `
    -ExpectedComputerName $env:COMPUTERNAME -CheckpointConfirmed -Execute
```

The runner requires a Hyper-V guest and explicit matching computer name. These checks prevent common operator mistakes; they are not cryptographic attestation of a trusted laboratory. Keep the script away from production guests.

The live sequence is:

1. Establish a new protected run directory accessible to SYSTEM and local administrators.
2. Stop only the two Freshworks services. The native Windows WinRM service is not managed.
3. Inventory and copy installation files under the protected directory. Compare source inventory before and after copying and compare the captured file set, lengths and SHA-256 hashes.
4. Save and hash-check a copy of the original MSI; retain file security metadata and a limited service inventory in a protected manifest.
5. Repair from the verified saved MSI. Recheck installed version and ProductCode after successful MSI completion.
6. Attempt to restart both Freshworks services even after failure, and write a protected result report. Failures and reboot requests require operator review.

## Evidence and limitations

- Live reports and MSI logs remain inside the protected guest backup directory. They can contain sensitive application information; do not publish them or copy configuration contents into chat.
- `INSTALLATION_TREE_VERIFIED` means captured file content matched a stable source inventory. It does not establish restore readiness.
- This limited capture excludes registry data, empty directories, directory ACLs, external dependencies and service-account secrets. It is not the planned complete Smart Application Backup.
- A successful repair does not prove restoration, cross-version upgrade/downgrade, or orchestrations. No automatic restore is attempted by this runner.
- Verify services and configuration after repair and record any unexpected changes. Restoration testing will be a separate explicit lab phase. A host checkpoint remains the laboratory fallback; no checkpoint is automatically applied or deleted.
- Regression tests use synthetic discovery and a mocked process launcher. They do not run MSI, modify services or validate the live copy/restart sequence.

## Current manual evidence

The first guest Dry Run exposed a Windows PowerShell 5.1 COM output issue: `Get-OsrMsiMetadata` emitted two null method results around its metadata record, causing a missing `Path` property error. The fix discards the `Execute` and `Close` return values. A regression test now creates and reads a temporary synthetic MSI through the real COM API rather than mocking this interaction. No installer execution is involved in that test. A subsequent guest screenshot confirms the corrected Dry Run completed successfully.

Operator screenshots show OSR 2.5.0.0 registered, both Freshworks services running and the dedicated lab entry online after a fresh installation. A host-side baseline checkpoint was also shown. The subsequent live repair report returned MSI exit code 0 without capture/restart errors; the MSI log confirms successful reconfiguration. Post-repair screenshots show both Freshworks services running and the lab entry online. This qualifies the observed baseline repair trial only, not restoration, injected-failure recovery, or cross-version operations.
