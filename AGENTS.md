# Shio

A real terminal for Mac, iPhone and iPad, organised by project, over SSH to
machines you own. Swift 6 strict concurrency. Monorepo.

## Before your first build

`Shio.xcodeproj` is NOT in git — it is generated. Three things a fresh clone
needs, in order:

```
brew install xcodegen tmux
./scripts/refresh-ghostty.sh --fetch   # ~800 MB of prebuilt libghostty static libs
./scripts/bundle-tmux.sh               # ShioMac/Resources/tmux, referenced by the Mac target
xcodegen generate
```

Skipping either script gives you a build failure that reads like a broken repo:
a missing `GhosttyKit` symbol, or `lstat(ShioMac/Resources/tmux)`.

## Targets

| Target | Notes |
|---|---|
| `Shio` | iOS + iPadOS |
| `ShioMac` | macOS. Product is named "Shio"; **module name is also `Shio`**, so tests say `@testable import Shio` |
| `ShioKitTests` | the real suite (132 tests), hosted in ShioMac |
| `ShioAppTests` | iOS-only seams |

Run the suite:
`xcodebuild test -project Shio.xcodeproj -scheme ShioMac -destination 'platform=macOS'`

CI is `.github/workflows/checks.yml` on every push: invariants, the Mac suite,
and an iOS compile. The iOS suite does **not** run — the test host crashes on
launch in the simulator, pre-existing and unfixed. Only `build-for-testing`
happens there, which is still enough to catch a test file that stops compiling.

## Things that will bite you

- **Build SIGNED or CloudKit traps at launch.** Ad-hoc or unsigned Mac builds
  have no iCloud entitlement. `ModelContainer` does not throw on that; it
  initialises, logs "sync ACTIVE", then CloudKit kills the process. `HostStore`
  checks the entitlement up front for exactly this reason — leave that check in.
- **The Mac ships with no push entitlement.** The App ID `sh.shio.app.mac` has
  no Push capability in the developer portal, so `aps-environment` is stripped
  at signing and CloudKit can never wake the Mac. Sync is poll-only until that
  is fixed in the portal. `release-mac.yml` now refuses to ship without it.
- **CloudKit production schema is append-only.** Debug maps to the development
  environment, Release to production. You cannot remove or retype a field in
  production, ever. `Action`, `Signal` and `CD_Skill` are stuck there.
- **libghostty is a rebasable patch series**, not a vendored copy. The fork is
  `shio-sh/ghostty`; our patch adds an External-IO backend and its C ABI. Never
  hardcode a Zig version — read `minimum_zig_version` from ghostty's
  `build.zig.zon`.
- **The SSH exec channel has a bare PATH.** Non-interactive, so the login
  shell's PATH never ran and Homebrew tmux is invisible. `TmuxResume.execLine`
  repairs PATH explicitly. Do not "simplify" that away.
- **`MacLocalLaunch` builds a shell command wrapped in single quotes**, so the
  script inside must contain none. It did once and zsh failed to parse the
  whole line, which killed every local project terminal on the Mac. There is a
  test that runs the real shell over the generated command; keep it.

## Architecture, briefly

Projects contain repos; repos have checkouts, one per machine. `Host` is a
machine. A device recognises its own `Host` record by `deviceID` and opens
those projects on a local PTY instead of SSHing to itself — `MacSelfHost`
owns that identity and merges duplicate records. The Mac's id is derived from
`IOPlatformUUID` so wiping defaults cannot fork it into two machines.

Sessions survive via server-side tmux (`shio-<name>`), not Mosh. Control mode
(`tmux -CC`) is behind a setting.

## Working here

Design and copy decisions are Amrith's, usually made with Claude first. Match
the surrounding code's comment density and naming — this codebase explains
*why*, in prose, and a bare diff will look foreign.
