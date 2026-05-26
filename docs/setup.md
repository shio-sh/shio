# Setting up your Mac for Shio

Shio is the iPhone app. Your Mac doesn't need Shio installed — it just needs to be reachable on Tailscale and willing to accept SSH connections from your iPhone. Four short steps. Total time: a minute or two.

Every step uses an existing trusted tool — Tailscale's signed installer, Apple's System Settings, your Mac's Terminal, and (optionally) Homebrew. **Shio asks you to install nothing of our own on your Mac.**

---

## 1. Install Tailscale on your Mac

Open [tailscale.com/download](https://tailscale.com/download) on your Mac. Run the installer. Sign in with Google, Apple, Microsoft, or GitHub.

Use **the same account** you'll use on your iPhone. That's how Tailscale knows the two devices belong to the same private network.

Once installed, you'll see a small Tailscale icon in your menu bar showing **Connected**.

## 2. Enable Remote Login

Open **System Settings** on your Mac. Navigate to **General → Sharing**. Turn **Remote Login** on.

Under "Allow access for", make sure your user account is included (or "All users").

Remote Login is what starts the SSH server on your Mac. Without it, your Mac refuses connection requests on port 22 — even with the right key, even with Tailscale humming along perfectly. macOS doesn't ship with this on by default, and only you can turn it on (no app can do it for you, and rightly so).

## 3. Install Shio's public key

Each Shio install generates its own SSH keypair stored on your iPhone. To let it sign into a Mac, that Mac needs to know the public half.

On your iPhone:
1. Open Shio
2. Go to **Settings → SSH Key**
3. Tap **Copy install command**

On your Mac, open Terminal and paste. Hit enter. The line appends Shio's public key to `~/.ssh/authorized_keys` safely, creating `~/.ssh` if it doesn't exist and setting `chmod 600` on the file.

That's all. No restart, no service to reload.

## 4. (Optional) Install tmux

This step is optional. Shio works without it; sessions just don't persist between reconnects when tmux isn't present.

With tmux installed, when you close Shio and come back, you land in the exact same shell state — same working directory, same running command, same scrollback. Without it, each reconnect starts a fresh shell.

If you already use [Homebrew](https://brew.sh), it's one line:

```sh
brew install tmux
```

If you don't have Homebrew, you don't need it just for this — Shio's perfectly happy with plain SSH. Install Homebrew + tmux later if you decide you want session persistence.

A nice quirk: you can install tmux *from inside Shio's first SSH session*. Connect, run `brew install tmux` at the prompt, disconnect, reconnect — your next session will auto-resume.

---

## That's it

Back on your iPhone, in Shio:
- Add your Mac (Shio knows it via Tailscale's MagicDNS name)
- Tap to connect

If anything doesn't work, Shio's built-in **Diagnose connection** (Settings → Diagnose, or the Diagnose button on a disconnect overlay) will tell you exactly which step is incomplete and what to do.

---

## A one-command install someday

We're working toward shipping `shio` as a CLI helper in [Homebrew's official formulas](https://formulae.brew.sh) so the steps above collapse into:

```sh
brew install shio
```

That requires earning Homebrew's notability threshold first, which we'll work toward once Shio is shipping with real users. Until then, the guide above is the path — and honestly, it's not bad.

---

## Reporting issues

For security-relevant issues, see [SECURITY.md](../SECURITY.md). For everything else, GitHub issues are welcome.
