# Integrated Lab Repair

Status: one successful integrated live backup/repair/acceptance trial and one successful operator-accepted same-version installation-file restoration trial are recorded in [Manual Test Results](MANUAL_TEST_RESULTS.md). Broader restoration qualification and failure-injection trials remain pending. Local Windows PowerShell 5.1 regressions exercise the GUI controls and main worker using synthetic discovery, services, MSI results and operator decisions. The earlier standalone repair trial is separate evidence.

## Scope

The main GUI now selects `Upgrade` or `Lab Repair (same version)`. Both selections use `OSR.Upgrade.Worker.ps1`, the existing progress/decision channel and operator acceptance flow. The standalone `OSR.Repair.Lab.ps1` remains available for the earlier isolated experiment but is not invoked by this GUI workflow.

`Upgrade` remains the default operation and rejects an equal or older target version. Live upgrades still require maintenance authorization, authentic original previous-version media and an independently validated version-pair recovery procedure. Lab Repair cannot set that procedure-validation flag through the GUI.

Lab Repair requires the exact installed version and ProductCode, authenticated original media, a dedicated Hyper-V guest with its computer name explicitly entered, an approved lab change and operator confirmation that a host-side baseline checkpoint exists. That confirmation is an attestation, not independent checkpoint verification. These guest checks prevent common mistakes; they are not proof that a guest is disconnected from production. Do not assign production workflows or credentials to the lab entry.

## Safe defaults and elevation

The log area grows with the main window in both dimensions, and input fields expand horizontally. Use `Copy all logs` to copy the current journal, or select lines with Ctrl/Shift and use `Copy selected` or Ctrl+C. Ctrl+A selects all log lines when the log has focus. The same actions are available through the log's context menu. Copying is explicit and uses the clipboard only; Dry Run still creates no log file. Clipboard errors are shown in the log toolbar without changing the worker state.

- Dry Run is checked at startup and runs in memory without launching the worker, writing reports, controlling services or invoking MSI.
- Changing the operation re-enables Dry Run and clears live approval checkboxes.
- UAC elevation preserves the selected operation, guest name and user inputs. Declining elevation retains simulation.
- The worker validates lab environment, identity, package and approvals independently of GUI controls. Missing or malformed checkpoint/maintenance authorization fails closed.
- Windows Server Backup discovery remains read-only. No system recovery, snapshot restore, registry restoration or tenant workflow action is added.

## Trial 1: acceptance

1. Independently confirm the host-side OSR baseline checkpoint and copy the complete integrated GUI package into a new folder inside the guest. Do not mix files from the older standalone package.
2. Double-click `Start-Manager.cmd` at the package root. It starts the GUI using Windows PowerShell 5.1 with `-STA` and a process-scoped `RemoteSigned` policy; it does not change persistent execution policy. Alternatively start `src\Freshservice_OSR_Upgrade_GUI.ps1` with the same flags.
3. Select `Lab Repair (same version)`. Enter the guest's actual Windows computer name (shown by `$env:COMPUTERNAME` inside the guest); the Hyper-V display name may be different.
4. Select the original installed-version MSI. Lab Repair automatically uses this same original package as its recovery media; the previous-version MSI field is not used to choose a different repair product.
5. Review the installation and recovery storage directories. Recovery storage must be a separate local tree without reparse points or overlap with the installation.

   Lab Repair defaults to `<SystemDrive>\OSRLab\Runs` to reduce destination path length. Upgrade keeps its existing ProgramData default. The worker scans every proposed source/destination path before service control and rejects file paths of 260 or more characters and directory paths of 248 or more characters. These conservative limits support Windows PowerShell 5.1 environments with legacy path handling. No Windows long-path policy is changed and no file is skipped. If a custom root is too long, choose a shorter one and rerun preflight. Capture and restoration recheck this budget before copying.
6. Keep Dry Run checked for initial read-only inspection and simulation. The lab acceptance question concerns local service/version/configuration checks, not execution of production app nodes.
7. After reviewing the plan, leave Dry Run, approve UAC if required, confirm the lab authorization and current baseline checkpoint, then run preflight. Live preflight writes protected run diagnostics but does not control services, capture application files or invoke MSI.
8. Start Lab Repair and approve the explicit operation confirmation. Review the local service/version/configuration result and answer Yes to accept it.

Expected report: `Operation=LabRepair`, `Status=LAB_REPAIR_ACCEPTED`, `MsiExitCode=0`, `BackupIntegrity=INSTALLATION_TREE_VERIFIED`, with both Freshworks services running. This is lab operator acceptance, not proof of orchestration behavior or general recoverability.

## Trial 2: file restoration

Run the same GUI workflow again to create a fresh recovery point. At the post-repair acceptance prompt, deliberately answer No to exercise the decision branch, then explicitly approve restoration when offered. Do not damage or delete application files manually.

The main worker stops the Freshworks services, verifies the saved file tree against its in-memory inventory, restores it and compares content and file/directory security metadata with the captured baseline. Files introduced after capture are removed only within the validated installation tree. Reparse points, overlapping roots, unsafe relative paths and altered backup data cause restoration to stop. The guest computer, product identity and installation directory are rechecked before restoration. No MSI uninstall or cross-version reinstall is used for this lab branch.

After service restart, inspect the local state and answer the recovery-acceptance prompt. Expected report: `Status=LAB_FILES_RESTORED`, `Rollback=LAB_FILES_RESTORED_OPERATOR_ACCEPTED` and `LabFileRestoreVerified=true`. An MSI or restart failure must remain visible and must not be labelled a successful acceptance. Review reports and service state before deciding on any further operation.

## Capture boundary and reports

The lab inventory records file paths, SHA-256, sizes, empty directories and file/directory security descriptors. Source consistency is checked while the Freshworks services are stopped. Backups, manifests and logs reside under the protected run directory. Treat all of them as sensitive and keep them out of Git.

This is installation-tree recovery within the same worker run. It does not capture registry keys, service-account passwords, external dependencies or full-machine state. It does not provide crash-resumable restoration. A reconfiguration of MSI registration or a change to the product/installation path blocks the lab restoration branch. The host checkpoint remains the independent lab fallback; the program never applies or deletes it.

Neither lab acceptance nor file-restore success sets `CrossVersionRollbackValidated`. Smart Application Backup v0.5 and version-pair upgrade/downgrade qualification remain separate work.
