# Shio — macOS setup

This page explains what Shio needs on your Mac, why, and the one-line script that handles it for you. The script is open source, runs only with your confirmation at each step, and touches a deliberately small set of files. **You should read it before you run it.** This page shows you how.

---

## What Shio needs on your Mac

To let your iPhone connect to your Mac through Shio, your Mac needs **four** things in place. None of them are Shio-specific — they're the same things any SSH-over-Tailscale setup needs.

1. **Homebrew** — macOS's package manager. Used to install tmux. If you already have Homebrew, the script skips this step.
2. **`tmux`** — used for session persistence. When you close Shio and come back, you land in the same shell state. macOS doesn't ship tmux since Catalina (2019), so it's a one-Homebrew-install away.
3. **Remote Login enabled** — under System Settings → General → Sharing. This is what starts the SSH server (`sshd`) on your Mac. The script can't toggle it for you — that's a macOS security boundary, and we think rightly so. The script opens the right Settings pane and waits.
4. **Tailscale** — installed and signed in on both your Mac and your iPhone, with the VPN active and "Use Tailscale DNS" turned on. The script checks whether Tailscale is installed and links you to the install page if not.

Optionally, the script can also paste Shio's public key into `~/.ssh/authorized_keys` for you — but only if you explicitly hand it the key via an environment variable.

---

## The one-liner

```sh
curl -fsSL https://shio.sh/setup | bash
```

That's it. The script asks for confirmation at each step. Total time on a fresh Mac: ~30 seconds.

If you'd prefer to install the public key in the same step, copy it from Shio first (Settings → SSH Key → Copy public key), then:

```sh
SHIO_PUBLIC_KEY='ssh-ed25519 AAAA... shio@iphone' \
  bash <(curl -fsSL https://shio.sh/setup)
```

---

## Read it first (recommended)

`curl | bash` is a known pattern that security folks rightly criticize, because you're trusting whoever serves that URL. Mitigation: read the script before you run it.

```sh
curl -fsSLo shio-setup.sh https://shio.sh/setup
less shio-setup.sh                              # read it
bash shio-setup.sh                              # run it
```

The script lives at [`scripts/mac-setup.sh`](../scripts/mac-setup.sh) in this repo. The `shio.sh/setup` URL serves the exact same file from a Cloudflare Pages deployment of this repository. The content of the URL and the content of the repo are pinned to the same commit.

---

## What the script will and won't do

### Will

- Install Homebrew (only if missing) by running [Homebrew's official installer](https://brew.sh) — same one you'd run yourself.
- Install `tmux` via Homebrew.
- Open System Settings → General → Sharing in the GUI so you can toggle Remote Login.
- (If you set `SHIO_PUBLIC_KEY`) Append a single line to `~/.ssh/authorized_keys`, ensuring `chmod 700 ~/.ssh` and `chmod 600 ~/.ssh/authorized_keys`. Uses an atomic temp-file write so the file is never half-corrupted.
- Check whether Tailscale is installed and tell you where to get it if not.

### Won't

- Run anything as `root` for things that don't require it. (Homebrew's installer and `brew install` need elevated permissions during install; nothing else does.)
- Modify any file outside `~/.ssh/` or Homebrew-managed paths.
- Toggle macOS settings programmatically.
- Change shell configuration (`.zshrc`, `.bash_profile`, etc.) — Homebrew's installer prints suggestions but doesn't apply them. The Shio script doesn't apply them either.
- Disable or weaken any security feature.
- Collect telemetry. Make network calls anywhere except `brew.sh`, `raw.githubusercontent.com/Homebrew/install/...`, Homebrew's package mirrors, and the URLs displayed during the run.
- Run silently. Every destructive step asks `y/N`.

---

## Why we chose this shape

A few options were considered and rejected:

- **A full macOS companion app** — too much install friction, doubles maintenance, can't actually toggle Remote Login anyway.
- **Auto-toggling Remote Login** — requires Full Disk Access entitlement on the user's Terminal. We refuse to ask for that.
- **Bundling tmux inside Shio** — pointless because tmux runs on the Mac, not the iPhone.
- **Custom Tailscale-replacement networking** — Tailscale is the trust anchor. We defer security-critical networking to people who specialize in it.

What we landed on: **one auditable script, served from one HTTPS URL, that does the minimum amount of preparation each user explicitly consents to.**

---

## Removing what the script installed

Everything the script installs is unprivileged Homebrew packages, plus optional lines in your `authorized_keys`. To undo:

```sh
brew uninstall tmux                       # if you don't want it
brew uninstall --force --zap homebrew/bundle    # if you don't want Homebrew at all
# Then remove the public key line from ~/.ssh/authorized_keys manually.
```

Remote Login you can toggle off in System Settings any time.

---

## Reporting issues

If you spot a security or privacy concern with the script, please don't open a public issue — see [SECURITY.md](../SECURITY.md). For everything else, GitHub issues are welcome.
