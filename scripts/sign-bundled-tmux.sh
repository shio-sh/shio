#!/bin/bash
# Re-sign the bundled tmux inside a BUILT Shio.app with the Developer ID
# identity, so it survives notarization + hardened runtime. bundle-tmux.sh
# ad-hoc-signs (fine for local dev, rejected by notarization); this overrides
# that with the real cert. Run AFTER build_mac_app, BEFORE notarize.
#
#   sign-bundled-tmux.sh <path/to/Shio.app> <signing-identity>
#
# <signing-identity> is a "Developer ID Application" name or its SHA-1 hash
# (whatever `codesign -s` accepts). No-op when no tmux is bundled.
set -euo pipefail

APP="${1:?usage: sign-bundled-tmux.sh <Shio.app> <identity>}"
IDENTITY="${2:?usage: sign-bundled-tmux.sh <Shio.app> <identity>}"
TMUX="$APP/Contents/Resources/tmux"
ENT="$(cd "$(dirname "$0")/.." && pwd)/ShioMac/tmux.entitlements"

if [ ! -d "$TMUX" ]; then
  echo "sign-bundled-tmux: no bundled tmux in $APP — nothing to sign." >&2
  exit 0
fi

# Deepest first: the dylibs (no entitlements — dylibs don't take them), then
# the tmux binary (hardened runtime + disable-library-validation so it can load
# its @executable_path dylibs), then re-seal the app so its signature covers
# the re-signed tmux (modifying nested code invalidates the outer seal).
find "$TMUX/lib" -name "*.dylib" -type f -print0 | while IFS= read -r -d '' dylib; do
  codesign --force --options runtime --timestamp -s "$IDENTITY" "$dylib"
done
codesign --force --options runtime --timestamp --entitlements "$ENT" -s "$IDENTITY" "$TMUX/bin/tmux"
codesign --force --timestamp \
  --preserve-metadata=entitlements,requirements,flags -s "$IDENTITY" "$APP"

# Fail loudly here rather than deep inside notarization.
codesign --verify --deep --strict --verbose=2 "$APP" >&2
echo "sign-bundled-tmux: tmux + dylibs Developer-ID-signed and app re-sealed." >&2
