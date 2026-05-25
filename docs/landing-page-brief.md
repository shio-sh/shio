# Shio — Landing Page Brief

> Standalone brief for building `shio.sh`. The brand and design system are already locked in `brand.md`, `design-tokens.md`, and `app-icon-concepts.md` — read those first; this doc only adds what's specific to the landing page.

---

## What we're building

A **one-scroll** landing page at `shio.sh` that introduces the app to developers who'd want it. Calm, minimal, premium-feeling. No clever marketing slogans. No feature grid. The icon and the positioning line do most of the talking.

The app is an iOS + iPadOS SSH client that's Tailscale-native. Pre-launch — not on the App Store yet. The landing page exists to (a) let the right people find it, (b) collect interest signal without spam, (c) be a reference link for early sharing.

---

## Executive decisions (locked — don't revisit)

The user was on the fence on a few things. These are decided now so the next session can just execute.

### 1. Capitalization → **lowercase wordmark, `Shio` everywhere else**

`shio` (lowercase) is the **wordmark only** — used wherever it's functioning as a visual brand identity. `Shio` (sentence case) is used everywhere the word is appearing as ordinary text. This is the eBay / Adobe / Airbnb pattern: lowercase logo, sentence-case word in titles and prose.

| Context | Form | Notes |
|---|---|---|
| Wordmark (logo, hero H1, footer brand mark) | `shio` | Functions as visual brand. Almost always set in DotGothic16 (the icon font). |
| HTML `<title>` | `Shio — your Mac, in your pocket.` | Browser tab reads "Shio". |
| Open Graph / Twitter meta titles | `Shio — your Mac, in your pocket.` | — |
| Body prose | `Shio` | "Shio is a clean, minimal SSH client." |
| Section headings (non-wordmark) | `Shio` | If the page ever adds a heading like "What Shio is for" — sentence case. |
| App Store listing title | `Shio` | — |
| Domain | `shio.sh` | Always lowercase (it's a URL). |

Considered and rejected: aggressive-lowercase-everywhere ("shio is a clean..."), bell hooks / allbirds style. Felt like a stylistic tic that clashes with the "quiet, never clever for its own sake" voice principle.

### 2. Hosting → **Cloudflare Pages, with `shio.sh` as the custom domain**

Not GitHub Pages. Reasons:
- The user already runs Medivalent on Cloudflare Workers + Pages — familiar territory.
- Domain is already in their Cloudflare dashboard (or trivially moved there).
- Cloudflare Pages gives us a path to add a tiny Worker later if we want a waitlist counter, geo-routing for App Store, or any small dynamic touch — without re-platforming.
- Faster edge CDN, free TLS, atomic deploys.

The user's other indie project, [`pasture-sh.github.io`](https://github.com/amrith/pasture-sh.github.io), uses GitHub Pages as precedent. We're deliberately doing this one on Cloudflare for the extensibility headroom.

**Repo layout**: create a new repo `github.com/shio-sh/shio.sh` (organization owns the domain too) or alternatively `github.com/shio-sh/landing`. Wire to CF Pages via git integration. Add `shio.sh` as the custom domain in the CF Pages settings.

### 3. Waitlist mechanism → **GitHub star, no email collection**

We are *not* doing email collection. Reasons:
- The user explicitly doesn't want to set up Resend / mail infra.
- Email lists for unreleased apps are a chore for everyone.
- The audience is developers — they know what "star this repo" means and it's already where they live.

What the CTA looks like:
- A single button: **"Star on GitHub"** that links to `github.com/shio-sh/shio`.
- Below the button, a tiny static line: *"Public TestFlight when v1.0 ships. Star to follow along."*
- If/when TestFlight goes public, swap the CTA text to "Join the TestFlight" with a link to the TestFlight URL.

Optional second-tier: an unobtrusive RSS link to the repo's releases feed (`github.com/shio-sh/shio/releases.atom`). One line, footer-only. Skip if it adds noise.

**Explicitly rejected**: email capture, Mailchimp, Resend, Substack, Twitter follow CTA, "subscribe to notify."

---

## Page structure (one scroll, mobile-first)

Aim for a page that fits in ~1.5 viewport heights on mobile, ~1 on desktop. Long-scroll marketing pages are anti-brand.

```
┌──────────────────────────────────────┐
│  [shio icon, 96–120px]               │
│  shio                                │
│                                      │
│  Your Mac, in your pocket.           │
│  A clean, minimal SSH client for     │
│  iPhone and iPad. Tailscale-native.  │
│                                      │
│  [ Star on GitHub ]                  │
│  Public TestFlight when v1.0 ships.  │
└──────────────────────────────────────┘
   ──── scroll line ────
┌──────────────────────────────────────┐
│  [3–4 screenshots: terminal,         │
│   onboarding, host list, iPad]       │
│  Side-scrolling carousel on mobile,  │
│  a tasteful row on desktop.          │
│  No labels, no captions.             │
└──────────────────────────────────────┘
   ──── scroll line ────
┌──────────────────────────────────────┐
│  Built by Amrith in 2026.            │
│  shio.sh · github                    │
│  [sun/moon toggle]                   │
└──────────────────────────────────────┘
```

Screenshots are not available yet — leave **labeled placeholder boxes** with the exact dimensions and notes about what each will eventually show. Ship without them; we'll drop them in when the app is shippable.

---

## Voice (from `brand.md`)

- Plain, calm, never clever.
- No exclamation marks. No emoji.
- "your" / "you" — direct address.
- Translate technical concepts only when necessary; the audience is technical.

Lines that are explicitly OK to use verbatim:
- `Your Mac, in your pocket.` *(primary positioning)*
- `A clean, minimal SSH client for iPhone and iPad.`
- `Tailscale-native.` *(single word/phrase, used as a tag)*

Lines that are explicitly **not** OK:
- Anything with "magical", "seamless", "revolutionary", "AI-powered."
- "The future of SSH on iOS."
- "Power your workflow."
- "🎉" or any equivalent enthusiasm marker.

---

## Visual direction

The icon **is** the brand — make sure it dominates the hero. The locked icon master is at `assets/icon/master.svg` in the Shio repo. Copy it into the landing page repo's `public/` or `assets/`.

Use the design tokens from `design-tokens.md`:
- Dark mode default: `chrome.background` = `ink.800` (`#0E0E10`); text = `#F2F2F4`.
- Light mode: `chrome.background.light` = `salt.bone.diluted` (`#F4EEDF`); text = `ink.800` (`#0E0E10`).
- `salt.bone` (`#E8DCC4`) — reserved for accents on this surface (e.g., the hero block behind the icon could pick up the full bone).
- Type: SF Pro Display for the hero, SF Pro for everything else, SF Mono nowhere on the landing.
- Spacing: respect the 4-point grid from `design-tokens.md`.

The wordmark below the icon should be set in **DotGothic16** (Google Fonts) — same font as the icon — and sized to match the visual weight of the icon above it. This is the one place we use DotGothic16 on the page; everything else is SF Pro.

**Theme toggle**: a small sun/moon button in the footer. Persists to localStorage. Default to system preference. Same pattern as `pasture.sh` — feel free to crib that pattern.

**No animations** except:
- A quiet fade-in on initial load (~200ms).
- The theme toggle's icon swap.
- The screenshot carousel auto-scroll (very slow) or pause-on-hover.

No parallax. No scroll-tied effects. No springy buttons. The aesthetic is "considered, calm" — not "playful."

---

## Tech stack recommendation

**Astro** or **plain static HTML + CSS + a small JS file**.

- For a one-page site with a few interactive elements (theme toggle, optional carousel), plain HTML/CSS/JS is enough and ships fastest. `pasture-sh.github.io` precedent.
- Astro is also fine if the developer wants component reuse (e.g., re-use the screenshot frame) or to bake in image optimization. It deploys cleanly to Cloudflare Pages with zero config.
- **Do not use** Next.js, SvelteKit, Remix, Nuxt — overkill for one page.

Either way, the build output must be static — Cloudflare Pages will serve it from the edge.

**Fonts**:
- SF Pro / SF Pro Display: use Apple's web fonts via the `apple-system` CSS stack — no download. (For tighter Apple-typography fidelity, optionally self-host the SF Pro family from Apple's developer downloads under license, but the system stack is fine for v1.)
- DotGothic16: Google Fonts `display=swap`, subset to the characters we need (`shio` + `塩` plus a small Latin fallback).

**SEO basics** (don't over-engineer):
- `<title>` = `shio — your Mac, in your pocket.`
- Meta description = `A clean, minimal SSH client for iPhone and iPad. Tailscale-native.`
- Open Graph: title same as above, description same, OG image = a 1200×630 export of the icon centered on the bone background.
- Favicon = the 32px and 16px PNG exports of the icon already in `assets/icon/`.
- `robots.txt` allow all. Sitemap optional for a single-page site.

**Analytics**: skip for v1. If we ever need them, use Cloudflare Web Analytics — privacy-respecting, no consent banner needed.

---

## Open considerations (for the new session to decide)

- **Should the page show the build status?** E.g., "Currently in private beta. Public TestFlight estimated [month]." Pro: builds anticipation. Con: dates slip. *Recommendation: leave it out unless you have a firm date.*
- **Footer credits**: should it link the user's personal site (`amrith.co`) and the company/project page if any? *Recommendation: just "Built by Amrith." — clickable to amrith.co. Nothing else.*
- **License/legal**: do we need a privacy policy on the landing? *Recommendation: no — we collect nothing. We will need one before App Store submission, but that lives in the app's listing, not the landing.*
- **Press kit / brand assets**: a `/press` page with the icon master and a one-paragraph description? *Recommendation: not for v1 — add when someone asks.*

---

## What the new Claude session should do

1. **Read first**:
   - `brand.md` (voice, positioning, anti-references)
   - `design-tokens.md` (colors, type, spacing)
   - `app-icon-concepts.md` (the locked icon decision and constraints)
   - This brief.

2. **Set up the repo** at `github.com/shio-sh/landing` (or whatever name the user picks — confirm before creating). Wire to Cloudflare Pages. Custom domain `shio.sh`.

3. **Build the page** per the structure above. Lean on `pasture-sh.github.io` for the sun/moon toggle pattern if useful — same indie maker, similar aesthetic neighborhood.

4. **Ship a draft** the user can review on a Cloudflare Pages preview URL before pointing `shio.sh` at it.

5. **Update memory**: add an entry to `~/.claude/projects/-Users-amrith/memory/MEMORY.md` for the landing page repo when it's set up.

---

## What this brief deliberately does NOT include

- Screenshots — the app isn't ready.
- Demo video / preview video — premature.
- An interactive demo of the terminal — too much work, off-brand for v1.
- A blog / changelog page — the GitHub releases page IS the changelog.
- Pricing — undecided, and announcing pre-launch pricing is bad form.
- A "compare to competitors" table — Shio's positioning doesn't need to punch at Termius or Blink. Quiet confidence.

If the next session is tempted to add any of these "for completeness," resist.
