# Roadmap

Where Shio is and where it's going. Loosely ordered by priority, not hardness.

## Shipped

- **Universal app** — iPhone, iPad, and a **native Mac** companion (AppKit/SwiftUI around libghostty), one shared Swift core.
- **Real terminal** — libghostty + Metal. Local shells on Mac; SSH everywhere.
- **SSH + tmux** — SwiftNIO SSH, host-key pinning (trust-on-first-use, refuses a changed key), tmux session continuity across devices. On Mac, Shio uses your existing `~/.ssh` keys.
- **Projects-first** — organized around the work, not just hosts; tabs and splits on Mac.
- **Pairing & reach** — Tailscale-native, plus QR/CloudKit pairing for your own devices.
- **Sync** — profiles via SwiftData + CloudKit (your iCloud, no account with us).
- **Agent supervision** — push when an agent **stops and needs you**, one-tap **approve / deny** from the lock screen (notification actions, answered over CloudKit), and jump-back routing into the **exact session** that needs attention.
- **iPad's own layout** — a proper three-column frame (rail · canvas · inspector), not a stretched iPhone.
- **Apple integrations** — Live Activities, widgets, App Intents (`ConnectToHost` and `RunCommand` are real — Siri/Shortcuts can connect and run commands without opening the app), Handoff foundations.
- **Distribution** — iPhone/iPad on TestFlight; Mac as a notarized Developer ID direct download (the App Store sandbox can't host a real terminal).

## Agent supervision: what remains

The reason Shio exists in the "agent era." The experience is built — away-push, lock-screen approve/deny, jump-back — so what's left is earning trust in it:

- **On-device verification** across real agents and real away sessions (not just the happy path).
- **Polish** — the timing, wording, and failure behavior a lock-screen decision deserves.

## In progress / near-term

- **Reconnect UX** — the reconnect state machine now runs on both platforms (iOS, plus the Mac port with wake/path recovery); what's left is polish on the edges.
- **Live Activities / Dynamic Island** — real lock-screen state (host, session, last command), beyond the current shell.
- **Widgets** — tap-to-connect home-screen widget behavior.
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
