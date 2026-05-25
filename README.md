# shio

Premium iOS + iPadOS SSH client. Your Mac, in your pocket.

- Domain: [shio.sh](https://shio.sh)
- Status: Bricks 0–8 + 11 shipped. Builds clean for iOS 26 simulator.

## Getting started

```sh
./scripts/bootstrap.sh        # installs XcodeGen if needed, generates Shio.xcodeproj, fetches xterm.js
open Shio.xcodeproj
```

The bootstrap script is idempotent — re-run it any time you add files to regenerate the project.

## Documentation

- [`docs/brand.md`](docs/brand.md) — positioning, voice, naming standards
- [`docs/design-tokens.md`](docs/design-tokens.md) — color, type, spacing, motion
- [`docs/app-icon-concepts.md`](docs/app-icon-concepts.md) — locked icon decision + rejected directions
- Plan: `~/.claude/plans/cozy-snacking-squid.md`

## Build phases

0. ✅ Brand & design system — icon locked, tokens locked
1. ✅ Foundation — XcodeGen project, design tokens in Swift, asset catalog, entitlements, widget + Live Activity shells
2. ✅ Terminal rendering — xterm.js bundled, WKWebView host, Swift ↔ JS bridge, theme bridge from design tokens to CSS variables
3. ✅ SSH core — SwiftNIO SSH async wrapper with PTY + shell channel, password + key-stub auth, host-key TOFU stub
4. ✅ Keyboard system — UIKit accessory row + hardware passthrough, modifier state machine (tap / hold / sticky), full ANSI escape translator
5. ✅ Tmux auto-resume — invisible `tmux new-session -A -s shio-<host>` integration with missing-tmux fallback
6. ✅ Onboarding — adaptive Tailscale flow: fast path if installed, guided steps only when needed
7. ✅ Host management — SwiftData Host model, profile CRUD, Direct-SSH Pro Mode form (ProxyJump, persistence modes)
8. ✅ iPad-bespoke layout — NavigationSplitView sidebar + detail, Cmd+N for new host, falls back to TabView on iPhone
9. Live Activities + Dynamic Island (stub in place — Brick 9 fills behavior)
10. Widgets (shell in place — Brick 10 fills behavior)
11. ✅ App Intents — ConnectToHost / RunCommand with HostEntity, surfaced via ShioAppShortcuts
12. Handoff (NSUserActivity broadcast/receive)
13. Mosh (SSP client in Swift)
14. Settings & polish
15. Submission

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
│   ├── SSH/                            SSHClient, TmuxResume (Mosh — Brick 13)
│   ├── Tailscale/                      URL-scheme detector
│   ├── Keyboard/                       KeyModifiers, ANSI translator
│   ├── Profiles/                       Host (SwiftData), ShioModelContainer
│   └── Predictive/                     (Brick 5 future — predictive echo)
├── Intents/                            App Intents + AppShortcutsProvider
├── Resources/
│   ├── terminal/                       xterm.js + addons + terminal.html (fetched by bootstrap)
│   └── Assets.xcassets/                AppIcon (locked 塩 master) + AccentColor + LaunchBackground
ShioWidgets/                            WidgetKit extension (Brick 10)
ShioLiveActivities/                     ActivityKit extension (Brick 9)
```

## Bricks remaining

Bricks 9, 10, 12, 13, 14, 15 — see `~/.claude/plans/cozy-snacking-squid.md` for full spec.
