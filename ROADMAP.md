# Roadmap

What's coming. Loosely ordered by current priority, not by hardness.

## Currently in flight

- **Tailscale onboarding & diagnostics refresh** — verification-driven onboarding with a `TailscaleDiagnostic` engine. Largely shipped; still iterating on edge cases.
- **Polish workstream** — keyboard hygiene, tmux install hint, terminal write buffering, multi-session support. See `~/.claude/plans/cozy-snacking-squid.md` for the active work.

## Pre-launch must-haves

- **Multi-session support** — multiple terminal windows to the same Mac, with tabs on iPad and a session pill / drawer on iPhone. Distinct tmux session names per Shio session so each persists independently.
- **Backgrounding + reconnect UX** — iOS suspends SSH within ~30s of backgrounding. We need clean disconnect detection on resume and one-tap reconnect that restores via tmux.
- **Known-hosts TOFU prompt** — surface the host's SHA-256 fingerprint on first connect, persist, reject mismatches thereafter.
- **Live Activities + Dynamic Island** behavior — currently a shell. Real lock-screen / Dynamic Island state: hostname, session duration, last command.
- **Widgets** behavior — tap-to-connect home screen widget.
- **App Store submission prep** — screenshots, App Preview video, privacy nutrition labels, App Review notes.

## Post-launch / nice-to-have

- **`brew install shio`** in [Homebrew's official formulas](https://formulae.brew.sh). A small `shio` CLI helper for Mac-side setup and diagnostics (`shio setup`, `shio doctor`, `shio key install`). Requires earning Homebrew's notability threshold first.
- **Handoff** — `NSUserActivity` broadcast/receive between iPhone, iPad, and (eventually) Mac Catalyst.
- **Mosh** — survives anything (network changes, sleep, backgrounding) via the SSP protocol. Significant scope; a Swift port of the reference C++ implementation.
- **Custom themes** — beyond the default light/dark Terminal Basic profile.
- **iCloud sync of profiles** — requires reintroducing CloudKit with the Host model's fields made optional/defaulted.
- **Mac Catalyst** — Shio as a Mac app, primarily for users who want to SSH from their Mac into other machines.

## Not on the roadmap

A few things we've deliberately decided against. Documenting so they don't get revisited under pressure.

- **A full macOS companion app** — too much install friction, doubles maintenance, can't actually toggle Remote Login anyway (Apple's security boundary).
- **Custom networking infrastructure** to replace Tailscale — Tailscale solves NAT traversal, identity, and DERP relay better than a side project could. We defer security-critical networking to people who specialize in it.
- **A `curl | bash` installer** — even well-designed, it asks users to extend trust we haven't earned. The four-step guide is the right shape.
- **Subscriptions, telemetry, accounts** — one-time purchase or free. Profiles sync via iCloud Keychain. No data leaves your devices.

## Things we want to do, eventually

- Apple Watch glance (connection status; maybe a "run saved command" complication).
- visionOS terminal — would feel native given the design system already maps cleanly.
- Real RunCommand intent — currently stubbed.
- Predictive local echo on tmux mode for high-latency connections.

---

The plan file at `~/.claude/plans/cozy-snacking-squid.md` is the canonical source-of-truth for current implementation details. This roadmap is the user-facing version.
