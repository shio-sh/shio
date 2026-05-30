# Shio — product north star

Internal reference. The "what and why" we build against. For brand voice see the
manifesto on the site; for public copy see shio.sh. Decisions here were made with
Amrith on 2026-05-30.

## What Shio is

Shio is the terminal for the agent era that lives in your pocket. One place to run
and watch the coding agents working across every machine you own, from your phone,
so you can leave the desk while the work keeps moving.

We are the **head, not the harness**. We do not run the agents and we do not run a
cloud. The agents run where they already run, on your hardware. Shio is how you
reach, watch, and steer them from anywhere.

## Who it is for

People running coding agents hard on machines they own (the agent-maxxer), who do
not want to be chained to a desk to keep that work moving. Secondary: anyone who
wants their machines and the work on them reachable from a phone.

## The moat

1. **Universal.** Any agent (Claude Code, Codex, local models, anything), any
   machine (Mac, Linux server, Hetzner box, a Pi), wherever it runs. The
   first-party apps (Claude, Codex) are each locked to one agent and one cloud.
   We are the universal one.
2. **Sovereign.** Your machines, your keys, no account, no Shio cloud. Nothing of
   yours runs on or routes through our infrastructure.
3. **Mobile-first.** Everyone is building terminals for agents at the desk (cmux,
   Warp). Almost no one is building for the moment you step away. That is our
   front door.

These compound. A better, mobile, vendor-neutral mousetrap is something neither the
desktop terminals nor the single-vendor apps can be.

## What we are building (v1, the full universal cut)

Three parts, one product, all shipping in v1.

1. **Shio (iPhone + iPad)** — the hero. Opens to your **projects**: the repos you
   chose to expose, not every repo. Each project holds **sessions**: persistent,
   tmux-backed terminals, some running agents. You get a notification and a Live
   Activity when an agent needs you or finishes. Tap in to watch the live terminal,
   unblock, steer, or take the wheel. Branch and PR status shown per project.
2. **The Shio helper** — a small, open-source, cross-platform program that runs on
   any host you own (Mac, Linux, Pi). It lets you pick which repos to expose,
   brokers the connection (direct, Tailscale fallback), and is the always-awake
   watcher that detects a blocked or finished agent and pushes to your phone.
   **Shio for Mac is the polished app wrapper of this helper.**
3. **Continuity** — the same sessions, live on your phone and waiting at your desk.

### The detection bet (hybrid)

The universal baseline is **watching the agent's terminal output** to recognize when
it is waiting: approval prompts, questions, idle. This works with any agent on any
host, no integration required, and is the moat. On top, **per-agent hooks** for the
big agents (Claude Code, Codex) give precise, reliable state where they exist.
Output-watching keeps us universal; hooks make the common cases bulletproof.

### Where work runs

On your machines, never ours. The phone reaches live sessions over SSH (direct, or
Tailscale when direct cannot). The helper owns the away-case: it is the thing awake
on the host that notices and pushes when the app is not connected. APNs (Apple's
push) is the only thing in the middle, and it carries a notification, not your work.

## The foundation (already built in the iOS app)

v1 reshapes and extends what exists rather than starting over: libghostty + Metal
terminal (External IO backend), multi-session via SessionStore, SwiftNIO SSH client,
tmux session resume, Live Activities and Dynamic Island, SwiftData host profiles,
FaceID app lock, widgets, Handoff. The main new work: hosts become **projects**, a
cross-platform **helper**, **agent-awareness and detection**, and the **supervision
flows** (notify, glance, take over).

## Principles, and what we deliberately do NOT build

- **Head, not harness.** Never our own coding agent. We run whatever you run.
- **No cloud of ours.** We never execute or store your code.
- **Light orchestration.** Projects, sessions, agent-state, notifications,
  take-over, continuity. That is the surface. No workflow engine, no worktree
  manager, no GitHub-sync service of our own. ("It's a terminal emulator, bro" is
  the guardrail.)
- **Embody universality, do not name competitors.** Be conspicuously universal; let
  the contrast speak.
- **Beauty is the bar.** Native, fast, restrained. The craft is the differentiator a
  serious developer feels.

## Openness and model

**Fully open and free** — the helper, the apps, all of it. We play for reach, trust,
and reputation. The outcome (sponsorship, acqui-hire, or simply being the best tool
in the category) comes later. No account, no telemetry, no paywall in the way. Long
game.

## Positioning

- Lead **universal-first**: one place for every agent on every machine you own.
- The payoff is **freedom**: leave the desk, the work keeps moving, so can you.
- Built **for the phone first**, because that is the open flank.
- Embody it; never name names.

## The field (where we stand)

- **cmux** — desktop Mac terminal on libghostty, agent supervision, ~20k stars, no
  mobile (iOS is a paid promise). Closest analog; owns the desk; will ship iOS
  eventually, so the mobile clock is real.
- **pi** — the minimal harness (the thing that runs the agent). A different layer.
  We are not a harness; we run pi too.
- **Claude / Codex mobile** — "away from the desk" for their own agent only.
  Single-vendor, their cloud. Our universality is what they cannot be.
- **Omnara / Happy / Conductor** — agent remote-controls or desktop orchestrators,
  mostly behind a relay or cloud. We are the sovereign, real-terminal, mobile-first
  one.

## Known hard parts (resolve in the build plan)

- One helper that installs cleanly on Mac, Linux, and a Pi, and pairs securely with
  your phone.
- Reliable away-push when iOS has backgrounded or killed the app (helper + APNs is
  the answer; the watcher must be dependable).
- Output-watching detection that is good enough across agents and locales without
  false pings; hooks to harden the big ones.
- Reaching arbitrary hosts from anywhere (the direct / Tailscale path is the hard 5
  to 15 percent).
