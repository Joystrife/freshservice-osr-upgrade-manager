# Design and Operational Model

The GUI separates **technical verification** from **functional acceptance**. A running Windows service does not prove that application orchestrations work.

## Modules and states

- Preflight: identify installed MSI version, OSR service path, official installer metadata and integrity, services, and operator-approved backup/recovery prerequisites.
- Deployment: invoke the vendor MSI with logging and no automatic reboot; observe the process and record the exit code.
- Technical validation: confirm version and service state.
- Manual validation: ask administrator-configurable Yes/No functional questions after deployment.
- Rollback decision: a No answer offers execution of an independently approved recovery script; declining it leaves the upgrade **not validated**.
- Audit: save local logs and machine-readable results; these are not intended for public source control.

## Constraints

- First-time installation and moving the installation directory are **not implemented**.
- An MSI installation success does not necessarily establish application-level success.
- Version rollback is not implied by rerunning an older MSI.
- The public source must contain no environment-specific IP addresses, credentials, OU names or asset identifiers.

## Validation status

Static code review is not equivalent to a Windows acceptance test. Validate on an authorized non-production host before production use.
