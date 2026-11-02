# V3 - Integrated Lab Repair

Tag: `v0.4.1-v3-preview`  
Date: 2026-11-02  
Status: experimental prerelease  
License: MIT

V3 publishes the generic source and documentation for the integrated lab workflow tested during development. V3 is the name of this distribution; it does not complete the planned v0.5 Smart Application Backup milestone.

## Download and start

- `OSR-Upgrade-Manager-V3-source.zip`: complete source, launcher, guide, tests and license.
- `SHA256SUMS.txt`: SHA-256 of that release ZIP. The ZIP also contains `PACKAGE-FILES.sha256` for individual source files.

Extract the full ZIP and double-click `Start-Manager.cmd`. Windows PowerShell 5.1 is required; Dry Run is checked at startup. Read the [User Guide](USER_GUIDE.md) before selecting Live Mode. There is no EXE asset yet, and no Freshworks MSI or runtime backup is included.

## Changes

- Main GUI operation selection for Upgrade and explicit same-version Lab Repair using the same worker and decision channel.
- File capture/verification, operator acceptance and experimental same-version file/security restoration after rejection.
- Guest binding, separate lab approval/checkpoint attestation and preserved Upgrade recovery/version gates.
- Short default lab run root and conservative path-budget checks before service changes.
- Resizable journal, clipboard actions and Ctrl+A/Ctrl+C; Dry Run logs remain in memory.
- Correct Windows PowerShell 5.1 MSI COM output handling.
- Seven regression suites, a user guide, workflow illustration, known issues and MIT license.

## Recorded qualification

In one dedicated Windows Server 2019 Hyper-V lab with the original signed OSR 2.5 MSI, the main GUI/worker completed a repair accepted by the operator and a separate operator-approved installation-file restoration. Service queries showed both Freshworks services Running. Equal-version Upgrade was correctly rejected. Read-only, simulation and elevation scenarios were also observed.

The full backup payload was not independently rehashed outside the worker. No production workflow execution was required. A deliberate No answer exercised file restoration after a completed repair; it does not establish recovery from a genuine failed upgrade. See [Test Evidence](MANUAL_TEST_RESULTS.md).

## Limits

Cross-version upgrades/downgrades, complete application recovery, registry/external-state restoration, credentials, crash-resumable recovery and full-machine recovery are not qualified. Windows Server Backup remains read-only discovery/planning. The release ZIP is unsigned; a checksum is an integrity aid, not a code-signing identity. See [Known Issues](KNOWN_ISSUES.md).

Executable packaging will be evaluated separately against the same source and safety behavior, then offered as a clearly identified additional distribution option after acceptance tests.
