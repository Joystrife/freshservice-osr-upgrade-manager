# 0.5.1 Release 3 — controlled replacement and application recovery

This publication is promoted from prerelease after the dedicated Windows Server 2019 VM trials. The existing tag `v0.5.1-preview.3`, executable, source archive and SHA-256 manifest are preserved exactly; the application's title still says Preview 3. This is a publication-status change, not a rebuilt binary or version 5.1.3.

## Validated scope

- Controlled replacement of the inspected, signed OSR 2.4.0.0 -> 2.5.0.0 MSI pair, with verified backup and identity-only `osr.conf` migration.
- Integrated rollback: removal of the recognized target, reinstallation of the original 2.4 MSI, restoration and comparison of the original 11,859-entry file/permission inventory, and operator acceptance.
- The operator subsequently confirmed OSR 2.4 after recovery and a successful GET Web Request through the dedicated lab orchestrator: HTTP 200 with the expected JSON response.
- A further integrated replacement installed OSR 2.5; the dedicated lab entry appeared ONLINE and the same Web Request returned HTTP 200 with the expected JSON response. A subsequent equal-version preflight correctly refused another 2.5 -> 2.5 upgrade. The operator reported this test successful; the final accepted-run report was not supplied for independent inspection.
- All nine Windows PowerShell 5.1 regression suites passed locally and on GitHub Actions before the original publication.

These observations qualify this Web Request scenario in this dedicated lab. Active Directory actions are provided by the separate Microsoft Active Directory - Orch application; the Web Request trial validates the exercised OSR-mediated scenario, not every action of that application. No AD failure was observed or diagnosed by these tests. Complete business workflows, full-system recovery, broader version pairs and migration of proxy/custom settings are outside this validation scope. No customer data, credentials or original screenshots are included in this documentation.

## Downloads and operation

The portable executable, readable source ZIP and `SHA256SUMS.txt` remain the same tested publication assets. Verify checksums and follow normal organizational application policy. The unsigned launcher requires x64 Windows, Windows PowerShell 5.1 and .NET Framework 4.7.2 or later. Freshworks MSIs are not bundled.

The application starts in Diagnostic with Dry Run enabled. For the inspected 2.4 -> 2.5 pair, use **Controlled replacement**, not in-place MSI upgrade. Confirm the maintenance authorization, independently tested recovery path and identity-only migration scope. Keep recovery files and perform the required functional test before operator acceptance.

[Detailed implementation and historical trials](https://github.com/Joystrife/freshservice-osr-upgrade-manager/blob/main/docs/RELEASE_0_5_1.md)
