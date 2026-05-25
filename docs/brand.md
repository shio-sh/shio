# Shio — Brand

## One-line positioning

**Shio is the terminal you'd expect Apple to make. Your Mac, in your pocket.**

## Longer positioning

Shio is a premium iOS and iPadOS SSH client built for developers who want their Mac in their pocket — and want it to feel native, calm, and uncompromisingly well-made. Tailscale-native by default, full SSH config available in Pro Mode. No clutter. No subscription. No slop.

## Why Shio exists

Every iOS terminal in 2026 is one of:

- **Cluttered** (Termius): bloated, feature-soup, pushes accounts and subscriptions.
- **Expensive / pro-coded** (Blink): powerful but priced and positioned only for pros, with reviews falling because of UX neglect.
- **Suspicious / abandonware** (the long tail): single-developer apps that look like 2014, charge $4.99/month for a libssh2 wrapper, or quietly stopped updating.
- **Wrong tool** (iSH, a-Shell, etc.): emulating a local Linux on your phone — not what most people want when they say "I want to use my Mac from my phone."

There is no clean, premium, "just works" option. Shio is that option.

## Brand values

These are the values we hold the bar against in every product, design, and copy decision:

1. **Minimal.** Less is the point. Settings stay short. Onboarding shows only the steps the user actually needs. The default screen is the terminal.
2. **Premium.** Should feel like it cost $20 even at $2.99 or free. Hand-crafted, considered, intentional.
3. **Quiet.** No badges, no banners, no upsells. Shio does not interrupt.
4. **Crafted.** Type, color, motion, copy, sound, haptics — all signed off. Nothing left "good enough."
5. **Opinionated.** Defaults matter more than options. Most users never open Settings.
6. **Unobtrusive.** Get out of the way. The user is here to use their Mac, not Shio.
7. **Trustworthy.** No telemetry. No account. No data leaves the user's devices unless they SSH it themselves.

## Brand voice

### How Shio talks

**Plain, calm, never clever for its own sake.** Shio sounds like a thoughtful colleague who knows what they're doing — not a startup mascot, not a Linux man-page, not a marketing intern.

**Short sentences. No exclamation marks. No emoji.** (Light haptics and visual feedback do the work emoji would do elsewhere.)

**Translate, don't transcribe.** SSH says "Connection refused"; Shio says "Your Mac isn't responding. It might be asleep, or Tailscale might not be running on both devices." Same information, no jargon, action implied.

**Address the user as "you," not "the user."** When a confirmation needs a subject, Shio says "Your Mac is fine — we just removed it from Shio" not "Host successfully deleted from local database."

**Never apologize for being a terminal app.** Don't say "for power users only" or "we know this looks intimidating." Treat the user as capable of learning what they don't yet know.

### What Shio doesn't say

- ❌ "Welcome to the future of SSH on iOS!"
- ❌ "🎉 Connected!"
- ❌ "Whoops, something went wrong."
- ❌ "Pro tip: …"
- ❌ "Awesome! Let's get started!"
- ❌ Marketing words: revolutionary, seamless, magical, AI-powered, world-class.

### What Shio does say

- ✅ "Pick your Mac."
- ✅ "Connected to `studio.tail-scale.ts.net`."
- ✅ "Your Mac isn't responding. It might be asleep."
- ✅ "Tailscale isn't installed on this iPhone. Install it from the App Store?"
- ✅ "Delete `studio` from Shio? Your Mac itself isn't affected."

### Tone in different contexts

| Context | Tone |
|---|---|
| Onboarding | Calm, instructive, never condescending. One thing at a time. |
| Errors | Plain language, what happened, what to try. Never modal stack-traces. |
| Empty states | Quiet. A single short sentence. Never "Nothing here yet 😢" |
| Success confirmations | None where possible. State changes are the confirmation. |
| Marketing surface | Confident, minimal, lets the screenshots do most of the work. |
| App Store description | Functional. Lead with what it does, not why it's great. |

## Naming standards

### The name

- **Word**: Shio
- **Pronounced**: shee-oh (`/ʃiːoʊ/`)
- **Etymology** (public origin story): `sh` is the shell, `io` is input/output, the word sneaks "iOS" inside, and *shio* (塩) is Japanese for salt — the minimal, essential seasoning that brings everything else to life.
- **Wordmark**: lowercase `shio`. Always lowercase. No italics, no all-caps, no `SHIO`, no `Shio.app`, no `Shio - iOS Terminal`.

### When the name is written

| Form | When |
|---|---|
| `shio` | The wordmark. App icon, hero copy, marketing surface. |
| `Shio` | Prose and sentence case. App Store title, body copy, this document. |
| `shio.sh` | Domain, URLs. |
| `Shio for iPhone` / `Shio for iPad` | When platform is relevant. Never `iPhone Shio`. |

### Names of things inside Shio

- **Mac**, not "host" or "server" or "endpoint" — even though Shio supports any SSH server, the user-facing word is *Mac* in the default flow.
- **Session**, not "connection" or "tab" — for the active terminal experience.
- **Pro Mode**, not "Advanced Settings" or "Developer Options" — when we unlock raw SSH/ProxyJump/custom ports.
- **Key**, not "private key" or "SSH key" in everyday UI — qualify only when it could be ambiguous.

### Names we don't use

- "User" (use "you")
- "Device" (use "iPhone", "iPad", or "Mac")
- "Sync" (we don't sync anything user-facing)
- "Cloud" (avoid; iCloud Keychain is invisible when it works)
- "Server" (use "Mac" or, in Pro Mode, the actual hostname)

## Visual identity (overview — full spec in `design-tokens.md`)

- **Mark**: see `app-icon-concepts.md`. The chosen direction informs the brand mark.
- **Wordmark**: lowercase `shio`, set in a custom-tuned monospace (likely SF Mono, ligatures off) or a precise geometric sans (likely a custom letter-spaced cut of Inter or a licensed display face — to be finalized in Figma).
- **Color**: a near-black ground in dark mode, a near-white ground in light mode, with a single accent color used sparingly. Terminal-color palette is the macOS Terminal "Basic" profile, untouched.
- **Motion**: minimal, fast, never decorative. UI chrome moves; the terminal does not.

## Marketing principles

- **Show, don't tell.** The website and App Store screenshots show the app working, not slogans about how good it is.
- **No celebrities, no testimonials in v1.** Quotes can come later, organically.
- **Don't oversell Tailscale.** Tailscale is *how* — not *why*. Tell users what Shio does, then show how setup is one-tap easy.
- **The landing page is one scroll long.** No "features grid" for its own sake.
- **App Store screenshots show real terminals doing real work** — Claude Code running, htop, neovim, tmux — not staged hero shots with "Connect from anywhere" overlaid.

## Brand DNA — references and anti-references

### What Shio borrows from

- **Things 3 (Cultured Code)** — the gold standard for "premium iOS app that feels handmade." Minimal type, restrained color, motion as character.
- **Bear** — quiet, focused, treats the user as capable. Settings are scarce; defaults are right.
- **Linear** — voice and copy as craft. Plain language, never clever.
- **Cardpointers / Halide / Darkroom** — premium iOS apps with one-time-or-tier pricing that don't apologize for being made well.
- **macOS Terminal "Basic" profile** — the visual baseline for what a terminal should look like.

### What Shio is *not* like

- ❌ Termius (cluttered, all-things-to-all-people)
- ❌ Blink (paywall-pushy, neglected UX)
- ❌ Hyper (heavy, JS-flavored, themed-to-death)
- ❌ Putty / OpenSSH config files (raw power without guardrails — that's Pro Mode's specific niche, not Shio's vibe)
- ❌ Cloud-IDE marketing (vague promises, hero screenshots with browser chrome, "code from anywhere")

## Decision tree

When in doubt, ask:

1. **Is this calm?** If a screen, sound, or copy element raises the user's pulse, reconsider.
2. **Does the user need this?** If you can ship a smaller version, ship the smaller version.
3. **Could a colleague say this out loud and not sound silly?** That's the voice test.
4. **Would Things 3 do this?** That's the craft test.
5. **Is this the user's terminal, or our app?** If our app, get out of the way.
