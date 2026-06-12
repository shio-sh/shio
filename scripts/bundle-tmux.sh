#!/bin/bash
# Relocate the local tmux into the Mac app bundle so Shio works out of the box
# on Macs that never installed it. The user's own tmux ALWAYS wins (the session
# bootstrap appends this dir to the END of PATH); the bundled one is purely the
# fallback, so we never mix our client with their running server.
#
# Produces ShioMac/Resources/tmux/{bin/tmux, lib/*.dylib} with install names
# rewritten to @executable_path and everything ad-hoc signed (install_name_tool
# invalidates signatures; unsigned arm64 binaries won't exec).
#
# Gitignored output — run this after a fresh clone (like refresh-ghostty.sh).
# NOTE: copies the host's binary, so the result matches this Mac's arch
# (arm64). A universal build is a distribution-batch task.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="$(command -v tmux || true)"
if [ -z "$SRC" ]; then
  echo "bundle-tmux: no tmux on this machine (brew install tmux) — skipping." >&2
  exit 0
fi
SRC="$(readlink -f "$SRC")"

DEST="ShioMac/Resources/tmux"
rm -rf "$DEST"
mkdir -p "$DEST/bin" "$DEST/lib"
cp "$SRC" "$DEST/bin/tmux"
chmod u+w "$DEST/bin/tmux"

# Rewrite every non-system dylib reference to @executable_path/../lib, copying
# the dylibs in and processing THEIR deps too (queue until fixpoint).
is_local_dep() { case "$1" in /opt/homebrew/*|/usr/local/*) return 0 ;; *) return 1 ;; esac; }

queue=("$DEST/bin/tmux")
while [ ${#queue[@]} -gt 0 ]; do
  file="${queue[0]}"; queue=("${queue[@]:1}")
  while read -r dep; do
    is_local_dep "$dep" || continue
    name="$(basename "$dep")"
    if [ ! -f "$DEST/lib/$name" ]; then
      cp "$(readlink -f "$dep")" "$DEST/lib/$name"
      chmod u+w "$DEST/lib/$name"
      install_name_tool -id "@executable_path/../lib/$name" "$DEST/lib/$name" 2>/dev/null
      queue+=("$DEST/lib/$name")
    fi
    install_name_tool -change "$dep" "@executable_path/../lib/$name" "$file" 2>/dev/null
  done < <(otool -L "$file" | tail -n +2 | awk '{print $1}')
done

for f in "$DEST/lib/"*.dylib "$DEST/bin/tmux"; do
  codesign -f -s - "$f" >/dev/null 2>&1
done

# Prove the relocated binary actually runs without homebrew.
VERSION="$("$DEST/bin/tmux" -V)"
echo "bundle-tmux: bundled $VERSION → $DEST ($(du -sh "$DEST" | awk '{print $1}'))"
