<p align="center">
  <img src="assets/icon/shio-180.png" width="120" height="120" alt="shio icon">
</p>

<h1 align="center"><code>shio</code></h1>

<p align="center"><em>The terminal for the agent era.</em></p>

<p align="center">
  Native on Mac, iPhone, and iPad. SSH into anything you own.
</p>

<p align="center">
  <code>塩</code>
</p>

<p align="center">
  <sub>iPhone + iPad in TestFlight · Mac as a notarized direct download · building in public.</sub>
</p>

---

## What Shio is

Shio is a native terminal for **Mac, iPhone, and iPad** — one app, three devices, built for the way work happens now: coding agents (Claude Code, Codex, whatever you run) doing long jobs on machines you own, while you move between your desk, your couch, and the world.

It connects over **SSH to any host you control** — your Mac, a Linux box, a Raspberry Pi, a VPS. Vendor-neutral: your hardware, your keys, no hosted middleman. The terminal you already trust, everywhere you are.

Two things make it more than a connection list:

- **Projects, not just hosts.** Shio organizes around the work — a project is its repo and the live session(s) running in it — so you reach for *the thing you're doing*, not the machine it's on. Start a session on your Mac, pick up the exact same one on your phone (tmux-backed continuity).
- **A real terminal.** Rendering is [libghostty](https://github.com/ghostty-org/ghostty), the GPU-accelerated Ghostty engine — not a web view. Selection, scrollback, colors, copy/paste, and the keyboard behave the way a terminal should, native on each platform.

## Principles

- **Your machines, your keys.** Vendor-neutral SSH to hardware you own. On Mac, Shio uses your existing `~/.ssh` keys; on iPhone/iPad it brings its own key you install once. No account with us, no telemetry.
- **The terminal is sacred.** Behavior, colors, copy/paste, scroll, selection — a real terminal, not an approximation.
- **The keyboard is the product.** Every chord that works in a desktop terminal works here — soft accessory row, hardware keyboard, full modifier handling.
- **Apple-platform-native.** Live Activities, Dynamic Island, widgets, App Intents, Handoff, a real Mac app — woven in, not bolted on.
- **Quiet by default.** No upsells, no badges, no banners. Shio opens to your terminal.

## What's shipped

- **Universal app** — iPhone, iPad, and a native **Mac** companion (AppKit/SwiftUI around libghostty, not Catalyst), sharing one Swift core.
- **Terminal** — libghostty + Metal; local shells on Mac, SSH everywhere.
- **SSH + tmux** — SwiftNIO SSH, host-key pinning (trust-on-first-use), `tmux` session continuity across devices.
- **Projects** — projects-first organization on iOS and Mac; tabs and splits on Mac.
- **Pairing & reach** — Tailscale-native, plus QR/CloudKit pairing for your own devices.
- **Apple integrations** — Live Activities, widgets, App Intents, Handoff.

**Distribution:** iPhone/iPad ship via **TestFlight**; the Mac app ships as a **notarized Developer ID** direct download (the Mac App Store mandates the App Sandbox, which forbids a real terminal — so Shio ships the way iTerm, Ghostty, and Warp do). Get it at [shio.sh/mac](https://shio.sh/mac).

**Next:** deeper **agent supervision** — push-notify when an agent stops and needs you, one-tap approve/deny, jump straight back into the session. The foundations are here; the experience lands in a future version, built right rather than shipped as a stub.

## Running it locally

You'll need a recent Xcode on macOS.

```sh
git clone https://github.com/shio-sh/shio.git
cd shio
scripts/refresh-ghostty.sh --fetch   # pulls the prebuilt GhosttyKit.xcframework
xcodegen                             # generates Shio.xcodeproj from project.yml
open Shio.xcodeproj
```

The Ghostty binary is large and lives out of git as a GitHub Release asset; `--fetch` pulls it. Schemes: **Shio** (iPhone/iPad) and **ShioMac** (Mac).

## Connecting to your machines

The local Mac terminal works the moment Shio opens. To reach other machines over SSH, the one-minute setup walks you through Tailscale and a single key: [shio.sh/setup](https://shio.sh/setup) (also in [`docs/setup.md`](docs/setup.md)). Every step uses an existing trusted tool — Tailscale's signed installer, Apple's System Settings, your own Terminal. **Shio asks you to install nothing of its own on the machines you connect to.**

## Architecture

One repository, a shared Swift core, two app targets:

```
Shio/                  shared Core (SwiftUI/SwiftData + CloudKit, SwiftNIO SSH,
                       libghostty bridge) + the iPhone/iPad app
ShioMac/               native AppKit/SwiftUI Mac app around libghostty
ShioWidgets/           WidgetKit extension
ShioLiveActivities/    ActivityKit extension
Frameworks/            GhosttyKit.xcframework (libghostty, fetched via --fetch)
scripts/               refresh-ghostty.sh, etc.
```

Core highlights: `Core/SSH` (SSHClient, SystemSSHKeys, host-key pinning, TmuxResume), `Core/Keys` (KeyManager — device-bound Ed25519), `Core/Pairing`, `Core/Profiles` (Host/Project SwiftData models, CloudKit-synced).

## Stack

- **Swift 6**, strict concurrency. One codebase across iOS, iPadOS, and macOS.
- **SwiftUI** primary; **UIKit**/**AppKit** where the platform needs it.
- **[libghostty](https://github.com/ghostty-org/ghostty)** + **Metal** for terminal rendering.
- **SwiftNIO SSH** for the SSH client.
- **SwiftData + CloudKit** for profiles/sync; **WidgetKit**, **ActivityKit**, **App Intents**.

## Following along

iPhone/iPad beta is on **TestFlight** and the Mac app is a free notarized download — both reachable from [shio.sh](https://shio.sh). **Star this repo** to follow along.

## License

App source license is not yet finalized — pending launch decisions. Bundled fonts (Departure Mono, DotGothic16) are OFL-licensed by their authors. Ghostty / libghostty is MIT-licensed by its authors.

---

<p align="center">
  <sub>Built by <a href="https://amrith.co">Amrith</a> in 2026. <code>shio.sh</code> · <code>塩</code></sub>
</p>
