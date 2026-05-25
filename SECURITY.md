# Security

Shio is in active development and not yet released. If you find something that looks like a real vulnerability — credential leakage, an SSH protocol flaw, a sandbox escape, a privacy regression — please don't open a public issue.

Email: **hi@amrith.co**

For everything else (bugs, UX feedback, suggestions), GitHub issues are fine.

## Secrets in this repository

This repository is built to contain **no secrets**: no API keys, no signing credentials, no personal identifiers, no real Tailscale hostnames. The Apple Developer Team ID lives only in a regenerated `Shio.xcodeproj` (gitignored).

If you spot a leaked secret or a personal identifier in a future commit, please flag it.
