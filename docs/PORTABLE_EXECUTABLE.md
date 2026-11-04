# 0.5.1-preview.3 Portable executable (experimental)

This experimental prerelease adds controlled 2.4 -> 2.5 replacement and encrypted path preferences. One integrated replacement/recovery trial completed in the dedicated VM; AD workflows remain untested. Read `docs/RELEASE_0_5_1.md` in the source distribution before live use. Replacement migrates only `osr.conf`; proxy/custom settings and external dependencies are excluded. Normal startup always uses Diagnostic and Dry Run. The default recovery root is `%SystemDrive%\OSR\Runs`.

Version 0.5.1-preview.3 packages the Workspace GUI and its five runtime modules inside one Windows executable. It is a launcher, not an OSR installer. It does not include Freshworks MSI packages, credentials, backups or run reports. Readable source is available alongside the EXE. The historical V3 source release remains available separately.

## Start the application

1. Use 64-bit Windows with Windows PowerShell 5.1, .NET Framework 4.7.2 or later, and an interactive Windows desktop. Windows Server 2019 Desktop Experience is the initial lab target.
2. Verify the executable's SHA-256 against the accompanying `SHA256SUMS.txt` from a trusted source. The executable is not Authenticode signed.
3. If Windows marks the downloaded file as blocked, review its origin and checksum, then use **Properties > Unblock** only if organizational policy permits. The launcher never removes this marker or changes machine execution policy. SmartScreen, AppLocker, WDAC or PowerShell policy may still block execution; use your normal application approval process.
4. Double-click `OSR-Upgrade-Manager-0.5.1-preview.3-portable.exe`. Administrator privileges are not requested at startup. Dry Run remains checked by default.
5. Start with **Read-only preflight** and **Start dry run**. Use **Copy all logs** to share diagnostic text after checking it for sensitive data.

## Compact workspace

This release uses the compact Workspace layout. It starts on **Diagnostic**, which keeps Dry Run enabled and cannot launch a live worker. **Read-only preflight** inspects the existing installation; **Check Windows backup** remains an inspection only.

Select **Lab repair** or **Upgrade** to reveal the required MSI and recovery storage inputs. Lab repair also shows the exact guest computer name. Switching operations re-enables Dry Run and clears live approvals. **Advanced options** reveals recovery media discovery, unsigned-package SHA-256 approval and acceptance checks. Expanding this section preserves entered values; smaller windows scroll the workspace while the mode banner remains visible. The activity log grows with the window and retains selected/all copying.

For Lab repair, select the package in **Same-version MSI**, even if **Recovery MSI** already contains a path from the diagnostic. These fields have different roles. With no repair target selected, the simulation can continue but does not establish readiness for a real repair.

Unchecking Dry Run on Lab repair or Upgrade still uses the existing GUI's explicit confirmation/UAC flow and worker approval/recovery checks. Live approvals are then displayed directly above the action buttons, outside the collapsed advanced section. Running as administrator does not itself disable Dry Run. The executable adds no automatic installation, service control, repair, upgrade or rollback.

See the [user guide](https://github.com/Joystrife/freshservice-osr-upgrade-manager/blob/main/docs/USER_GUIDE.md) and [known issues](https://github.com/Joystrife/freshservice-osr-upgrade-manager/blob/main/docs/KNOWN_ISSUES.md). Same-version lab repair/file restoration is experimental; cross-version upgrades and recovery remain unqualified.

## Local files and integrity

The launcher checks the embedded ZIP's SHA-256 and exact nine-file allowlist before extraction. It writes a fresh application folder below `%LOCALAPPDATA%\FreshworksOSRUpgradeManager\Portable\<random-id>`, with permissions restricted to the current account, SYSTEM and Administrators. It refuses reparse-point ancestors, duplicate/unexpected ZIP entries and overlong extraction paths. It starts the Windows-provided PowerShell executable with `-NoProfile -STA` without overriding the effective host execution policy; enforced organizational policies retain precedence.

Extracted application folders remain after closing. This is intentional: a GUI relaunched through UAC may outlive its original process and still need the modules. These folders contain application code and this document, not backup payloads. After closing **all** GUI and worker processes, you may manually delete obsolete folders inside that exact Portable directory. Do not delete it during a live operation. User-selected OSR recovery storage is separate and is never cleaned by the launcher.

The embedded hash detects corruption; it is not a publisher signature and cannot authenticate a malicious replacement executable. Windows policy and endpoint protection remain in effect.

## Build and verify from source

In Windows PowerShell 5.1, from the repository root:

```powershell
.\scripts\Test-Release.ps1
.\scripts\Build-PortableExecutable.ps1 -OutputDirectory .\dist\portable-trial
Get-FileHash .\dist\portable-trial\OSR-Upgrade-Manager-0.5.1-preview.3-portable.exe -Algorithm SHA256
```

The builder uses the existing Windows .NET Framework C# compiler, with no downloaded dependencies. Outputs must not already exist. `--verify-package` verifies/extracts the embedded application and exits without starting PowerShell or inspecting OSR; it still writes an application extraction folder.

## Remaining manual qualification

- Start the EXE as a standard user in the lab; confirm default Dry Run, responsive layout and log copying.
- Confirm Diagnostic starts selected and its Dry Run checkbox cannot be unchecked. Select Lab repair and Upgrade; confirm operation-specific fields, short lab recovery storage, collapsed advanced options and approval resets.
- Complete a read-only preflight and a Dry Run with the same lab inputs used for the source GUI.
- Cancel the live-mode confirmation, then reject UAC; confirm Dry Run is restored and no live worker starts.
- Accept UAC for the dedicated lab GUI only; confirm inputs survive, the extracted modules remain available, and re-enabling Dry Run keeps simulation active. An administrator token is expected to remain elevated.
- Verify downloaded-file handling and startup errors under representative Windows policies.
- Perform an explicitly authorized lab repair/restoration only when the existing host checkpoint and lab approvals are satisfied.

Automated payload tests do not qualify a real upgrade, a cross-version rollback, publisher trust, antivirus reputation or the interactive UAC boundary. This executable is distributed as an experimental prerelease with these qualification limits recorded.
