# 0.5.0 - Compact Workspace and portable executable

Tag: `v0.5.0`  
Date: 2026-11-02  
License: MIT  
Status: experimental prerelease

## Downloads

- `OSR-Upgrade-Manager-0.5.0-portable.exe`: single-file x64 launcher with the GUI and required modules embedded. Double-click to start on Diagnostic with Dry Run enabled. No installation or startup elevation is requested.
- `OSR-Upgrade-Manager-0.5.0-source.zip`: complete readable source, launcher code, build scripts, documentation and tests. Extract the complete ZIP and run `Start-Manager.cmd`.
- `SHA256SUMS.txt`: SHA-256 checksums for both downloads. The EXE is unsigned; the hash is not a publisher signature.

Freshworks installers, credentials, operational logs, backup payloads and machine-specific settings are not included.

## Changes

- Compact Workspace with Diagnostic, Lab repair and Upgrade tabs, operation-specific inputs and collapsible advanced options.
- A fixed Dry Run/Live banner, a separate Windows privilege indicator, resizable logs and selected/all log copying.
- Read-only Diagnostic cannot start a live worker. Operation changes restore Dry Run and clear live approvals. Existing UAC, MSI identity/version, checkpoint-attestation and recovery procedure gates remain in place.
- Portable extraction verifies the embedded ZIP hash and exact file allowlist, creates a unique protected per-user application folder and rejects unsafe paths/reparse points. Windows policy is not persistently changed.
- Missing same-version MSI input now produces actionable guidance instead of a parameter-binding error.
- Eight Windows PowerShell 5.1 regression suites, including actual WinForms controls, integrated worker behavior and compiled portable payload checks.

## Observed lab scope

The operator supplied logs for the portable Workspace GUI's read-only diagnostic, both operation simulations and a real same-version OSR 2.5.0.0 repair followed by deliberate rejection and approved installation-file restoration in a dedicated Windows Server 2019 Hyper-V guest. The worker reported matching file hashes/permissions and final operator acceptance. A separate guest query showed both Freshworks services running. This is bounded scenario evidence; no independent full-tree rehash or retained integrated JSON report was inspected.

Cross-version upgrades/downgrades, real MSI-failure recovery, registry/external-state recovery, crash-resumable recovery and full Windows recovery remain unqualified. The latest portable build's standard-user/UAC cancellation and representative download-policy behavior have not all been independently observed. Do not infer general production readiness from these trials.

## Roadmap clarification

0.5.0 names the completed Workspace and portable distribution work. The complete Smart Application Backup provider formerly assigned to the 0.5 milestone is still planned; it is not declared implemented by this version number. Existing lab file capture/restoration has a narrower scope.

Start with the [User Guide](USER_GUIDE.md), [Portable Executable](PORTABLE_EXECUTABLE.md), [Known Issues](KNOWN_ISSUES.md) and [Manual Test Results](MANUAL_TEST_RESULTS.md).
