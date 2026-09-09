# Shio — Brand

Updated September 2026, after the scope cut. See [`product.md`](product.md) for what
the product is; this file is how it sounds and how it holds its bar.

## One-line positioning

**A terminal that follows you.**

## Longer positioning

Shio is a terminal for Mac, iPhone and iPad. It runs local shells on your Mac and
SSHes into machines you own, organises that work by project rather than by host,
and puts the same session on whichever device you happen to be holding. Free, MIT
licensed, no account, no server of ours anywhere.

Note the order. The Mac is first because if Shio is not good enough to be someone's
only terminal there, the phone is a party trick.

## Why Shio exists

Desktop terminals do not follow you. Mobile ones are not good enough to be a
terminal:

- **Cluttered** (Termius): feature soup, pushes accounts and subscriptions.
- **Pro-coded** (Blink): powerful, priced and positioned for a narrow audience,
  with UX neglect showing in the reviews.
- **Abandonware** (the long tail): single-developer apps that look like 2014,
  charge monthly for a libssh2 wrapper, or quietly stopped updating.
- **Wrong tool** (iSH, a-Shell): emulating a local Linux on your phone, which is
  not what people mean when they say they want their Mac from their phone.

And on the desktop side, nothing treats the phone as a first-class place the same
work continues. That gap is the whole product.

## Brand values

These are the values we hold the bar against in every product, design, and copy decision:

1. **Minimal.** Less is the point. Settings stay short. Onboarding shows only the steps the user actually needs. The default screen is the terminal.
2. **Worth paying for, given away.** Shio is free and MIT licensed. It should still feel like something you would have paid for. Craft is the point, not the price tag. Never say "premium" in user-facing copy; earn the impression instead.
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
- **Pro Mode**, not "Advanced Settings" or "Developer Options", for raw SSH, ProxyJump and custom ports. It is a disclosure level, not a paid tier: everything in Shio is free.
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

- **Things 3 (Cultured Code)** — the gold standard for an app that feels handmade. Minimal type, restrained color, motion as character.
- **Bear** — quiet, focused, treats the user as capable. Settings are scarce; defaults are right.
- **Linear** — voice and copy as craft. Plain language, never clever.
- **Halide / Darkroom** — iOS apps that don't apologize for being made well.
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
