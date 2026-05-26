<p align="center">
  <img src="assets/icon/shio-180.png" width="120" height="120" alt="shio icon">
</p>

<h1 align="center"><code>shio</code></h1>

<p align="center"><em>Your Mac, in your pocket.</em></p>

<p align="center">
  A clean, minimal SSH client for iPhone and iPad. Tailscale-native.
</p>

<p align="center">
  <code>塩</code>
</p>

<p align="center">
  <sub>In active development. Not yet on the App Store.</sub>
</p>

---

## What Shio is

Shio is a premium iOS and iPadOS SSH client built for developers who want their Mac in their pocket — and want it to feel native, calm, and uncompromisingly well-made.

It exists because every current option is one of:

- **Cluttered** — bloated feature soup, account walls, subscription pushes.
- **Expensive or pro-coded** — powerful but priced and positioned only for power users, with UX that's slowly fallen behind.
- **Suspicious or abandonware** — single-developer apps that look like 2014 and charge monthly for a `libssh2` wrapper.
- **The wrong tool** — local Linux emulators when what you actually want is your Mac, not a virtualized Linux.

Shio is the clean, opinionated, "just works" option in the middle of that. Tailscale-native by default. Full direct-SSH support gated behind a Pro Mode toggle.

## Principles

- **Guardrails by default, power on request.** Defaults are right for 95% of users. Anything dangerous is one toggle away in Settings.
- **The terminal is sacred.** Behavior, colors, copy/paste, scroll, selection — match macOS Terminal's "Basic" profile where it matters. SF Mono throughout the terminal.
- **The keyboard is the product.** Every chord that works in macOS Terminal works here — soft accessory row, hardware keyboard, modifier state machine.
- **Apple-platform-native.** Live Activities, Dynamic Island, widgets, App Intents, Handoff — woven in, not bolted on.
- **No account. No telemetry. No subscription.** One-time purchase or free. Profiles sync via iCloud Keychain.
- **Quiet by default.** No upsells, no badges, no banners. Shio opens to your terminal.

## Status

In development. Building in public, but no public marketing yet — the build sequence is roughly:

```
Brick  0  ✓  Brand & design system (icon, tokens, voice)
Brick  1  ✓  Foundation (Xcode project, design tokens, asset catalog)
Brick  2  ✓  Terminal rendering (xterm.js in WKWebView)
Brick  3  ✓  SSH core (SwiftNIO SSH)
Brick  4  ✓  Keyboard system (accessory row, hardware passthrough, ANSI)
Brick  5  ✓  Tmux auto-resume
Brick  6  ✓  Onboarding (adaptive Tailscale walkthrough)
Brick  7  ~  Host management (Direct SSH Pro Mode) — auth flow in progress
Brick  8  ✓  iPad bespoke layout
Brick  9  -  Live Activities + Dynamic Island
Brick 10  -  Widgets
Brick 11  ✓  App Intents (Connect to Host, Run Command)
Brick 12  -  Handoff
Brick 13  -  Mosh
Brick 14  -  Settings & polish
Brick 15  -  App Store submission
```

The current blocker to "I can actually SSH into my Mac" is Brick 7's second pass — Ed25519 key generation, Keychain storage, and wiring the public key through NIO's auth flow. Everything else is plumbed end-to-end; tap-to-connect surfaces a clean *"This Mac has no authentication set up"* message instead of crashing, which means the architecture works.

## Getting it running locally

You'll need Xcode 16+ on macOS, with the iOS 26 SDK.

```sh
git clone https://github.com/shio-sh/shio.git
cd shio
./scripts/bootstrap.sh
open Shio.xcodeproj
```

The bootstrap script is idempotent. It installs [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you don't have it, regenerates `Shio.xcodeproj` from `project.yml`, and fetches xterm.js + addons into `Shio/Resources/terminal/`. Re-run it any time you add files.

## Documentation

The brand, design system, and architecture are all locked in markdown:

- [`docs/brand.md`](docs/brand.md) — positioning, voice, naming standards.
- [`docs/design-tokens.md`](docs/design-tokens.md) — color, typography, spacing, motion, components.
- [`docs/app-icon-concepts.md`](docs/app-icon-concepts.md) — the locked icon decision with rejected alternatives.
- [`docs/landing-page-brief.md`](docs/landing-page-brief.md) — the brief for `shio.sh`.
- [`docs/setup.md`](docs/setup.md) — Mac-side setup script: what it does, what it won't, how to read it before running.

## Mac-side setup

Shio needs four things on your Mac to work end-to-end: Homebrew, `tmux`, Remote Login enabled, and Tailscale installed + signed in. Once the landing page is live, a single line handles the parts it can:

```sh
curl -fsSL https://shio.sh/setup | bash
```

Pre-landing-page, run [`scripts/mac-setup.sh`](scripts/mac-setup.sh) directly. The script is open source, asks for confirmation at every step, and touches only `~/.ssh/`, Homebrew-managed paths, and the System Settings pane it opens for you. See [`docs/setup.md`](docs/setup.md) for the trust model and a read-it-first option.

## Architecture

```
Shio/
├── ShioApp.swift                       @main + ModelContainer
├── DesignSystem/
│   ├── Tokens/                         color, type, spacing, motion, haptics
│   └── Components/                     ShioButton (more arrive in Brick 14)
├── Features/
│   ├── Onboarding/                     adaptive Tailscale walkthrough
│   ├── Hosts/                          list, add sheet (Tailscale + Direct SSH)
│   ├── Terminal/                       xterm.js host, input view, accessory row, scene, VM
│   ├── Settings/                       Pro Mode toggle, about
│   └── Shared/                         RootView (router)
├── Platform/
│   └── iPad/                           NavigationSplitView for regular size class
├── Core/
│   ├── SSH/                            SSHClient, TmuxResume
│   ├── Tailscale/                      URL-scheme detector
│   ├── Keyboard/                       KeyModifiers, ANSI translator
│   ├── Profiles/                       Host (SwiftData), container
│   └── Predictive/                     reserved (predictive echo)
├── Intents/                            App Intents + AppShortcutsProvider
├── Resources/
│   ├── terminal/                       xterm.js + addons + terminal.html
│   ├── fonts/                          Departure Mono, DotGothic16
│   └── Assets.xcassets/                AppIcon (locked 塩 master), AccentColor, LaunchBackground
ShioWidgets/                            WidgetKit extension (Brick 10)
ShioLiveActivities/                     ActivityKit extension (Brick 9)
```

## Stack

- **Swift 6**, strict concurrency.
- **iOS 26+, iPadOS 26+** — one binary, two bespoke UIs.
- **SwiftUI** primary, **UIKit** wrapping where needed (terminal view, keyboard accessory, low-level `UIKey` handling).
- **xterm.js** in a `WKWebView` for terminal rendering — the most battle-tested terminal emulator in existence, used by VS Code, Cursor, and every cloud IDE.
- **SwiftNIO SSH** for the SSH client.
- **WidgetKit**, **ActivityKit**, **App Intents**.

## Following along

The plan is to ship a TestFlight when the happy path works end-to-end, then iterate publicly from there.

If you want to follow along, **star this repo**. There's no waitlist email — stars are the signal. When TestFlight opens, the link will live in this README and on [shio.sh](https://shio.sh).

## License

The app source code license is not yet finalized — pending the App Store launch decisions. Bundled fonts (Departure Mono and DotGothic16) are OFL-licensed by their respective authors. xterm.js is MIT.

---

<p align="center">
  <sub>Built by <a href="https://amrith.co">Amrith</a> in 2026. <code>shio.sh</code> · <code>塩</code></sub>
</p>
