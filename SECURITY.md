# Security Policy

## Reporting Security Issues

Please do not open a public issue for a security-sensitive report.

Email the maintainer at `caipiz@gmail.com` with:

- A short summary of the issue.
- Reproduction steps or a proof of concept.
- Affected versions or commit SHAs, if known.
- Any relevant environment details.

## Scope

Security-sensitive areas include:

- Unexpected command injection through CLI arguments.
- Unsafe handling of local or remote paths.
- Cleanup behavior that could delete files outside the intended temporary paths.
- Accidental exposure of secrets, SSH options, or host-specific details.

This script does not accept or store passwords. Authentication is delegated to the system `ssh/scp` commands.

## Supported Versions

Before the first tagged release, security fixes target the `main` branch.
