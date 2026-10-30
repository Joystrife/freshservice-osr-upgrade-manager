# Freshservice OSR Upgrade Manager

A generic **English-language Windows Forms / PowerShell 5.1** project for supervised in-place upgrades of the **Freshworks Freshservice Orchestration Server (OSR)**.

**Release: v0.3.2 (experimental).** The GUI is implemented, but live upgrades and recovery have **not** been tested on a Windows Server. This is not a Freshworks-supported universal downgrade tool. Do not deploy in production before validating the upgrade and recovery paths for the specific versions.

## Quick start

In an authorized Windows PowerShell 5.1 session:

```powershell
powershell.exe -NoProfile -STA -File ".\src\Freshservice_OSR_Upgrade_GUI.ps1"
```

The **DRY RUN** checkbox is **enabled by default**. Click **Start dry run** to simulate preflight, recovery planning, both Freshworks service stops, file backup, MSI installation, both service starts, interactive acceptance tests, and the rollback decision. The Dry Run performs no intended system modifications; logs remain in the GUI's memory. Read-only local MSI and environment queries may occur.

## Administrator elevation (v0.3.1)

The default **Dry Run** and read-only discovery operate without Administrator privileges. When **Dry Run** is unchecked, the GUI requests explicit confirmation and then triggers Windows User Account Control (UAC) via `Start-Process -Verb RunAs`. After successful elevation, the elevated GUI restores the file selections, paths, hashes and test questions, without creating an intermediate state file. Its window title displays **[Administrator]**.

If elevation is denied or unavailable, the program remains in **Dry Run**. The live GUI and deployment worker both independently reject any live execution without an elevated Administrator token.

## What is new in v0.3.2

- **Auto-find registry fix:** Windows uninstall entries without a `DisplayName` or other optional properties are skipped safely.
- **Visible token status:** the window header shows `SESSION: STANDARD USER` or `SESSION: ADMINISTRATOR`.
- **UAC behavior:** Dry Run never triggers UAC; the UAC prompt appears when switching to Live Mode from a standard session. If the process was already elevated, no second prompt is needed.
- **Regression test:** GitHub Actions runs a Windows PowerShell 5.1 registry detection test.

## What is new in v0.3.0

- **Auto-find** next to the recovery MSI field. It searches a bounded list of original installer locations, including the registered installation source, the selected upgrade MSI's directory, Downloads, and this application's previously created recovery points.
- The **previous installer is optional to select manually**: during live preflight, the worker also automatically searches for a verified package matching the currently installed OSR version.
- MSI identity and version must match; the package must have a valid Freshworks Authenticode signature **or** an independently supplied matching SHA-256. A package merely having the right filename is not trusted.
- The Windows Installer cache (`C:\Windows\Installer`) is **not** treated as an original, fully redistributable MSI.
- Read-only **recovery environment diagnostics** report virtualization information and whether Windows Backup tooling is present. These indicators do **not** constitute a usable VM checkpoint or a verified backup.
- If no verified automatic recovery mechanism exists, the **live upgrade is blocked** instead of pretending a local file backup can undo an MSI upgrade.

## Controlled upgrade workflow

1. Select the **new official `FO-OSR.msi`** with Browse.
2. Leave the recovery MSI blank and use **Auto-find**; select the earlier original MSI manually only when discovery fails.
3. Confirm the existing installation directory (detected from the Freshworks service) and the recovery storage location (outside the installation tree).
4. Run preflight. The system verifies elevation, vendor MSI identity, versions, package authenticity, the two OSR services and recovery package readiness.
5. After the operator has independently tested and authorized the exact downgrade/recovery procedure, disable Dry Run, confirm the live operation, and start the upgrade.
6. The worker stops **Orchestration Server - WinRM_SSH** and **Orchestration Server**, copies the OSR files with NTFS metadata and stores the verified previous MSI in protected recovery storage.
7. The worker launches the new `FO-OSR.msi`, monitors the exit code, restarts both Freshworks services and checks the installed version.
8. The operator performs functional Freshservice tests. If a test fails, the GUI asks whether to attempt the integrated application rollback. Declining the rollback results in **NOT VALIDATED**.
9. Reports and MSI logs are written locally for a **live operation** only.

The native **Windows WinRM** service is never stopped by the application.

## Recovery strategies: implemented vs future

| Capability | Status |
| --- | --- |
| Discover an original previous-version MSI automatically | **Implemented**; local, bounded, read-only search |
| Verify a previous-version MSI against version, vendor identity and signature/hash | **Implemented** |
| Protected OSR file snapshot plus verified previous installer | **Implemented**; Windows validation pending |
| Integrated application recovery using the previous MSI and backed-up files | **Implemented** but **requires an independently validated version-specific procedure** |
| Detect whether the machine looks virtual and Windows Backup tooling exists | **Read-only diagnostics only** |
| Create and revert a Hyper-V/VMware checkpoint from within the OSR VM | **Not implemented** |
| Automatically roll back the full Windows system without the original MSI | **Not implemented** |

A Hyper-V production checkpoint must be controlled from an authorized hypervisor management context. Restoring a VM may terminate the guest session and requires an independently running recovery controller. Windows Server Backup also has separate restore procedures. Neither merely having VSS available nor being on a virtual machine guarantees that an automatic full-system rollback is possible.

**Automatic discovery is not automatic historical download:** Freshworks' published setup instructions show how to obtain the current `FO-OSR.msi`, not a public archive of old versions.

## Project files

```text
src/
  Freshservice_OSR_Upgrade_GUI.ps1  # GUI, read-only discovery and in-memory Dry Run
  OSR.Upgrade.Worker.ps1            # External upgrade worker and acceptance decisions
  OSR.Upgrade.Core.psm1             # Version, MSI, service and recovery helper functions
docs/
  DESIGN.md
  INSTALLATION.md
  RECOVERY_PROVIDERS.md
.github/workflows/
  powershell-syntax.yml
CHANGELOG.md
```

## Privacy and operational safety

The source contains no customer-specific hosts, tenants, credentials, internal network names or identifiers. Never commit installer binaries, logs, configuration backups, secret keys, or recovery-point contents. Recovery data may contain Freshworks tokens or proxy credentials and must be secured by local ACLs and organizational retention rules.

## References

- [Freshworks – Setting up the Orchestration Server](https://support.freshservice.com/support/solutions/articles/50000003259-setting-up-the-orchestration-server)
- [Freshworks – Troubleshooting Guide for Orchestration Server Issues](https://support.freshservice.com/support/solutions/articles/50000003393-troubleshooting-guide-for-orchestration-server-issues)
- [Microsoft – Windows Installer Rollback Installation](https://learn.microsoft.com/en-us/windows/win32/msi/rollback-installation)
- [Microsoft – Hyper-V checkpoints](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/checkpoints)
- [Microsoft – Windows Server Backup (`wbadmin`)](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wbadmin)

## License

MIT — see `LICENSE`.