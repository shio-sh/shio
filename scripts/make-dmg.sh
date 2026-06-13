#!/bin/bash
# Build the styled Shio.dmg the landing page describes — a window with the Shio
# keycap and an Applications drop, on the assets/dmg.png background (660x400).
# The app inside is already Developer-ID-signed + notarized + stapled; the DMG
# itself is notarized + stapled by the release workflow (or run those after).
#
#   make-dmg.sh <path/to/Shio.app> <output.dmg>
#
# create-dmg (Homebrew): brew install create-dmg.
set -euo pipefail

APP="${1:?usage: make-dmg.sh <Shio.app> <out.dmg>}"
OUT="${2:?usage: make-dmg.sh <Shio.app> <out.dmg>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Stage just the app, so the DMG holds exactly Shio.app + the Applications link.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
APPNAME="$(basename "$APP")"

rm -f "$OUT"
create-dmg \
  --volname "Shio" \
  --background "$ROOT/assets/dmg.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 120 \
  --icon "$APPNAME" 165 185 \
  --app-drop-link 495 185 \
  --hdiutil-quiet \
  --no-internet-enable \
  "$OUT" \
  "$STAGE"

echo "make-dmg: built $OUT ($(du -h "$OUT" | awk '{print $1}'))"
