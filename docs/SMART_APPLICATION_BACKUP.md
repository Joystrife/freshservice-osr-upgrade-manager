# Smart Application Backup - Future Development Plan

Status: design and development preparation only. Version 0.5.0 was assigned to Workspace and portable packaging; the full provider scope described here remains a future milestone. The v0.4.1 V3 preview adds experimental lab installation-file capture/restoration to the v0.4 foundation; the complete Smart Application Backup provider below is not implemented. Names and contracts below are proposed, not exported commands.

## Objective and boundaries

Discover, plan, capture and verify the application data needed to recover a Freshworks Orchestration Server installation without requiring a full Windows Server backup. Keep the design generic and independent of any organization, host, drive letter or infrastructure vendor.

This backup cannot claim full-machine recovery, recover service account passwords, or establish MSI downgrade support. Full Windows Server Backup creation and an external recovery controller are separate milestones. Do not install software, Windows features or dependencies automatically.

The original OSR 2.4.0.0 installer is not currently available for the intended version-pair validation. OSR 2.5.0.0 to 2.4.0.0 rollback remains **not verified**. Same-version restoration evidence must never be presented as cross-version rollback evidence.

## Existing implementation and gaps

`OSR.Upgrade.Core.psm1` already discovers the registered product and both Freshworks services, validates MSI metadata/authenticity, and provides service and file-copy operations. `OSR.Upgrade.Worker.ps1` stops the Freshworks services, copies the installation tree and verified original previous MSI, and records basic product/service metadata.

The existing Upgrade recovery point checks the saved MSI hash and the presence of an `osr` directory. V3's separate Lab Repair branch adds installation-tree hashes and security metadata, but does not capture registry or external dependencies or provide complete application recovery evidence. Directory creation and a successful copy must not be treated as verification of restrictive destination permissions. These gaps remain requirements for the complete provider, not claims of existing capability.

Do not replace the existing worker recovery point until the new provider's failure handling, coverage and compatibility have been tested. Discovery and planning can be integrated first without changing deployment authorization.

## Required invariants

- Keep Windows PowerShell 5.1 and .NET Framework compatibility; avoid PowerShell 7-only syntax, APIs and modules.
- Keep Dry Run checked at startup, with simulation state and logs in memory only. Do not create directories, probe destination writability, export registry data, control services, launch MSI or initiate backup jobs during discovery or Dry Run.
- Keep Live Mode elevation, explicit maintenance approval, verified original previous-version media, and independently validated version-specific recovery procedures as distinct gates.
- Recheck authorization in any future capture worker, including direct invocation. Missing, malformed or unrecognized authorization must fail closed.
- Only manage the two Freshworks services: `Orchestration Server` and `Orchestration Server - WinRM_SSH`. Never manage the native Windows `WinRM` service.
- Keep the Windows Server Backup diagnostic read-only. Do not execute `wbadmin` backup or restore commands as part of this work.
- Treat configurations, registry exports, manifests and account metadata as sensitive. Never log configuration contents, credentials or private key material; never commit actual inventories or backups.
- Capture success, integrity verification and tested restorability are separate outcomes. No new backup status alone may authorize a live upgrade.

## Proposed module boundary

Add `src/OSR.Recovery.ApplicationBackup.psm1` incrementally. Reuse core discovery through a narrow adapter; do not duplicate MSI trust decisions or embed service-control commands in planning functions.

| Proposed operation | Responsibility | Allowed effects |
| --- | --- | --- |
| `Get-OsrApplicationBackupInventory` | Query registered product, service definitions and bounded application locations; report missing or ambiguous evidence | Read-only queries |
| `Get-OsrApplicationBackupPlan` | Convert inventory and selected destination into coverage, prerequisites, warnings and blocking reasons | Pure transformation; in-memory result |
| `New-OsrApplicationBackup` | Capture a protected, consistent recovery point after explicit authorization | Future approved backup writes and Freshworks service control only |
| `Test-OsrApplicationBackup` | Independently verify manifest schema, coverage, paths, file set and hashes | Read-only verification; result in memory |

Discovery must return structured errors for no installation, ambiguous products, inaccessible paths or missing service evidence. The GUI may still simulate such an environment, but the plan must remain incomplete and ineligible for live capture.

## Discovery and coverage

1. Resolve the installed product through the existing uninstall discovery adapter. Capture version, product identity and registry view; do not query `Win32_Product` or scan the whole disk.
2. Resolve executable paths for both Freshworks services, preserving quoted path handling. Compare them with the installation root and registration. A second service outside the primary root must become an explicit dependency or blocker, never silently disappear from the plan.
3. Enumerate only approved installation roots. Track configuration, binaries, hidden files, required directories and exclusions. Do not follow junctions or symbolic links; report reparse points and block completeness when a required target is unresolved.
4. Identify application-owned registry keys in both registry views through a reviewed allowlist. Define the allowlist from isolated lab evidence before implementing export; do not export entire registry hives or unrelated products.
5. Record service name, display name, executable command line, start mode, account identity, dependencies, recovery settings and security descriptor where readable. Account identity is metadata, not a recoverable password. Required unavailable credentials or machine-bound encryption keys must block restoration readiness.
6. Record file/directory security descriptors needed for restoration. Report access errors and unknown coverage explicitly. Do not assume `/COPYALL` alone establishes complete recoverability.
7. Report certificates, shared paths or external state as unresolved dependencies unless an explicit supported capture/restore procedure exists. Do not recursively collect unrelated shared directories or automatically export private keys.

## Destination and consistency policy

The first capture increment should support an explicitly selected local directory. Network destinations and alternate providers can follow separate validation work. Discovery may describe destination prerequisites, but actual write probes belong only to authorized capture.

Reject relative paths, volume roots, overlapping source/destination trees in either direction, and unresolved aliases or reparse points that could bypass containment. Validate containment using normalized paths with directory boundaries and case-insensitive comparison. A different folder on the same disk is not independent full-system recovery.

Before sensitive writes, verify destination identity, available space, required privileges and a restrictive access policy for the approved administrator/service principals. Verify the effective access policy rather than trusting inherited permissions. Keep partial and completed runs separate; never overwrite a completed recovery point.

Use offline application capture for the first supported consistency policy. After authorization, record the original service states, stop only the two Freshworks services, wait for confirmed stops, then inventory and copy the consistent source. Detect source changes during capture and fail incomplete rather than silently accepting a moving source.

On failure before deployment, restore the original Freshworks service states where possible and report any failed restart as requiring operator action. Never hide service recovery failure behind a successful file copy. Cancellation must leave an incomplete recovery point and restore service state; it must not start a deployment or delete evidence automatically.

## Proposed manifest and verification

Use a versioned manifest stored with the protected recovery point. Proposed fields:

| Field group | Required evidence |
| --- | --- |
| Identity | Schema version, unique backup ID, provider version, UTC capture time, application version and product identity |
| Coverage | Approved source roots, required components, explicit exclusions and unresolved dependencies |
| Files | Relative path, component ID, length, SHA-256, timestamp and captured security metadata; required empty directories tracked separately |
| Registry and services | Registry view/key coverage, protected artifact hashes, service definitions and credential availability prerequisites |
| Recovery media | Original MSI identity, version, SHA-256 and authenticity evidence; missing media explicitly recorded |
| Completion | Capture state and verification results, with errors and incomplete components |
| Readiness | Independent integrity, same-version restoration, cross-version rollback and production authorization states |

Reject unsupported schemas, rooted or traversing relative paths, duplicate case-insensitive entries and reparse points. Independently enumerate captured files and compare exact file sets, sizes and hashes against the expected inventory; reject missing, extra, changed or unreadable data. Do not trust only the manifest's own success flag or a copy exit code. Verify that the source inventory was stable during capture.

Store manifest completion atomically only after all required captures and checks succeed. SHA-256 detects changed payloads relative to trusted metadata; it does not authenticate a manifest that an attacker can also replace. Protect the manifest and payload with the destination access policy, and do not describe hashes as cryptographic proof of trusted origin.

## Recovery readiness

| Dimension | Initial state | Evidence needed to advance |
| --- | --- | --- |
| Application backup integrity | `NOT_TESTED` | Complete capture plus independent coverage and integrity checks |
| Same-version restoration | `NOT_TESTED` | Authorized isolated restoration with required original media, permissions, configuration and functional checks |
| Cross-version rollback | `NOT_VERIFIED` | Required original version media plus independently validated procedure for the exact installed/target version pair |
| Production upgrade authorization | `BLOCKED` | Existing maintenance, package and recovery gates plus approved operational policy |

A missing original MSI need not prevent read-only planning or an explicitly authorized data capture, but it must remain visible and cannot be bypassed as a deployment or restoration prerequisite. Verification of a file set does not unlock production upgrades. Test evidence must identify the version pair and coverage rather than relying on a generic success checkbox.

## Implementation sequence

1. Add inventory and planning functions with synthetic fixtures and injected/mock discovery adapters. Keep the GUI and worker authorization logic unchanged. All results remain in memory.
2. Add the manifest contract and independent read-only verification against synthetic fixture trees. Specify schema rejection and containment behavior before implementing capture.
3. Add protected capture behind explicit authorization. Test permission failures, service-stop failures, copy failures, cancellation, concurrent operations and restart failures through mocks before lab execution.
4. Add read-only GUI inventory/plan presentation. Keep real backup creation separate from simulation and show the four readiness dimensions without promoting any status automatically.
5. Validate same-version capture and restoration in an isolated Windows Server lab after explicit authorization. Record sensitive evidence outside the repository. Preserve the cross-version restriction until the required original media and exact version-pair tests exist.

## Regression and acceptance matrix

| Scenario | Expected result |
| --- | --- |
| Missing optional registry properties or ambiguous OSR registration | Existing tests remain green; ambiguous coverage blocks the plan |
| Service path with spaces, quotes or a different installation drive | Correct bounded roots or an explicit unresolved-path blocker |
| Missing second service, access denied or required external state | Incomplete coverage; no readiness claim |
| Dry Run or discovery requested | No filesystem writes, registry export, service control, MSI, backup jobs or credential prompts |
| Default/direct capture without authorization | Rejected before the first write or service change |
| Nested/overlapping destination, traversal, duplicate path or reparse point | Rejected without following an unsafe path |
| Modified, missing, additional or unreadable backup file | Integrity check fails; restoration readiness stays unverified |
| Failure during copy, cancellation or service restart | Incomplete result; original service states restored where possible; unresolved failures visible |
| Complete copy or successful same-version lab restore | No automatic production authorization or cross-version validation |
| Windows PowerShell 5.1 execution | Source/tests parse and synthetic regression suites pass without third-party installations |

Extend the existing Windows PowerShell 5.1 GitHub Actions workflow when implementation tests are added. Mock all system-changing operations; capture/restore integration tests require a separately authorized disposable lab and must not run on the developer's workstation or a production server.

## Local development checks

Use Windows PowerShell 5.1 with `-NoProfile` for compatibility validation. Parse all `.ps1` and `.psm1` files in `src` and `tests`, then run `tests/Test-RegistryDiscovery.ps1` and `tests/Test-WindowsBackupProvider.ps1`. These existing regression suites use synthetic data and do not install OSR or manage services. Do not invoke `OSR.Upgrade.Worker.ps1` as a test runner: even its preflight mode writes run files.

If local policy requires it and organizational policy permits it, a `RemoteSigned` execution policy can be scoped to the validation process only. Do not change persistent user/machine policy or install test dependencies for this preparation.
