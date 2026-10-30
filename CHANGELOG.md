# Changelog

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
