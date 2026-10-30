# Running Freshservice OSR Upgrade Manager (v0.3.0)

## Default: Dry Run (safe exploration)

1. On Windows, open Windows PowerShell 5.1 with STA support.
2. Run `powershell.exe -NoProfile -STA -File ".\src\Freshservice_OSR_Upgrade_GUI.ps1"`.
3. **DRY RUN** is checked by default. Select **Start dry run** to simulate service stops, backup, install, validation and recovery without changing the server. Simulated logs stay in memory.
4. Select **Read-only preflight** or **Auto-find** to inspect the installed OSR, both Freshworks services and locally discoverable original MSI packages.

## Preparing a real in-place upgrade

1. Download the new official `FO-OSR.msi` from Freshservice.
2. Select it with **Browse**. Leave the recovery MSI field empty; the live worker will search a bounded set of local directories for the original installer corresponding to the installed version.
3. If automatic discovery cannot find a complete trusted package, use the recovery MSI Browse field to choose an independently authenticated original installer. The Windows Installer cache is not accepted as a complete recovery source.
4. Confirm the detected existing installation directory. The recovery storage path must be outside it.
5. Independently validate the procedure for the specific pair of OSR versions and obtain maintenance authorization.
6. Disable Dry Run deliberately, run preflight and confirm the required approvals before starting the real upgrade.
7. The worker stops **Orchestration Server - WinRM_SSH** and **Orchestration Server**, creates an application-file backup, performs the MSI upgrade, restarts the two services and prompts for Freshservice functional tests. The native Windows WinRM service is never stopped.

## Recovery

The application contains a version-specific MSI recovery sequence. This is **not** equivalent to full Windows or virtual-machine restoration, and requires an independently validated downgrade procedure. It blocks live upgrades when no original verified recovery MSI or validated recovery path is available.

The GUI can inspect virtualization information and the presence of Windows Server Backup tooling, but **cannot create or apply full-machine snapshots** in this release. See [Recovery Providers](RECOVERY_PROVIDERS.md).

**Status:** Development preview. Neither the graphical Windows runtime nor production recovery has been independently tested by this project.
