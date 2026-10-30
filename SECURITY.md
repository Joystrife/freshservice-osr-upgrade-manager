# Security and operational safety

## Supported mode

This is an **experimental preview** and must not be represented as an endorsed recovery product or a validated one-click disaster-recovery solution.

## Operating principles

- Dry Run is on by default. It must not execute Windows service, MSI, filesystem backup or restore modifications.
- Live deployment requires deliberate mode change, Windows UAC elevation and explicit operator approvals.
- An available tool (`wbadmin.exe`, VSS or a hypervisor) does **not** mean an operable, recoverable point has been created.
- Never automatically stop the native Windows `WinRM` service. The managed Freshworks service is `Orchestration Server - WinRM_SSH`.
- Do not store MSI installers, backups, sensitive settings, passwords, recovery scripts, logs or server identifiers in the public repository.
- Recovery data can contain secrets; use restrictive ACLs, organizational retention policies and independently protected backup targets.

## Reporting security issues

Open a private GitHub security advisory when available. Do not paste confidential server details or credentials into public issues.

## Project governance

The repository is publicly visible, but no project-wide redistribution license has yet been selected. Verify your rights to publish and modify any code derived from employer-owned assets.
