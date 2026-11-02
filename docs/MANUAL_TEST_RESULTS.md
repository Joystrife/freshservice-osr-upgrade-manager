# Manual Test Results - v0.4 Preview

Evidence: operator-provided screenshots reviewed during development, plus a local repair report and MSI log reviewed for the dedicated lab trial below. Initial GUI observations used an extracted v0.4 archive whose exact commit was not established. Lab repair used the separate experimental runner with the MSI COM output fix. No environment identifiers, raw reports, logs or screenshots are stored here.

| Scenario | Observed result |
| --- | --- |
| Read-only preflight | Completed; installed application and both Freshworks services detected |
| Windows Backup capability check | Missing feature reported; candidate destination explicitly unverified |
| Simulated functional acceptance | Simulated upgrade accepted |
| Simulated functional rejection, rollback declined | Deployment not validated |
| Simulated rollback, recovery accepted | Rollback simulated and accepted |
| Simulated rollback, recovery rejected | Recovery not validated |
| Live Mode confirmation declined | Dry Run checkbox restored |
| UAC declined | Cancellation message shown; no live operation reported; checkbox restoration after dialog dismissal not captured |
| UAC accepted | Elevated GUI opened with explicit Live Mode warning |
| Dry Run re-enabled in elevated session | Simulation controls restored; administrator session retained as expected |

## Finding and correction

Re-enabling Dry Run left the earlier administrator/Live Mode status text visible. The local GUI change now sets a simulation status message when Dry Run is checked. This does not remove the process's administrator token or alter deployment authorization.

Manual confirmation of the corrected message in Windows Forms remains pending. Repeat only the affected transition: in an elevated GUI, enable Dry Run and confirm that the status describes simulation while the privilege indicator still describes the administrator session. Do not start a real upgrade for this check.

## Validation boundaries

Subsequent lab setup screenshots show a fresh OSR 2.5.0.0 installation with both Freshworks services running, the dedicated lab entry online, and a host-side baseline checkpoint. The same-version repair trial is recorded below; restoration tests remain pending. See [Same-Version Repair Lab](SAME_VERSION_REPAIR_LAB.md).

The initial GUI observations cover simulation branches, discovery presentation and elevation transitions. The lab trial adds limited real repair evidence; neither set of observations establishes complete application backup coverage, same-version restoration, cross-version upgrade or cross-version rollback. Smart Application Backup v0.5 remains planned, not implemented.

## Same-version repair trial - 2026-11-02

Scope: authorized Windows Server 2019 Hyper-V lab, installed OSR 2.5.0.0 and the original signed OSR 2.5.0.0 MSI. No orchestration workflow execution was requested or evidenced.

| Check | Evidence and result |
| --- | --- |
| Read-only plan after COM fix | Screenshot shows DRY_RUN, matching version/product identity, both services running, no backup or recovery claim |
| Capture | Runner report states INSTALLATION_TREE_VERIFIED; this records its before/after source and copied-file comparisons, not an independent rehash of the retained backup |
| MSI repair | Report exit code 0; MSI log states configuration completed successfully and reconfiguration status 0 |
| MSI execution | Log includes InstallValidate, InstallInitialize, InstallFiles and InstallFinalize; no Return value 3 marker was found |
| Service handling | Report has no error or restart error; subsequent guest query shows both Freshworks services Running |
| Tenant connectivity | Operator screenshot shows the dedicated lab entry ONLINE after repair |
| Restoration | Not performed; report retains RestorationValidated=false |
| Cross-version rollback | Not performed; report retains CrossVersionRollbackValidated=false |

Outcome: one observed successful same-version repair trial on a fresh lab installation. The presence of InstallFiles in the log does not establish that every payload file was replaced. Post-repair configuration equivalence, missing-file repair, injected-failure handling and actual restoration remain separate tests. Do not treat the baseline trial as approval for production upgrades.

## Integrated GUI/worker implementation

The subsequent integrated implementation is covered locally by Windows PowerShell 5.1 regressions with synthetic OSR discovery, service control, MSI results and human decisions. Real temporary file operations verify content/security restoration and rejection of altered backups. Unshown WinForms controls verify operation selection, default Dry Run, approval reset and elevation-state transfer. These tests execute no real OSR MSI or service changes. Subsequent live evidence is recorded below; follow [Integrated Lab Repair](INTEGRATED_LAB_REPAIR.md).

The operator subsequently confirmed the integrated GUI's read-only inspection and simulated acceptance/restoration branches through copied log text. The first integrated live trial reached backup and failed on a 261-character Ruby documentation destination under the longer ProgramData run root. The log reports service stop followed by service restart and PRE_DEPLOY_FAILED; no MSI operation was reached. A subsequent guest service query confirmed both Freshworks services Running.

The correction selects a shorter default lab run root and adds conservative path-budget checks during worker preflight, capture and restoration. Synthetic regressions verify rejection of a proposed 261-character file before destination creation, successful capture of the same source under a shorter root, and rejection before service/MSI calls in both worker modes. This is bounded path support, not a claim of arbitrary long-path compatibility.

## Integrated live acceptance trial - 2026-11-02

Evidence: copied main-worker activity log and guest/tenant screenshots. The corrected worker preflight passed with a longest proposed destination path of 245 characters. During the subsequent GUI-initiated live run, the log records service stop, completed application file capture including the two expected configuration files, verified saved MSI, same-version repair, and service restart. A separate guest query shows both Freshworks services Running; the dedicated lab entry is shown ONLINE. The operator answered YES to the local acceptance question, and the worker recorded completion after operator validation.

Outcome: one successful observed integrated backup/repair/acceptance path for OSR 2.5.0.0 in the dedicated lab. The retained JSON report and backup payload were not independently inspected for this trial; exact configuration equivalence is an operator attestation rather than an independently recorded hash comparison. Actual integrated file restoration, failure-injection recovery, crash-resumable recovery and cross-version operations remain unqualified. No production workflow execution is established by this evidence.

## Integrated same-version file-restoration trial - 2026-11-02

Evidence: copied main-worker activity log, recovery-prompt screenshots and a separate guest service query. A second GUI-initiated run completed backup and same-version repair. The operator deliberately rejected acceptance to exercise the recovery branch, then explicitly approved restoration. This rejection was a test decision, not evidence of a spontaneous MSI or service failure.

The worker reached the recovery-acceptance prompt stating that file hashes and permissions matched the captured baseline. The operator answered YES, and the final activity entry records restoration completed and operator-validated. The subsequent service query shows both Freshworks services Running. No independent post-restoration tenant connectivity screenshot or retained JSON report was supplied for this trial.

Outcome: one observed successful same-version installation-file restoration through the main GUI and worker, after an operator-triggered rejection. The comparison result is reported by the worker; an independent rehash of the full restored tree was not performed outside it. No application files were deliberately damaged or removed by the operator, so missing-file recovery and recovery after real installation failure are not established. Registry/external-state restoration, credential recovery, crash-resumable recovery and cross-version rollback remain outside this qualification. No host checkpoint restore was invoked by the program.
