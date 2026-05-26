#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# shio — macOS setup
# Source: https://github.com/shio-sh/shio/blob/main/scripts/mac-setup.sh
# Run:    curl -fsSL https://shio.sh/setup | bash
# Review: curl -fsSLo shio-setup.sh https://shio.sh/setup && less shio-setup.sh
#
# Prepares this Mac to accept SSH connections from Shio on your iPhone.
# Open source, no telemetry, every destructive step asks for confirmation.
# Touches only: Homebrew-managed paths, ~/.ssh/, and System Settings (which
# it opens for you — it cannot toggle Remote Login programmatically).
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── styling ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

heading() { printf "\n${BOLD}%s${NC}\n" "$1"; }
info()    { printf "  %s\n" "$1"; }
dim()     { printf "  ${DIM}%s${NC}\n" "$1"; }
ok()      { printf "  ${GREEN}✓${NC}  %s\n" "$1"; }
warn()    { printf "  ${YELLOW}!${NC}  %s\n" "$1"; }
err()     { printf "  ${RED}✗${NC}  %s\n" "$1"; }

confirm() {
    local prompt="${1:-Continue?}"
    printf "  ${prompt} [y/N] "
    read -r answer </dev/tty
    [[ "${answer:-}" =~ ^[Yy]$ ]]
}

# ── preamble ─────────────────────────────────────────────────────────────────
printf "\n  ${BOLD}shio${NC} setup\n"
dim "https://shio.sh"
dim "Open source. No telemetry. Reads ~/.ssh/, writes only with your consent."

heading "What this script will do"
info "1. Verify Homebrew (install only if missing, via brew.sh's own installer)"
info "2. Install tmux so Shio can persist sessions across reconnects"
info "3. Open System Settings → Sharing — you'll toggle Remote Login yourself"
info "4. (Optional) Paste a public key into ~/.ssh/authorized_keys"
info "5. Check whether Tailscale is installed"
echo
dim "What it will NOT do: collect data, write outside ~/.ssh, run anything as root"
dim "that doesn't need it, change firewall settings, or modify your shell config."

echo
confirm "Continue?" || { err "Cancelled."; exit 0; }

# ── 1. Homebrew ──────────────────────────────────────────────────────────────
heading "1. Homebrew"
if command -v brew >/dev/null 2>&1; then
    ok "Already installed at $(command -v brew)"
else
    warn "Not installed"
    info "Shio uses Homebrew to install tmux. The next command runs Homebrew's"
    info "official installer (from brew.sh), unchanged."
    confirm "Install Homebrew now?" || { err "Cancelled."; exit 0; }
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Apple Silicon: brew goes in /opt/homebrew which isn't on PATH by default.
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

# ── 2. tmux ──────────────────────────────────────────────────────────────────
heading "2. tmux"
if command -v tmux >/dev/null 2>&1; then
    ok "Already installed: $(tmux -V)"
else
    info "Installing tmux..."
    brew install tmux
    ok "Installed: $(tmux -V)"
fi

# ── 3. Remote Login ──────────────────────────────────────────────────────────
heading "3. Remote Login"
# `sudo systemsetup -getremotelogin` now requires Full Disk Access on
# modern macOS, so don't even try — just ask the user to check the UI.
info "Shio needs Remote Login enabled. macOS doesn't let any app toggle it"
info "programmatically — you'll do it yourself in System Settings."
echo
info "Opening System Settings → General → Sharing..."
open "x-apple.systempreferences:com.apple.preferences.sharing" 2>/dev/null \
    || open "x-apple.systempreferences:com.apple.preference.sharing" 2>/dev/null \
    || warn "Couldn't open System Settings automatically. Open it manually."
echo
info "Find ${BOLD}Remote Login${NC} in the list and turn it on. Under"
info "\"Allow access for\", make sure your user account is included."
echo
printf "  Press Enter when done... "
read -r _ </dev/tty
ok "Marked Remote Login as enabled (you confirmed)"

# ── 4. Public key (optional) ─────────────────────────────────────────────────
heading "4. Public key"
SSH_DIR="${HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

if [[ -n "${SHIO_PUBLIC_KEY:-}" ]]; then
    # Sanity-check the format. Should start with ssh-ed25519 (or similar).
    if [[ ! "$SHIO_PUBLIC_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256)\  ]]; then
        err "SHIO_PUBLIC_KEY doesn't look like a valid public key. Skipping."
    else
        info "Installing public key into $AUTH_KEYS"
        confirm "Append this key?" || { warn "Skipped."; goto_tailscale=1; }
        if [[ "${goto_tailscale:-0}" != "1" ]]; then
            mkdir -p "$SSH_DIR"
            chmod 700 "$SSH_DIR"
            touch "$AUTH_KEYS"
            chmod 600 "$AUTH_KEYS"
            if grep -qF "$SHIO_PUBLIC_KEY" "$AUTH_KEYS" 2>/dev/null; then
                ok "Already installed (key already present in authorized_keys)"
            else
                # Always write to a tmp file and move — atomic and safe.
                tmpfile="$(mktemp "${SSH_DIR}/.authorized_keys.shio.XXXXXX")"
                cat "$AUTH_KEYS" > "$tmpfile" 2>/dev/null || true
                echo "$SHIO_PUBLIC_KEY" >> "$tmpfile"
                mv "$tmpfile" "$AUTH_KEYS"
                chmod 600 "$AUTH_KEYS"
                ok "Installed"
            fi
        fi
    fi
else
    info "No SHIO_PUBLIC_KEY environment variable set."
    info "If you'd like to install your iPhone's public key now:"
    echo
    info "  1. In Shio on your iPhone: Settings → SSH Key → Copy public key."
    info "  2. Then run, on this Mac:"
    echo
    dim "       SHIO_PUBLIC_KEY='ssh-ed25519 AAAA... shio@iphone' \\"
    dim "         bash <(curl -fsSL https://shio.sh/setup)"
    echo
    info "Or just paste it manually into $AUTH_KEYS later — Shio's"
    info "PublicKeyView shows you the exact one-liner for that too."
fi

# ── 5. Tailscale ─────────────────────────────────────────────────────────────
heading "5. Tailscale"
if [[ -d "/Applications/Tailscale.app" ]] || command -v tailscale >/dev/null 2>&1; then
    ok "Installed"
    info "Make sure Tailscale is signed in and the menu bar shows your Mac"
    info "as connected before trying to connect from Shio."
else
    warn "Not installed"
    info "Shio uses Tailscale to reach your Mac securely from your iPhone."
    info "Install it from: https://tailscale.com/download"
fi

# ── done ────────────────────────────────────────────────────────────────────
echo
heading "All set"
info "Open Shio on your iPhone. Add this Mac and tap to connect."
dim "Your username for the Add screen is: $(whoami)"
echo
