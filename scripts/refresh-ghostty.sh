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
#   scripts/refresh-ghostty.sh --fetch    # download prebuilt libs from the GitHub Release (fresh clone / CI; NO build, NO Nix)
#
# The GhosttyKit .a static libs (~800 MB) are build artifacts, NOT in git. A
# fresh clone runs `--fetch` once to pull them from the pinned Release before
# the first Xcode build. `--update` rebuilds them; after that, publish a new
# Release (see the reminder it prints) and bump GHOSTTYKIT_TAG below.
#
# After a build: cd ~/Shio && xcodegen && build BOTH schemes (ShioMac +
# Shio iOS) and re-verify — this binary ships on iOS too.

set -euo pipefail

GHOSTTY="${GHOSTTY_DIR:-$HOME/ghostty}"
SHIO="${SHIO_DIR:-$HOME/Shio}"
DEST="$SHIO/Frameworks/GhosttyKit.xcframework"
SRC="$GHOSTTY/macos/GhosttyKit.xcframework"

# Pinned Release holding the prebuilt libs (bump after each --update rebuild).
GHOSTTYKIT_TAG="ghosttykit-332da19d2"
GHOSTTYKIT_URL="https://github.com/shio-sh/shio/releases/download/${GHOSTTYKIT_TAG}/ghosttykit-libs.tar.gz"

# --fetch: pull the prebuilt libs into the (git-tracked, .a-less) xcframework.
# Public repo → anonymous curl, so this works on a fresh clone / CI with no gh
# auth and no Ghostty checkout. Run this once before the first build.
if [[ "${1:-}" == "--fetch" ]]; then
  echo "==> Fetching prebuilt GhosttyKit libs ($GHOSTTYKIT_TAG)…"
  mkdir -p "$DEST"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fL --progress-bar "$GHOSTTYKIT_URL" -o "$tmp/libs.tar.gz"
  tar -xzf "$tmp/libs.tar.gz" -C "$DEST"
  echo "==> Done. Libs extracted into $DEST"
  echo "    Verify:"; find "$DEST" -name '*.a' -exec ls -lh {} \; | awk '{print "      "$5, $NF}'
  echo "    Next: cd \"$SHIO\" && xcodegen && build."
  exit 0
fi

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
echo
echo "==> Publish the new binary so fresh clones / CI get it (the .a aren't in git):"
NEWREV="$(git -C "$GHOSTTY" rev-parse --short HEAD)"
echo "    tar -czf /tmp/ghosttykit-libs.tar.gz -C \"$DEST\" \\"
echo "        macos-arm64_x86_64/ghostty-internal.a ios-arm64/libghostty-internal-fat.a ios-arm64-simulator/libghostty-internal-fat.a"
echo "    gh release create ghosttykit-$NEWREV /tmp/ghosttykit-libs.tar.gz --repo shio-sh/shio --title \"GhosttyKit @ $NEWREV\""
echo "    then set GHOSTTYKIT_TAG=\"ghosttykit-$NEWREV\" in this script and commit."
