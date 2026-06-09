# Roadmap

Where Shio is and where it's going. Loosely ordered by priority, not hardness.

## Shipped

- **Universal app** — iPhone, iPad, and a **native Mac** companion (AppKit/SwiftUI around libghostty), one shared Swift core.
- **Real terminal** — libghostty + Metal. Local shells on Mac; SSH everywhere.
- **SSH + tmux** — SwiftNIO SSH, host-key pinning (trust-on-first-use, refuses a changed key), tmux session continuity across devices. On Mac, Shio uses your existing `~/.ssh` keys.
- **Projects-first** — organized around the work, not just hosts; tabs and splits on Mac.
- **Pairing & reach** — Tailscale-native, plus QR/CloudKit pairing for your own devices.
- **Sync** — profiles via SwiftData + CloudKit (your iCloud, no account with us).
- **Apple integrations** — Live Activities, widgets, App Intents, Handoff foundations.
- **Distribution** — iPhone/iPad on TestFlight; Mac as a notarized Developer ID direct download (the App Store sandbox can't host a real terminal).

## Next major: agent supervision

The reason Shio exists in the "agent era" — and the part we're building right rather than shipping as a stub:

- Push when an agent **stops and needs you** (a prompt, a confirmation, a failure).
- **One-tap approve / deny** from the lock screen, without opening the app.
- Jump straight back into the **exact session** that needs attention.

The plumbing (agent detection, away signals, Live Activities) exists; the supervision *experience* lands in a future version.

## In progress / near-term

- **Reconnect UX** — iOS suspends SSH within ~30s of backgrounding; clean disconnect detection on resume and one-tap tmux-restore.
- **Live Activities / Dynamic Island** — real lock-screen state (host, session, last command), beyond the current shell.
- **Widgets** — tap-to-connect home-screen widget behavior.
- **App Intents** — real `RunCommand` and `ConnectToHost` (currently stubbed/foreground-only).
- **Public beta hardening** — external TestFlight, landing/onboarding, the polish a first impression needs.

## Later / nice-to-have

- **`brew install shio`** — a small `shio` CLI helper for Mac-side setup/diagnostics (`shio setup`, `shio doctor`), once it earns Homebrew's notability threshold.
- **Mosh** — survives network changes/sleep via SSP. Significant scope (a Swift port); parked behind tmux + auto-reconnect for now.
- **Custom themes** beyond the default light/dark.
- **Apple Watch** glance — connection status, maybe a "run saved command" complication.
- **visionOS** — the design system maps cleanly.
- **Persistent host-key pinning across reinstalls / a "trust new key" flow** — current pinning lives in app storage.

## Deliberately not doing

Documented so they don't get revisited under pressure.

- **Mac App Store distribution** — it mandates the App Sandbox, which forbids running arbitrary shells and reading your files. A real terminal can't live there; Shio ships notarized and direct, like iTerm, Ghostty, and Warp.
- **Custom networking to replace Tailscale** — Tailscale solves NAT traversal, identity, and relay better than a side project could. We defer security-critical networking to specialists.
- **A `curl | bash` installer** — it asks for trust we haven't earned. The guided setup is the right shape.
- **Accounts, telemetry, subscriptions-for-their-own-sake** — no account with us, no telemetry, nothing leaves your devices that you didn't send.
