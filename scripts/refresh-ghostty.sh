#!/usr/bin/env bash
#
# refresh-ghostty.sh — rebuild Shio's vendored GhosttyKit.xcframework from the
# Ghostty fork at ~/ghostty, keeping us on latest Ghostty with our patches.
#
# Shio's libghostty is a REBASABLE PATCH SERIES on top of upstream Ghostty
# `main` (remote `origin` = ghostty-org/ghostty; `shio` = shio-sh/ghostty).
# Today: one patch — "shio: add External IO backend + C ABI for embedder-driven
# terminals" — plus whatever we add next (e.g. search/⌘F lives natively in
# Ghostty already, driven via binding_action, so it needs no patch).
#
# The build MUST run inside Ghostty's Nix dev shell: it provides the exact Zig
# (0.15.2) + a self-contained Apple toolchain that links without the system
# Xcode SDK. A raw zig + the macOS 26.x SDK fails to link (.tbd too new).
#
# GOTCHA: nix/devShell.nix deliberately prepends /opt/homebrew/bin to PATH, so a
# bare `zig` inside the dev shell resolves to Homebrew's zig (0.16, which
# Ghostty REJECTS). We must invoke the flake's nix-store zig 0.15.2 — found by
# scanning PATH for the 0.15.2 binary — explicitly.
#
# Usage:
#   scripts/refresh-ghostty.sh            # build from the fork's CURRENT state + vendor
#   scripts/refresh-ghostty.sh --update   # fetch upstream + rebase our patches onto latest main, then build + vendor
#
# After it finishes: cd ~/Shio && xcodegen && build BOTH schemes (ShioMac +
# Shio iOS) and re-verify — this binary ships on iOS too.

set -euo pipefail

GHOSTTY="${GHOSTTY_DIR:-$HOME/ghostty}"
SHIO="${SHIO_DIR:-$HOME/Shio}"
DEST="$SHIO/Frameworks/GhosttyKit.xcframework"
SRC="$GHOSTTY/macos/GhosttyKit.xcframework"

cd "$GHOSTTY"

if [[ "${1:-}" == "--update" ]]; then
  echo "==> Fetching upstream (origin = ghostty-org/ghostty)…"
  git fetch origin
  echo "==> Rebasing Shio patch series onto origin/main…"
  echo "    (If this stops with conflicts: resolve, 'git rebase --continue', then re-run without --update.)"
  git rebase origin/main
fi

echo "==> Fork state:"
git --no-pager log --oneline -3

echo "==> Building xcframework in the Nix dev shell (Zig 0.15.2; ~10–30 min first run)…"
nix develop --accept-flake-config -c bash -c '
  set -e
  ZIG=""
  for d in $(echo "$PATH" | tr ":" "\n"); do
    if [ -x "$d/zig" ] && [ "$("$d/zig" version 2>/dev/null)" = "0.15.2" ]; then ZIG="$d/zig"; break; fi
  done
  if [ -z "$ZIG" ]; then echo "!! could not find zig 0.15.2 on the dev-shell PATH" >&2; exit 1; fi
  echo "    using zig: $ZIG"
  exec "$ZIG" build -Demit-macos-app=false
'

if [[ ! -d "$SRC" ]]; then
  echo "!! Build did not produce $SRC" >&2
  exit 1
fi

echo "==> Vendoring into Shio (backing up the old one)…"
if [[ -d "$DEST" ]]; then
  mv "$DEST" "$DEST.bak-$(date +%Y%m%d-%H%M%S)"
fi
cp -R "$SRC" "$DEST"

echo "==> Done. New framework at $DEST"
echo "    Next: cd \"$SHIO\" && xcodegen && build ShioMac + Shio (iOS) and re-verify."
echo "    Check include/ghostty.h drift vs the Swift bridge if anything fails to compile."
