# Changelog

## 0.5.0 - Compact Workspace and portable executable (2026-11-02)

- Replaced an empty-path binding error in Lab repair recovery discovery with guidance to select the Same-version MSI first. A recovery-only selection is not promoted to repair readiness; Dry Run remains available.
- Applied the compact Workspace UI with Diagnostic, Lab repair and Upgrade tabs, operation-specific fields, collapsible advanced inputs and a fixed mode/privilege header. Diagnostic is read-only and cannot start the live worker; operation changes restore Dry Run and clear approvals.
- Added a single-file x64 .NET Framework launcher embedding the existing V3 GUI and four runtime modules, with standard-user startup and default-on Dry Run preserved.
- Added SHA-256 payload verification, an exact extraction allowlist, protected per-launch application folders, reparse-point/path checks and downloaded-file blocking without machine policy changes.
- Added an offline build script and regression coverage for embedded source parity, permissions, damaged payloads and unsafe archives. Interactive VM/UAC qualification remains pending; the published V3 source tag is unchanged.

## 0.4.1-v3-preview - V3 Integrated Lab Repair (2026-11-02)

- Published an experimental source distribution with an English user guide, workflow illustration, known issues, release notes and MIT license.
- Recorded one accepted main-GUI same-version repair trial, one accepted same-version installation-file restoration trial, and equal-version Upgrade rejection in the dedicated lab. Cross-version operations remain unqualified.

- Added a short default lab recovery root and conservative Windows PowerShell 5.1 path-budget checks before service control. Overlong backup/restore paths fail closed without skipping files or changing Windows policy.

- Made the log area resize with the main window and input rows expand horizontally. Added selected/all log copying, a context menu and Ctrl+A/Ctrl+C without creating Dry Run log files.

- Added an explicit Lab Repair selection to the main GUI and main worker, with default-on Dry Run, guest-name binding, checkpoint attestation and separate lab approval wording.
- Added verified installation-tree capture and experimental same-version file restoration through the existing acceptance/rollback decision channel.
- Preserved the Upgrade version, package, maintenance and independently validated recovery gates; malformed approval values fail closed.
- Added Windows PowerShell 5.1 tests for actual WinForms controls, synthetic worker paths, file/permission restoration, altered backups and unsafe paths. Automated checks and bounded live lab observations are documented separately.
- Fixed null COM return values contaminating MSI metadata in Windows PowerShell 5.1; covered by a real COM regression using synthetic MSI metadata.

## 0.4.0 — Recovery Provider Manager foundation (experimental)

- Added a standalone read-only Windows Server Backup capability provider.
- Added the GUI **Check Windows backup** action and automatic diagnostics during Dry Run and Auto-find.
- Discovers Windows Server Backup command/feature, source volumes and unverified separate fixed-volume backup candidates.
- Validates destination syntax and prevents plan targets from matching Windows/OSR source volumes.
- Generates a non-executing Microsoft `wbadmin start backup` plan preview.
- Added Windows PowerShell 5.1 regression tests and GitHub Actions coverage.
- Repositioned the project as a lifecycle, backup-planning and recovery manager with recovery providers and an explicit roadmap.
- **No automated Windows Server Backup execution or WinRE restoration is implemented in this release.**

## 0.3.2 — Registry discovery and privilege indicator (experimental)

- Fixed **Auto-find** failing with `The property 'DisplayName' cannot be found` when unrelated Windows uninstall keys omit `DisplayName` under StrictMode.
- Optional OSR uninstall fields (InstallSource, InstallLocation and LocalPackage) are now read defensively.
- Added Windows PowerShell 5.1 regression tests for registry entries with missing fields and ambiguous duplicate OSR records.
- Added a visible **SESSION: STANDARD USER / SESSION: ADMINISTRATOR** privilege indicator to the GUI header.

## 0.3.1 — Automatic Administrator elevation (experimental)

- Dry Run remains available in a standard non-elevated Windows PowerShell session.
- Switching to Live Mode automatically requests elevation through Windows User Account Control (UAC).
- If UAC is approved, the GUI restarts with an elevated token and restores the selected installer paths, recovery directory, hashes, functional questions and approval checkboxes without writing an intermediate file.
- If UAC is denied or elevation fails, the non-elevated GUI remains in Dry Run and no live operation starts.
- A second Administrator check in the GUI and the worker blocks live execution if the token is not elevated.
- The application title identifies the elevated session with [Administrator].

## 0.3.0 — Automatic recovery discovery (experimental)

- Introduced an **Auto-find** button for matching previous OSR MSI packages.
- Added bounded local discovery through the registered install source, Downloads, selected new installer folder and previous application recovery points.
- Required exact MSI identity/version and a validated Freshworks signature or independently verified SHA-256 before accepting recovery media.
- Reported virtualization and Windows Server Backup availability as **read-only diagnostics**, not as a guaranteed recovery point.
- Kept the live upgrade blocked when recoverability and the version-specific recovery procedure are not established.
- Preserved the default-on in-memory Dry Run and both Freshworks service controls.

## 0.2.0 — Dry Run

- Added default-on in-memory simulation including rollback decisions.

## 0.1.0 — Initial development preview

- Created the Windows Forms GUI, PowerShell worker and a basic integrated application recovery engine.

### Release validation correction

- Restore parent NTFS permissions before descendant permissions.
- Compare complete security descriptors while normalizing only the Windows-managed DACL auto-inherited bookkeeping flag; owner, group, ACEs and inheritance protection remain verified.
- Add synthetic regression cases for the CI-observed descriptor difference and security changes that must be rejected.
