# shio

Premium iOS + iPadOS SSH client. Your Mac, in your pocket.

- Domain: [shio.sh](https://shio.sh)
- Status: pre-build (Brick 0 — brand + design system)

## Documentation

- [`docs/brand.md`](docs/brand.md) — positioning, voice, naming standards
- [`docs/design-tokens.md`](docs/design-tokens.md) — color, type, spacing, motion
- [`docs/app-icon-concepts.md`](docs/app-icon-concepts.md) — icon directions to mock in Figma
- Plan: `~/.claude/plans/cozy-snacking-squid.md`

## Build phases

0. **Brand & design system** ← *current*
1. Foundation (Xcode project, tokens in code)
2. Terminal rendering (xterm.js in WKWebView)
3. SSH core (SwiftNIO SSH)
4. Keyboard system (custom accessory + hardware passthrough)
5. Tmux auto-resume
6. Onboarding (adaptive Tailscale walkthrough)
7. Host management (Direct SSH Pro Mode)
8. iPad-bespoke layout
9. Live Activities + Dynamic Island
10. Widgets
11. App Intents / Shortcuts / Siri
12. Handoff
13. Mosh
14. Settings & polish
15. Submission
