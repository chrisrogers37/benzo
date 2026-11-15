# Security policy

## Scope

Reports are welcome about:

- the Benzo macOS menubar app, in the current source and in published releases;
- the account-bound `BenzoCommand` grant, digest-pinned rule at `/private/etc/sudoers.d/benzo-command`, and root-owned authority and execution records;
- the legacy permission rule at `/etc/sudoers.d/benzo`, including how the app observes it;
- the recovery boundary, meaning saved original `pmset` values, Restore/Off, quit, and removal behavior;
- the benzo.work website.

The v0.4.0 account-free design grants finite commands to the local setup account,
bound by UID and GeneratedUID; it is not an app-exclusive privilege. Other programs
in that account can invoke those commands. Setup, repair and removal are explicit
administrator-approved actions. Ordinary apply and restore use the retained grant.
See the [README](README.md) for recovery behavior and the
[native acceptance record](docs/account-free-acceptance.md) for observed and untested
cases. Reports are welcome in every area, including these boundaries.

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
