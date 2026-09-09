# Roadmap

Where Shio is and where it's going. Loosely ordered by priority, not hardness.

Shio 1.0 is a terminal. It is not an agent dashboard, a supervision console, or a hosted service, and the scope below is deliberately narrow: be good enough to use as your only terminal on a Mac, and carry that same work to a phone and an iPad.

## Shipped

- **Universal app** — iPhone, iPad, and a native Mac app (AppKit/SwiftUI around libghostty), one shared Swift core.
- **Real terminal** — libghostty and Metal. Local shells on Mac; SSH everywhere.
- **SSH and tmux** — SwiftNIO SSH, host-key pinning (trust on first use, refuses a changed key), and tmux holding sessions open on the host so they outlive the device that started them. On Mac, Shio uses your existing `~/.ssh` keys.
- **Projects-first** — organized around the work rather than a list of hosts; tabs and splits on Mac, a projects overview on every platform.
- **Reach** — works on the local network, Tailscale-native when you're away, plus QR and CloudKit pairing for your own devices.
- **Sync** — profiles via SwiftData and CloudKit, in your iCloud, no account with us.
- **iPad's own layout** — a proper three-column frame (rail, canvas, inspector), not a stretched iPhone.
- **Apple integrations** — Live Activities, widgets, App Intents (`ConnectToHost` and `RunCommand` are real, so Siri and Shortcuts can connect and run commands without opening the app), Handoff foundations.
- **Distribution** — Mac as a notarized Developer ID direct download, with Sparkle auto-update; iPhone and iPad on TestFlight.

## In progress

- **tmux control mode** — driving tmux with `-CC` so windows and panes are server-side and therefore exist on every device. Today a split made on the Mac lives only in the Mac's view tree and cannot follow you. The transport is built and tested against real tmux, and sits behind a setting on iOS while it earns trust. Making tmux windows into tabs and panes into splits, and deleting Shio's parallel split tree, is the next step.
- **Reconnect** — the reconnect state machine runs on both platforms, including wake and network-path recovery. What's left is polish on the edges.
- **App Store review** — iPhone and iPad are on TestFlight pending the 1.0 submission.

## Later / nice-to-have

- **Saved commands per project** — the two or three things you actually run in a repo, one tap away. Needs a new CloudKit entity, so it waits for a schema deploy.
- **`brew install shio`** — a small `shio` CLI helper for Mac-side setup and diagnostics (`shio setup`, `shio doctor`), once it earns Homebrew's notability threshold.
- **Mosh** — survives network changes and sleep via SSP. Significant scope (a Swift port); parked behind tmux and auto-reconnect for now.
- **Custom themes** beyond the default light and dark.
- **Apple Watch** glance — connection status, maybe a "run saved command" complication.
- **visionOS** — the design system maps cleanly.
- **Persistent host-key pinning across reinstalls, and a "trust new key" flow** — pinning currently lives in app storage.

## Deliberately not doing

Documented so they don't get revisited under pressure.

- **Agent supervision** — away-push when an agent stops, lock-screen approve and deny, a supervision console. It was built and it was cut. It made Shio a worse terminal and a mediocre dashboard at the same time, and every agent vendor is shipping their own version of it. Shio's job is to be the terminal those agents run in.
- **Mac App Store distribution** — it mandates the App Sandbox, which forbids running arbitrary shells and reading your files. A real terminal can't live there; Shio ships notarized and direct, like iTerm, Ghostty and Warp.
- **Custom networking to replace Tailscale** — Tailscale solves NAT traversal, identity and relay better than a side project could. Security-critical networking is deferred to specialists.
- **A `curl | bash` installer** — it asks for trust we haven't earned. The guided setup is the right shape.
- **Accounts, telemetry, subscriptions for their own sake** — no account with us, no telemetry, nothing leaves your devices that you didn't send.
