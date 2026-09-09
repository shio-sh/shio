<p align="center">
  <img src="assets/icon/shio-180.png" width="120" height="120" alt="shio icon">
</p>

<h1 align="center"><code>shio</code></h1>

<p align="center"><em>The terminal for structured work.</em></p>

<p align="center">
  Native on Mac, iPhone, and iPad. SSH into machines you own.
</p>

<p align="center">
  <code>塩</code>
</p>

<p align="center">
  <sub>Mac as a notarized direct download · iPhone and iPad in TestFlight · free and MIT licensed.</sub>
</p>

---

## What Shio is

Shio is a terminal you can use as your only terminal. It runs local shells on your Mac and connects over SSH to the machines you already own: another Mac, a Linux box, a Raspberry Pi, a VPS.

Then it puts the same work on your phone and your iPad, because the session lives on the machine rather than in the app.

Two things make it more than a connection list:

- **Projects, not a wall of tabs.** A project holds its repos, the machines they live on, and the shells you opened for them. Open a project and you land in the right directory on the right machine, with the branch and the uncommitted count in front of you. Same shape on all three devices.
- **A real terminal.** Rendering is [libghostty](https://github.com/ghostty-org/ghostty), the engine behind Ghostty, compiled natively rather than wrapped in a web view. Selection, scrollback, colors, copy and paste, and the keyboard behave the way a terminal should. Which is why vim, htop and lazygit render on a phone instead of falling apart.

## Principles

- **Your machines, your keys.** SSH to hardware you own. On Mac, Shio uses your existing `~/.ssh` keys; on iPhone and iPad it brings its own key that you install once. There is no Shio server, no account, no telemetry. If this project vanished, the app on your Mac would keep working.
- **The terminal is sacred.** Behavior, colors, copy and paste, scroll, selection. A real terminal, not an approximation.
- **The keyboard is the product.** Every chord that works in a desktop terminal works here: soft accessory row, hardware keyboard, full modifier handling.
- **Apple-platform-native.** Live Activities, widgets, App Intents, Handoff, a real Mac app. Woven in, not bolted on.
- **Quiet by default.** No upsells, no badges, no banners. Shio opens to your terminal.

## What's shipped

- **Universal app.** iPhone, iPad, and a native Mac app (AppKit/SwiftUI around libghostty, not Catalyst), sharing one Swift core.
- **Terminal.** libghostty and Metal; local shells on Mac, SSH everywhere.
- **SSH and tmux.** SwiftNIO SSH, host-key pinning on first use, and tmux holding sessions open on the machine so they survive you closing the lid.
- **Projects.** Projects-first organization on every platform, with tabs and splits on Mac.
- **Sync.** Projects, machines, and settings sync privately over iCloud between your own devices.
- **Reach.** Works on your local network, and Tailscale-native when you are away.
- **Apple integrations.** Live Activities, widgets, App Intents, Handoff.

**Distribution:** the Mac app ships as a notarized Developer ID direct download, because the Mac App Store mandates the App Sandbox and a real terminal cannot live in one. This is how iTerm, Ghostty and Warp ship too. iPhone and iPad are in TestFlight while App Store review goes through. Get both at [shio.sh](https://shio.sh).

## Running it locally

You'll need a recent Xcode on macOS.

```sh
git clone https://github.com/shio-sh/shio.git
cd shio
scripts/refresh-ghostty.sh --fetch   # pulls the prebuilt GhosttyKit.xcframework
xcodegen                             # generates Shio.xcodeproj from project.yml
open Shio.xcodeproj
```

The Ghostty binary is large and lives outside git as a GitHub Release asset; `--fetch` pulls it. Schemes: **Shio** (iPhone and iPad) and **ShioMac** (Mac).

Build signed. An unsigned build has no iCloud entitlement, and CloudKit traps at launch with a stack trace that blames something else entirely.

## Connecting to your machines

The local Mac terminal works the moment Shio opens. To reach other machines over SSH, the one-minute setup walks you through Tailscale and a single key: [shio.sh/setup](https://shio.sh/setup), also in [`docs/setup.md`](docs/setup.md). Every step uses a tool you already trust: Tailscale's signed installer, Apple's System Settings, your own Terminal. **Shio asks you to install nothing of its own on the machines you connect to.**

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

Core highlights: `Core/SSH` (SSHClient, SystemSSHKeys, host-key pinning, TmuxResume, and the tmux control-mode protocol), `Core/Keys` (KeyManager, device-bound Ed25519), `Core/Pairing`, `Core/Profiles` (Host and Project SwiftData models, CloudKit-synced).

libghostty is carried as a rebasable patch series on top of upstream Ghostty. See [`scripts/refresh-ghostty.sh`](scripts/refresh-ghostty.sh); a scheduled workflow proposes upstream bumps rather than applying them.

## Stack

- **Swift 6**, strict concurrency. One codebase across iOS, iPadOS, and macOS.
- **SwiftUI** primary; **UIKit** and **AppKit** where the platform needs it.
- **[libghostty](https://github.com/ghostty-org/ghostty)** and **Metal** for terminal rendering.
- **SwiftNIO SSH** for the SSH client.
- **SwiftData + CloudKit** for profiles and sync; **WidgetKit**, **ActivityKit**, **App Intents**.

## Following along

The Mac app is a free notarized download and the iPhone and iPad beta is on TestFlight, both reachable from [shio.sh](https://shio.sh). **Star this repo** to follow along.

## License

Shio is MIT licensed, see [LICENSE](LICENSE). Bundled fonts (Departure Mono, DotGothic16) are OFL-licensed by their authors. Ghostty and libghostty are MIT-licensed by their authors.

---

<p align="center">
  <sub><a href="https://duskresearch.com">Dusk Research</a> · <code>塩</code></sub>
</p>
