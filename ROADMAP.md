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

## v0.4.1-v3-preview — V3 Integrated Lab Repair

- [x] Main-GUI operation selection, lab binding and separate approval wording.
- [x] Same-version repair and experimental file/permission restoration through the main worker.
- [x] Short lab recovery root and path-budget checks before service changes.
- [x] Resizable, copyable in-memory journal.
- [x] Seven Windows PowerShell 5.1 regression suites.
- [x] Recorded bounded live repair/restoration and Upgrade rejection evidence.
- [x] User guide, known issues, source release packaging and MIT license.
- [ ] Executable package, with separate packaging/elevation acceptance checks.
- [ ] Broader failure-injection, reboot and crash-recovery qualification.

V3 names this distribution of the v0.4.1 preview. It does not rename or complete the v0.5 feature milestone below.

## v0.5 — Smart Application Backup (planned)

The next milestone is a targeted OSR application backup, independent of full Windows Server Backup. The implementation plan and acceptance criteria are in [Smart Application Backup](docs/SMART_APPLICATION_BACKUP.md). No v0.5 runtime functionality is implemented yet.

- [ ] Bounded, read-only discovery of OSR files, configuration, related registry keys, service definitions and required permissions.
- [ ] In-memory backup plan with explicit source coverage, unresolved dependencies and operator-selected destination; no writes in Dry Run.
- [ ] Protected application backup after explicit Live Mode authorization, with an offline consistency policy for the two Freshworks services.
- [ ] Versioned manifest with per-file SHA-256, file counts, metadata and completeness checks; incomplete backups must fail closed.
- [ ] Separate backup integrity, same-version restoration, cross-version rollback and production authorization states.
- [ ] Windows PowerShell 5.1 regression tests using synthetic data and mocked system operations.
- [ ] Explicitly authorized same-version restoration trials in an isolated Windows Server lab.

An application backup does not replace a full-system recovery point or establish that a downgrade is supported. Preserve the verified original previous-version MSI and independently validated version-pair recovery gates. Cross-version rollback remains unverified.

## Future milestone — Windows Server Backup creation

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
- [x] MIT license selected by the project owner for this source distribution.
