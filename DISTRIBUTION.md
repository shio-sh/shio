# Shipping Shio

Two channels, because a terminal doesn't fit the Mac App Store:

| App | Channel | Why |
|---|---|---|
| **iPhone / iPad** | **TestFlight → App Store** | SSH-only; sandbox-clean. |
| **Mac** | **Notarized Developer ID** (direct DMG off shio.sh) | A real terminal runs arbitrary shells + reads your files — the **App Sandbox** (mandatory for the Mac App Store) forbids that. iTerm, Ghostty, and Warp all ship direct for the same reason. |

Automated with **fastlane** (`fastlane/Fastfile`).

## One-time setup
1. **App Store Connect API key:** ASC → Users and Access → Integrations → App Store Connect API → generate (App Manager). Download the `.p8`.
2. `cp fastlane/.env.example fastlane/.env` and fill in `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`.
3. **Create the iOS app record — once, in the ASC web UI.** App Store Connect → Apps → ＋ → New App → iOS, name "Shio", bundle id `sh.shio.app`, SKU `shio-ios-001`. (This is the *only* manual step: Apple's API can't create app records, so `produce`/the API key can't do it — but everything after, build + upload, runs off the API key non-interactively.)

## iPhone / iPad → TestFlight
```
fastlane ios beta
```
Builds Release, signs with **Apple Distribution**, uploads. Then in ASC → TestFlight: add yourself as an internal tester (no beta review needed for internal).

**App Review notes (pre-written, for when you go public):**
- *App Transport Security:* `NSAllowsArbitraryLoads` is set **only** so QR pairing can POST this device's public key over plain HTTP to the user's **own** machine — including a Tailscale `100.64/10` address, which ATS's local-networking exception doesn't cover. No arbitrary web content is loaded; SSH is raw sockets and CloudKit uses its own secure transport.
- *Encryption:* `ITSAppUsesNonExemptEncryption = false` (only standard TLS/SSH). No extra export docs needed.

## Mac → notarized direct download
```
fastlane mac release
```
Builds Release with **Hardened Runtime**, signs **Developer ID**, notarizes, staples. Output in `build/mac/Shio.app`. ✅ **Verified 2026-06-09: the notarized + hardened build runs the local terminal** (real shell, no fork-safety abort) — the warning below is satisfied, kept for the record.

> ⚠️ **Re-verify the terminal whenever the libghostty spawn path changes.** Re-zip *after* stapling for distribution: `ditto -c -k --sequesterRsrc --keepParent build/mac/Shio.app Shio-1.0.zip` (gym's own zip is made before the staple).

## Mac → GitHub CI release (`.github/workflows/release-mac.yml`)

The same `fastlane mac release` recipe, run on a `macos-15` runner, publishing the notarized `.zip` as a **GitHub Release** (manual trigger: Actions → *Release Mac* → Run). shio.sh links the latest asset.

**One-time: five repo secrets** (Settings → Secrets and variables → Actions). Three are already set from `fastlane/.env` (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`). The remaining two are your signing cert — export it (Touch ID prompt), then set both:
```sh
PW="$(openssl rand -base64 24)"
security export -k ~/Library/Keychains/login.keychain-db -t identities \
  -f pkcs12 -P "$PW" -o /tmp/devid.p12          # approve the keychain prompt
base64 -i /tmp/devid.p12 | gh secret set DEVID_CERT_P12_BASE64 --repo shio-sh/shio
printf '%s' "$PW" | gh secret set DEVID_CERT_PASSWORD --repo shio-sh/shio
rm -f /tmp/devid.p12                            # never commit / never print the .p12
```
(Or export just the *Developer ID Application* identity + its key via Keychain Access → Export → `.p12`.)

(Sparkle for in-app auto-update is a later add — it points at a GitHub-Releases appcast, which is exactly what this workflow produces. See the landing/messaging work.)

> ⚠️ **TEST FIRST — hardened-runtime + the local terminal.** Notarization requires Hardened Runtime, and the ObjC runtime ignores `OBJC_DISABLE_INITIALIZE_FORK_SAFETY` for hardened processes — the very opt-out the local terminal used to dodge the fork-safety abort when ghostty forks a shell. **Before distributing, open the notarized `build/mac/Shio.app`, start a local terminal tab, and confirm you get a working shell** (not a blank cursor). Ghostty.app ships notarized + hardened with a working terminal using the same libghostty, so it's very likely fine — but it MUST be verified on a hardened build, since our Debug builds are unhardened. If the shell doesn't spawn, the fix is in the libghostty spawn path (posix_spawn vs fork), not the env var.

## Versions
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` live in `project.yml`. Fastlane stamps each upload with a UTC-timestamp build number, so you only bump `MARKETING_VERSION` for user-facing version changes.
