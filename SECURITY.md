# Security

Shio 1.0 is out: the Mac app as a notarized direct download, iPhone and iPad in TestFlight.

If you find something that looks like a real vulnerability, such as credential leakage, an SSH protocol flaw, a sandbox escape, or a privacy regression, please don't open a public issue.

Email: **hi@amrith.co**

For everything else (bugs, UX feedback, suggestions), GitHub issues are fine.

## What Shio touches

Worth knowing when you're deciding where to look:

- **SSH keys.** On Mac, Shio reads your existing `~/.ssh` keys. On iPhone and iPad it generates its own device-bound Ed25519 key, held in the keychain, that you install on hosts yourself.
- **Host keys** are pinned on first connection and a changed key is refused rather than silently accepted.
- **Sync** goes through your own iCloud via CloudKit. There is no Shio server and no account with us.
- **Nothing is installed** on the machines you connect to. Shio is an SSH client and uses tmux if the host already has it.

## Secrets in this repository

This repository is built to contain **no secrets**: no API keys, no signing credentials, no personal identifiers, no real Tailscale hostnames. The Apple Developer Team ID lives only in a regenerated `Shio.xcodeproj`, which is gitignored.

If you spot a leaked secret or a personal identifier in a future commit, please flag it.
