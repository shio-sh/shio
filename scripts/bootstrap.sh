#!/usr/bin/env bash
# Bootstraps the Shio Xcode project from project.yml and fetches xterm.js assets.
# Run from anywhere; resolves paths relative to the repo root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

info()  { printf "${GREEN}→${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$*"; }
error() { printf "${RED}✗${NC} %s\n" "$*" >&2; exit 1; }

# 1. XcodeGen
if ! command -v xcodegen >/dev/null 2>&1; then
  warn "xcodegen not installed. Installing via Homebrew..."
  if ! command -v brew >/dev/null 2>&1; then
    error "Homebrew not installed. Install it from https://brew.sh and re-run."
  fi
  brew install xcodegen
fi

info "Generating Shio.xcodeproj from project.yml"
xcodegen generate --quiet

# 2. xterm.js assets
XTERM_DIR="$REPO_ROOT/Shio/Resources/terminal"
mkdir -p "$XTERM_DIR"

XTERM_VERSION="5.5.0"
ADDON_FIT_VERSION="0.10.0"
ADDON_WEB_LINKS_VERSION="0.11.0"

fetch_if_missing() {
  local url="$1"
  local dest="$2"
  if [[ ! -f "$dest" ]]; then
    info "Fetching $(basename "$dest")"
    curl -fsSL -o "$dest" "$url" || error "Failed to fetch $url"
  else
    info "$(basename "$dest") already present, skipping"
  fi
}

fetch_if_missing \
  "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/lib/xterm.js" \
  "$XTERM_DIR/xterm.js"
fetch_if_missing \
  "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/css/xterm.css" \
  "$XTERM_DIR/xterm.css"
fetch_if_missing \
  "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@${ADDON_FIT_VERSION}/lib/addon-fit.js" \
  "$XTERM_DIR/addon-fit.js"
fetch_if_missing \
  "https://cdn.jsdelivr.net/npm/@xterm/addon-web-links@${ADDON_WEB_LINKS_VERSION}/lib/addon-web-links.js" \
  "$XTERM_DIR/addon-web-links.js"

info "Done. Open Shio.xcodeproj in Xcode."
