# Getting Started

For version 0.5.0, start with the illustrated [User Guide](USER_GUIDE.md), [Known Issues](KNOWN_ISSUES.md) and [Release Notes](RELEASE_0_5.md). Double-click the portable EXE, or extract the complete source ZIP and run `Start-Manager.cmd`. See [Portable Executable](PORTABLE_EXECUTABLE.md) for Windows policy behavior and extraction details.

## Requirements

- Windows with interactive Windows PowerShell 5.1 and Windows Forms support.
- For source startup, the complete `src/` directory, including all `.psm1` modules and the worker script. The portable EXE embeds these runtime files.
- Administrator approval for Live Mode. Dry Run and backup capability assessment are read-only.

## Launch

From the repository root:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy RemoteSigned -File ".\src\Freshservice_OSR_Upgrade_GUI.ps1"
```

## Dry Run (recommended first)

1. Leave the **DRY RUN** box checked (default).
2. Start on Diagnostic for read-only inspection. Select Lab repair or Upgrade to show MSI fields and the simulation action.
3. Select **Read-only preflight** or **Start dry run**.
4. Review the in-memory activity log and experiment with functional test responses.
5. No services are stopped, no MSI is launched, and no recovery files are created.

## Check Windows backup — v0.4.0

1. Select **Check Windows backup**.
2. Read the status of the Windows Server Backup command and Windows feature.
3. Review the Windows and OSR source volumes and any candidate separate fixed volumes.
4. Note that candidate disks are **NOT VERIFIED** backup destinations and that the check does not run `wbadmin`.
5. The result does not authorize a live upgrade or establish a complete system rollback.

The same capability assessment is logged automatically during **Auto-find** and the Dry Run read-only inspection.

## Auto-find

The **Auto-find** action reads OSR MSI registration and searches a bounded set of installer locations for a complete original MSI matching the installed version. If none is discovered, that does not mean the OSR version is missing; it means no eligible old installer was found in the inspected locations.

## Live mode and UAC

Uncheck DRY RUN and confirm. If the current Windows session is not elevated, the application triggers an ordinary Windows User Account Control prompt. If elevation succeeds, the GUI reopens with its non-secret form settings. If elevation is declined, the original GUI stays in Dry Run.

The Upgrade workflow requires verified original recovery media and an independently tested version-specific restoration procedure. The separate Lab Repair workflow requires an exact same-version/product MSI, named Hyper-V guest, explicit lab approval and baseline checkpoint attestation; it does not qualify cross-version recovery. Windows Server Backup detection cannot bypass either workflow's checks.

**Do not use the experimental Live Mode in production until the relevant Freshworks version upgrade and recovery paths have been tested.**

## More information

- [Technical Design](DESIGN.md)
- [Recovery Architecture](RECOVERY_ARCHITECTURE.md)
- [Roadmap](../ROADMAP.md)
