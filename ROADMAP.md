# Product Roadmap

The roadmap is intentionally staged. **A finished GUI or a successful syntax test does not establish that an upgrade or recovery procedure is safe in production.**

## v0.4.0 — Recovery-provider foundation (implemented)

- [x] Separate Windows Server Backup provider module.
- [x] Read-only backup feature/command detection.
- [x] Source volume identification and candidate backup destination discovery.
- [x] Validation of backup target syntax and exclusion of protected source volumes.
- [x] Backup command preview; no execution.
- [x] GUI **Check Windows backup** control and Dry Run diagnostics.
- [x] Windows PowerShell 5.1 syntax and regression checks.
- [x] Rewrite product positioning and recovery documentation.

## v0.5 — Windows Server Backup creation

- [ ] Operator-selectable approved local/UNC backup destination.
- [ ] Readiness checks: permissions, sufficient disk capacity, volume inclusion, VSS health and concurrent backup jobs.
- [ ] Background `wbadmin start backup` worker with real progress and cancellation policy.
- [ ] Backup catalog verification (`wbadmin get versions`) and creation of a protected recovery manifest.
- [ ] Validate operation in representative Windows Server lab environments.

## v0.6 — Restore orchestration

- [ ] Restore-capability checks independent of backup creation.
- [ ] External recovery controller design for WinRE and remote operations.
- [ ] Explicit authorization and end-to-end restore simulations.
- [ ] Support version-specific OSR app restoration without assuming MSI downgrade support.
- [ ] Fail closed whenever restoration is not executable.

## Future provider plugins

- [ ] AWS snapshot / AMI provider using approved external control-plane credentials and access.
- [ ] Hyper-V host-side checkpoint / restore provider.
- [ ] VMware vSphere snapshot / restore provider.
- [ ] Policy-based automatic provider selection from **validated** capabilities, not server manufacturer alone.

## Product quality

- [ ] End-to-end Windows Server backup/upgrade/recovery acceptance testing.
- [ ] Signed releases and release checksums.
- [ ] Interface redesign to separate installer, recovery, validation and audit panels.
- [ ] Localization framework, with English maintained as the default.
- [ ] License selection once contributor and organizational rights are confirmed.
