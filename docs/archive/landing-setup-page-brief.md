# Brief for shio.sh/setup — pure instructions, no shell script

## Context

The previous `/setup` page on `shio.sh` was built around a `curl -fsSL https://shio.sh/setup.sh | bash` one-liner with an embedded script preview and a "read it first" path. After review, that whole shape was rejected — even with the polish, the artifact category (`curl | bash`) signals "sketchy" to a meaningful fraction of users no matter how well it's framed. The trust cost outweighed the convenience.

The new `/setup` page is **purely instructional**. There is no script. There is no `setup.sh` URL. There is no executable artifact served from `shio.sh`.

The full content this page mirrors lives in the Shio repo at `/Users/amrith/Shio/docs/setup.md`. Treat that as the source of truth — same prose, same tone, same step structure. The page is the visual rendering of that doc within our design system.

## What to remove

- The big `curl | bash` code block at the top.
- The "Read it first (recommended)" three-line section.
- The "Inline script preview" — there is no script anymore.
- The "With public key (optional sub-section)" variant of the curl command.
- The `_headers` rule for `/setup.sh` (delete the rule; the URL goes away).
- The `setup.sh` file itself in `public/` of the landing repo.
- The sync script that copied `mac-setup.sh` from the Shio repo.

The Shio repo no longer ships `scripts/mac-setup.sh` either. It's deleted upstream.

## What the new page is

A beautiful, calm, one-scroll instructional page. Four numbered steps, each a card. No executable shortcuts. The voice continues from the home page — plain, never clever, no exclamation marks, no emoji.

## Page structure

### Hero

Same H1 treatment as the home page: **Set up your Mac**. One-line subhead: *Four short steps. About a minute. Shio asks you to install nothing of our own on your Mac.*

### A short preamble

Two or three sentences. Pull from `docs/setup.md`'s opening:

> Shio is the iPhone app. Your Mac doesn't need Shio installed — it just needs to be reachable on Tailscale and willing to accept SSH connections from your iPhone.
>
> Every step below uses an existing trusted tool: Tailscale's signed installer, Apple's System Settings, your Mac's Terminal, and (optionally) Homebrew. Shio asks you to install nothing of our own on your Mac.

### The four steps

Each step is a card with: a numeric marker, a short title, a 1–3 paragraph body, and (where relevant) a code block for a copy-pasteable command. Cards stack vertically on mobile, stack with generous spacing on desktop (don't try to grid them — readability over compactness).

The full prose for each step lives in `docs/setup.md` — render it verbatim or near-verbatim. Don't paraphrase loosely; the wording was chosen carefully.

**1. Install Tailscale on your Mac**
- Body: explain the same-account-on-both-devices point. Single big button (or link styled as a button) that points at `https://tailscale.com/download`.
- No code block.

**2. Enable Remote Login**
- Body: the System Settings path and *why* (so the user understands what Remote Login is, not just where to find it).
- No code block.

**3. Install Shio's public key**
- Body: "In Shio on your iPhone: Settings → SSH Key → Copy install command. Paste it into Terminal on your Mac."
- Optionally a small illustration of where the button is in Shio (skip if no asset).
- The code-block here is *placeholder*: a one-line `echo ... >> ~/.ssh/authorized_keys` example, dimmed, with a note "Shio shows you the real command with your actual public key — copy it from there, not from here."

**4. (Optional) Install tmux**
- Body: explain what it gives them (session persistence) and that it's optional. Mention the nice quirk: they can `brew install tmux` from inside Shio's first SSH session.
- Code block: `brew install tmux`

### Closing

A short note that wraps it:

> Back on your iPhone, in Shio: add your Mac and tap to connect. If anything doesn't work, Shio's built-in **Diagnose** (Settings → Diagnose, or the Diagnose button on a disconnect overlay) tells you exactly which step is incomplete and what to do next.

### Future-state note

A small section at the very bottom, visually de-emphasized:

> **A one-command install someday.** We're working toward shipping `shio` as a CLI helper in [Homebrew's official formulas](https://formulae.brew.sh) so the steps above collapse into:
>
>     brew install shio
>
> That requires earning Homebrew's notability threshold first, which we'll do once Shio is shipping with real users. Until then, the guide above is the path — and honestly, it's not bad.

### Footer

Same footer as the home page.

## Design system

Same tokens as everywhere else on the landing:
- Background: `salt.bone.diluted` in light, `ink.800` in dark
- Text: `ink.800` on light, `#F2F2F4` on dark
- Code blocks: `ink.700` on dark, `ink.50` with subtle border on light, SF Mono content
- The wordmark anywhere it appears: Departure Mono
- The 塩 anywhere it appears: DotGothic16
- Everything else: SF Pro / system font stack

No emoji. No exclamation marks. No "🎉 Easy!"-style energy. Calm, considered, instructive.

## Copy/edit pass

Once you've drafted the page, do a final pass against these voice rules:

- Direct address ("On your Mac, open..."), not impersonal ("Users should...").
- No marketing-coded verbs (revolutionary, seamless, magical, AI-powered).
- No "Pro tip:" / "Heads up:" / "Note:" preambles — just say the thing.
- Code blocks have one command per block; no trailing semicolons of unrelated commands chained together.

## SEO

- `<title>`: "Mac setup — Shio"
- Meta description: "Set up your Mac for Shio in four short steps. About a minute. Shio asks you to install nothing of our own on your Mac."
- OG image: same as the home page is fine.

## Definition of done

- `/setup` renders the four-step guide cleanly in light and dark, theme toggle works.
- `/setup.sh` returns 404 (deleted).
- All copy is verbatim or near-verbatim from `/Users/amrith/Shio/docs/setup.md`.
- The page passes a 30-second skim test: a non-developer can read the steps, find the right buttons in their Mac's System Settings, and connect successfully.
- No `curl | bash` anywhere.
- No "EXECUTE THIS!" CTA anywhere.
