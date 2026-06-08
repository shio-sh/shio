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
Builds Release with **Hardened Runtime**, signs **Developer ID**, notarizes. Output in `build/mac/`. Then DMG it (or zip) and host on shio.sh. (Sparkle for in-app auto-update is a later add — see the landing/messaging work.)

> ⚠️ **TEST FIRST — hardened-runtime + the local terminal.** Notarization requires Hardened Runtime, and the ObjC runtime ignores `OBJC_DISABLE_INITIALIZE_FORK_SAFETY` for hardened processes — the very opt-out the local terminal used to dodge the fork-safety abort when ghostty forks a shell. **Before distributing, open the notarized `build/mac/Shio.app`, start a local terminal tab, and confirm you get a working shell** (not a blank cursor). Ghostty.app ships notarized + hardened with a working terminal using the same libghostty, so it's very likely fine — but it MUST be verified on a hardened build, since our Debug builds are unhardened. If the shell doesn't spawn, the fix is in the libghostty spawn path (posix_spawn vs fork), not the env var.

## Versions
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` live in `project.yml`. Fastlane stamps each upload with a UTC-timestamp build number, so you only bump `MARKETING_VERSION` for user-facing version changes.
