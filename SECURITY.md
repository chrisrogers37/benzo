# Security policy

## Scope

Reports are welcome about:

- the Benzo macOS menubar app, in the current source and in published releases;
- the legacy permission rule at `/etc/sudoers.d/benzo`, including how the app observes or relies on it;
- the recovery boundary, meaning saved original `pmset` values, Restore/Off, quit, and removal behavior;
- the benzo.work website.

The current source is an unreleased intermediate revision with known recovery limits, documented in the [README](README.md) and the [remediation plan](documentation/planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md). Report new issues even when they relate to those areas.

## How to report

Send private reports to [contact@benzo.work](mailto:contact@benzo.work). Do not open a public GitHub issue for a suspected vulnerability.

Handling is best effort. This project does not promise a response time, fix date, backport, or supported release line.

Please include, where you can:

- the Benzo version or commit SHA, and whether you used a release download or a source build;
- your macOS version and Mac hardware (Intel or Apple Silicon);
- the impact you observed and the component affected;
- minimal reproduction steps, with any evidence redacted.

Do not send passwords, tokens, private keys, full system logs, or unredacted backup files. Describe the observed `pmset` state rather than assuming a repair has occurred.

Privacy details are in [PRIVACY.md](PRIVACY.md).
