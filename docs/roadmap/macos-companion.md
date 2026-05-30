# Shio for Mac — roadmap

A macOS companion that makes Shio reachable without a separate Tailscale
install, by handling all the gnarly direct-SSH plumbing automatically.
Captured 2026-05-27 after a strategy discussion; revisit before scoping
the actual implementation.

## Why we're doing this

Tailscale-as-installed-dependency is the right v1.0 bet — it lets us
focus iOS-side polish on what matters (terminal UX, keyboard, libghostty)
without owning a network layer. But two apps to install is friction we
can eliminate later, and it puts a third-party service on the critical
path for an app that's otherwise self-contained.

Pro Mode (raw SSH) is the existing escape hatch for power users who
don't want Tailscale. The macOS companion turns Pro Mode into the
default path for *everyone*, not just experts, by automating the parts
that today require knowing what UPnP / port forwarding / authorized_keys
are.

## Product naming

- iOS app: **Shio**
- macOS app: **Shio** (same name; iOS and macOS bundle IDs are
  independent in App Store Connect, so both can ship as plain "Shio")
- In writing where disambiguation matters: "Shio for Mac" / "Shio for
  iPhone" — descriptive only, not branded
- The networking mode is **never named** in product surface. Users see
  "your Mac, reachable" and don't need to know whether bytes flow direct
  or via Tailscale.
- Engineering labels (internal): `Transport.direct`, `Transport.tailscale`

## Three modes, in user-facing order of importance

1. **Default (no name)** — direct connection via Shio for Mac.
   - Shio for Mac handles UPnP / NAT-PMP port forwarding, public IP
     tracking, pairing, key distribution.
   - Tiny Shio signaling service (Cloudflare Workers + Durable Objects)
     acts as a rendezvous point — never sees SSH bytes.
   - For ~85% of network conditions: just works. Direct TCP between
     iPhone and Mac, SSH on top.
2. **Tailscale** — surfaced only as a recovery path when direct fails.
   - Existing Tailscale flow stays in the codebase.
   - The only place "Tailscale" appears by name is on the disconnect
     overlay: *"Couldn't reach this Mac from your current network.
     [Set up Tailscale →]"*
3. **Manual SSH (Pro Mode)** — unchanged from today. Power users who
   want custom ProxyJump, non-default ports, jump hosts, manual key
   management.

## What "no relay" means and what we accept

We don't run a TURN-style relay. That means ~5–15% of network
conditions (symmetric NATs, CGNAT-on-CGNAT, restrictive corporate /
hotel WiFi) cannot establish direct connections even with hole-punching.

For those users, we don't fail — we graceful-degrade to the Tailscale
flow. They install Tailscale, sign in, done. Worse UX than direct, but
it's the same UX they'd have today, so it's not a regression.

This is a deliberate choice to avoid owning network infrastructure
forever. If usage scales and the 5–15% becomes large in absolute
numbers, we can revisit running our own relay then.

## Architecture (sketch, subject to detailed design)

```
iPhone Shio                Shio signaling                Shio for Mac
     │                       (CF Workers,                       │
     │  pair request          long-poll)                        │
     │ ─────────────────────────▶ │ ◀──────────────────────── │
     │                            │                            │ ← UPnP forward
     │  pull current Mac          │                            │ ← STUN: public IP
     │  reachability hints        │                            │
     │ ─────────────────────────▶ │ ─────────────────────────▶ │
     │                            │                            │
     │  TCP hole-punch / direct to Mac's public IP:port        │
     │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
     │                                                         │
     │  SSH handshake (E2E encrypted; signaling never sees this)
     │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
```

### Component checklist

- **Shio for Mac** (new SwiftUI macOS app)
  - Menu-bar app + onboarding window
  - Pairing flow: QR code shown on Mac, scanned by iPhone
  - UPnP / NAT-PMP forwarding via a small Go helper (compiled to
    static lib) or pure Swift port of the protocol
  - STUN client for public-IP discovery
  - Holds long-poll connection to Shio signaling
  - Trusted-iPhones list (with revoke button)
  - Writes paired iPhone's public key to `~/.ssh/authorized_keys`
    with correct perms (`chmod 600`, `chmod 700 ~/.ssh`)
  - System-tray UI showing active sessions, last connect time
  - Verifies Remote Login is enabled; deep-links to Settings if not

- **Shio signaling service** (new Cloudflare Workers + Durable Objects)
  - Stateless rendezvous endpoint
  - Persists nothing about SSH session contents (it never sees them)
  - Pairs short-lived; reachability hints replaced on each device IP
    change
  - Single DO instance per (mac, iphone) pair
  - No account, no email, no auth — pairing happens via shared key
    established during QR scan

- **iOS Shio changes**
  - `Transport` enum on `Host`: `.direct`, `.tailscale`, `.manual`
  - Onboarding "Add your Mac" flow becomes camera/QR scan path
    (Tailscale walkthrough kept behind a "Use Tailscale instead" link)
  - `SSHClient.Configuration` gains transport hints
  - Disconnect overlay gains "Set up Tailscale" CTA when direct fails

## What this lets us strip from iOS Shio (eventually)

- Tailscale detection / install prompt / open-Tailscale buttons can
  move from "first thing the user sees" to "fallback only"
- `TailscaleDiagnostic`'s `appInstalled` / `vpnActive` / `magicDNS`
  probes stay but become advisory rather than required
- "Use Tailscale DNS" instruction stays but becomes conditional
- The whole onboarding can simplify dramatically — most users go
  through "scan this QR code from your Mac" and that's it.

## What iOS Shio polish is safe to do *now* despite this future

Anything that doesn't touch the network transport:

- libghostty rendering polish (color, padding, font weight, scrolling)
- Keyboard accessory row design, key set, gestures
- Pinch-to-zoom refinement, double-tap-to-reset-zoom, etc.
- Theme system (light/dark/custom palettes)
- Live Activities (session status in Dynamic Island)
- Widgets (lock-screen / home-screen quick-connect)
- iPad layout (NavigationSplitView, command bar, multi-pane)
- Handoff between iOS devices
- App Intents / Shortcuts
- Settings UI / About / privacy screen / FaceID UX
- Accessibility audit (VoiceOver, Dynamic Type, contrast)

Anything that DOES need to think about future networking:

- `Host` data model — add a `transport` field now (optional, defaults
  to `.tailscale` to match current behavior). Cheap forward-compat.
- Add a `Transport` abstraction layer above `SSHClient` so the rest of
  the app doesn't care how connectivity is achieved.
- Avoid hard-coupling onboarding to Tailscale step names — wrap them
  in a flow object so we can add a "direct pairing" flow later
  without refactoring every step.

## Open questions to revisit before implementation

- Does Shio for Mac auto-launch at login? (Menu-bar daemon vs. opt-in)
- How does revocation work? (Mac-side button vs. global Shio key wipe)
- What happens if the user has 3 Macs paired and they share an iPhone
  with one of them? (Multi-mac discovery flow)
- Pairing-server abuse — rate limits, ephemeral DOs vs. permanent
- macOS sandbox: can we touch `~/.ssh/` from a sandboxed app? (Likely
  needs developer ID + non-sandboxed Mac App Store distribution, OR
  ship outside MAS)
- App Store review: is "writes to ~/.ssh" something Apple flags?
  (Likely fine since the user explicitly grants it via standard UI)
