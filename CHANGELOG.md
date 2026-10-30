# Changelog

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
