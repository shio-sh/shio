# Shio — State of the Union

> Handoff context for a fresh agent picking up the build. Written 2026‑06‑12 after a long build session that took the app from a working terminal to a feature‑complete command center. Repo: `github.com/shio-sh/shio` (branch `main`). Two Apple targets — `Shio` (iOS/iPad), `ShioMac` (macOS) — sharing a platform‑agnostic Swift core.
>
> **Continue this work in a session running on a Mac with Xcode.** This is an Xcode/iOS/macOS project — the build + verify loop (`xcodegen`, `xcodebuild`, on‑device runs) requires macOS and cannot run on Linux. Editing/reasoning could happen anywhere, but every change must be compiled on a Mac (both targets green) before it counts as done.

---

## 1. What Shio is

**A sovereign, cross‑machine command center for the AI agents running on your own machines, reachable from any of your devices.** A real terminal (libghostty) underneath, vendor‑neutral SSH, no relay server, no cloud middleman.

**Positioning:** "a real terminal for the agent era." The hero use‑case is *supervising coding agents* (Claude Code, Codex, Cursor, …) on your machines from your phone — see what needs you, approve/deny from the lock screen, keep the same project followed across every machine you own.

**Differentiator** (vs Cursor = their cloud, Conductor = one Mac, Omnara = SaaS relay): the *same project* followed across *your* machines, supervised over *your* network, **no relay**, vendor‑neutral, with a real terminal. The moat is being the head, not the harness — Shio uniquely sits at (which project × which machine × which agent × IS the terminal).

**Product shape:** mobile command deck (iPhone hero, iPad ≈ Mac later) + a Mac companion. Projects → Repos → Sessions. Lead with freedom / IRL / sovereignty as a *feeling*, never self‑claimed "premium."

---

## 2. Surfaces & information architecture

- **iPhone — supervision‑first.** Tab bar = sections (Projects / Machines / Files). The Projects tab root is a calm command‑center list where "needs‑you" floats to the top; tap a project → its **dashboard**, reordered for mobile (glance → needs‑you/agents → repos → grounding modules as tap‑in rows). Away‑push deep‑links here.
- **Mac — master/detail.** A collapsible sections sidebar | a slim **projects rail** (switch + glance who‑needs‑you) | the **project dashboard** as the always‑present canvas (no click‑through). Native AppKit/SwiftUI hosting libghostty (NOT Catalyst).
- **iPad** — currently runs the iPhone layout; a proper master/detail (≈ Mac) is deferred ("iPad later").

The **project dashboard is the source of truth** that the agents also pull from (one source, two consumers: the human dashboard + agent grounding). Modules: **Repos** (git/PRs/tests), **Agents** (supervision), **Skills**, **Memory & context**, **Integrations** — each conceptually a provider so they fill in incrementally.

---

## 3. Architecture & stack

- **App / UI → Swift / SwiftUI.** The magic is Apple‑native: CloudKit sync, Live Activities, widgets, Metal, Handoff, Secure Enclave.
- **Terminal core → libghostty (Zig).** Two forks, both justified, current, and auto‑watched:
  - `shio-sh/ghostty` — 1 patch: an External‑IO backend + a C ABI + iOS embedding (so we can drive ghostty's renderer with bytes from our SSH layer instead of a local PTY).
  - `shio-sh/libxev` — 1 patch: iOS kqueue. **Pinned to ghostty's own libxev pin, not libxev main.**
  - `GhosttyKit.xcframework` is a **prebuilt static library** (`scripts/refresh-ghostty.sh --fetch`); the heavy `*.a` slices are **gitignored** (≈771 MB) — only small headers are tracked. A fresh clone must run the refresh script (or fetch a prebuilt) before building.
  - `.github/workflows/fork-watch.yml` weekly audits both forks via `git cherry` patch‑identity (→ "drop‑the‑fork" issue when upstream absorbs a patch) + a dry rebase (drift). `update-ghostty.yml` does the heavy bump+PR.
- **SSH → all‑Swift on SwiftNIO‑SSH (`apple/swift-nio-ssh`).** No Rust, no Citadel, no russh. **Modern algorithms only** (no RSA / deprecated = a deliberate security feature). This was deeply litigated and resolved all‑Swift; do not relitigate.
- **Persistence → SwiftData + CloudKit** (private database), one shared container.
- **Project generation → XcodeGen.** `project.yml` is the source of truth; run `xcodegen generate` after adding files. Never hand‑edit the `.xcodeproj`.

---

## 4. Data model (`Shio/Core/Profiles/`)

Three‑level, project‑first, multi‑repo:

```
Project (an org/workspace; can span several repos — e.g. Shio = app + landing + worker)
  └─ Repo (identity: cloneURL / identityKey)
       └─ ProjectCheckout (a repo on a specific machine: host + path)
```

- Helpers: `project.activeRepo` / `activeCheckout` / `allCheckouts` / `effectiveCloneURL`, `Project.create(...)`, `project.addRepo(...)`, `repo.activeCheckout`. **`activeCheckout` = the most‑recently‑opened** (so the machine‑switcher just stamps `lastOpenedAt`).
- **CloudKit‑valid by construction:** every attribute optional/defaulted; relationships optional with **explicit inverses** on the parent and `.nullify` delete rules. (A missing inverse silently drops the whole store to local‑only — this bit us once with `Skill.project`; the lesson is baked in.)
- Additive migration: `ProjectMigration.run()` (backfillCheckouts → backfillRepos → reconcile), idempotent, safe every launch. **Not yet baked on a real 2‑device iCloud account** — that verification is a remaining gate.
- Models registered in `ShioModelContainer` (in `HostStore.swift`): `Host, Project, ProjectCheckout, Repo, Skill`.

---

## 5. Major subsystems

### Status engine (`Shio/Core/Status/`)
Cache‑first git status across every visible checkout. `GitStatusReader` runs `git status --porcelain=v2 --branch -z` — one batched script per host over `SSHClient.exec` (remote) or `Process` (local Mac). `GitStatus.parse(...)` (porcelain‑v2, 19 unit tests). `ProjectStatusStore` (@Observable): cache‑first, capped fan‑out, App‑Group **disk cache** so the dashboard paints instantly on cold launch *before any SSH*, **warm‑host gating** (`targets(...warmOnly:)`), a 20s visible‑only refresh timer, `isStale()`. **PRs** via `GitHubReader` — runs the machine's own `gh pr list --json` over the same exec layer (no in‑app GitHub auth; rides the machine's `gh` like it rides `git`). **Git writes** via `GitWriter` (stage/commit/push) with a command‑preview sheet (`CommitSheet`), shell‑quoting verified injection‑safe.

### Agent supervision (`Shio/Core/Agents/`, `ShioMac/MacProjectAgentMonitor.swift`)
`AgentDetector` classifies a terminal pane tail into `running` / `waiting` / `finished` and the agent name (Claude Code / Codex / …). **Bias: a false "waiting" is worse than a missed one** — `waiting` requires a recognizable confirmation prompt (`(y/n)`, "do you want to proceed", Claude's `❯ 1. yes / 2. no` menu, etc.). On Mac, `MacProjectAgentMonitor` polls `tmux capture-pane` of `shio-*` sessions every 4s. Remote agents are detected by folding a base64 pane capture into the same per‑host status SSH round trip (`GitStatusReader.probeRemoteWithAgents`) → `ProjectStatusStore.remoteAgent(host:repoName:)`. So an agent on a machine you aren't viewing still surfaces.

### Skills — the grounding layer (`Shio/Core/Skills/`, `Shio/Features/Skills/`)
**Key insight (from studying chops.md):** there is no injection/MCP — a skill *is* a `SKILL.md` (markdown + YAML frontmatter `name`+`description`, where the description is what an agent uses to decide *when* to load it) that lives in a directory the agent reads natively (`~/.claude/skills/<name>/SKILL.md`, `~/.cursor/skills`, `~/.codex/skills`, vendor‑neutral canonical `~/.agents/skills`). Shio's edge over a local‑only tool: it writes those files on **every machine + project** the agent runs on.
- `Skill` is a CloudKit‑synced `@Model` (name, `skillDescription`, content, enabled, optional `project` → nil=global, set=project‑scoped). The library is in Settings (`SkillsLibraryView`, shared both platforms) with full CRUD.
- `SkillMaterializer` writes/removes the files — **local** (FileManager) and **remote** (one SSH round trip, base64'd). `enabled` ⇔ file present. **Vendor‑neutral v2:** the canonical copy lives in `~/.agents/skills` and each *installed* tool's dir is **symlinked** to it (guarded so it never clobbers a real user dir). **Bidirectional v3:** `SkillImporter` scans existing agent dirs (local + remote over SSH) and pulls them *into* Shio, deduped — so edit a skill on your phone and it lands on every box.
- **macOS "data from other apps" prompt:** writing into `~/.claude` etc. is cross‑app access, which macOS Sequoia gates. There's a one‑time in‑app explainer before the first write + a **kill switch** (`SkillMaterializer.syncEnabled`, Settings → Skills). The system prompt text itself is not developer‑customizable.

### Remote control & away‑push (`ShioMac/`, `Shio/Core/Push/`, `Shio/Core/SSH/TmuxResume.swift`)
- **Mirror is the default** (tmux native: any device attaching `shio-<name>` shares the live session, `window-size latest`). **Takeover** is opt‑in (`detach-client -a`), an App‑Group setting with a Settings toggle. tmux lag fixed via `escape-time 0` + `status off`.
- **Away‑signal (the sovereign push):** `CloudKitSignalService` — the Mac writes a `Signal` record to the user's own private iCloud when a local agent blocks; the iPhone's `CKQuerySubscription` turns that into a Shio‑branded alert (no server, no terminal content on the wire — only a host/session id for routing). `MacProjectAgentMonitor.fireAwaySignals` fires on the not‑waiting→waiting edge, once per block.
- **RC3 — always‑on menu‑bar watcher** (`ShioMac/MacAppDelegate.swift`, opt‑in): keeps the monitor (and the away‑signal) alive after the Mac window closes.
- **Lock‑screen approve (#33):** the reverse channel. The phone writes an `Action` record (`sessionId`, `key`); the Mac polls `fetchAndClearActions()` (only while an agent is waiting) and runs `tmux send-keys -t <session> <key> Enter` (verified end‑to‑end). The lock‑screen entry point is **notification actions** (Approve/Deny on the away‑push via `UNNotificationCategory`; chosen over a Live Activity for v1 — simpler, robust, reuses the Signal push). There's also in‑app Approve/Deny on the iOS needs‑you card. The `Action` record type is deployed to CloudKit Production; the query filters on the queryable `sessionId` field (so no `recordName` index edit is needed).

### SSH keys & Secure Enclave (`Shio/Core/Keys/`, `Shio/Core/SSH/`)
- Default key: an **Ed25519** Shio key in the keychain (`KeyManager`), public half pasted into a machine's `authorized_keys` (`OpenSSHFormatter`, `PublicKeyView`).
- Passphrase‑protected `~/.ssh` keys decrypt **in‑app** (a `bcrypt_pbkdf` port — NIOSSH has no agent hook).
- **#36 — opt‑in Secure Enclave key:** a non‑extractable P‑256 key generated *in* the Enclave, used via `NIOSSHPrivateKey(secureEnclaveP256Key:)`. Additive (Ed25519 stays the default; the Enclave key is offered first with Ed25519 as fallback). The `ecdsa-sha2-nistp256` public‑key wire format is **verified by `ssh-keygen`**. Settings toggle is hidden on the Simulator (no SE there) — needs on‑device verification.
- The Mac uses the system `~/.ssh` keys first (then the Shio key); iOS uses its own key (+ password bootstrap). RSA and an iOS "auto‑install key" flow are still pending.

---

## 6. What's built — phase by phase

The whole "command‑center" roadmap is **code‑complete**. Each phase shipped to `main`, both targets building green:

| Phase | Status | Notes |
|---|---|---|
| **P0** Shared component kit (`ShioKit` on `ShioTheme`) | ✅ | terminal‑refined primitives; light/dark + ink↔salt accent flip |
| **P1** Projects rebuilt (Mac master/detail + iOS supervision‑first) | ✅ | repos+git live; agents live; modules designed |
| **P2** Machines / Files / Settings in the new language | ✅ | the "app looks whole" checkpoint; universal Skills library lives in Settings |
| **P3** Status economy | ✅ | App‑Group disk cache (instant cold‑launch), warm‑host gating, visible‑tab timer |
| **P4** Agent supervision live | ✅ | per‑repo/project; remote agent detection folded into the status fetch |
| **P5** Skills | ✅ | backend + **full grounding arc** (materialize → vendor‑neutral fan‑out → cross‑machine import) + **PRs via `gh`** + memory/notes |
| **P6** Remote control | ✅ | mirror/takeover + away‑signal + menu‑bar watcher + **lock‑screen approve** |
| **P7** Module depth | ✅ | **git‑writes** + **machine‑switcher** (saved‑commands deferred to the design pass) |
| **P8** SSH hardening (Secure Enclave key) | ✅ (code) | needs on‑device verification |

Design language is **LOCKED** ("terminal‑refined" on the real shio.sh tokens — bone `#F4EEDF` light canvas / ink‑800 dark, accent flips ink↔salt, status deepened in light). Mockups for reference live at `~/shio-*.html` on the author's Mac (not in the repo).

---

## 7. What's left

**Code‑complete, but these genuinely need a human / device / Apple account:**

1. **A full on‑device test pass** (iPhone + Mac, same iCloud). The app has grown enormously and most flows have only been compile‑verified + unit‑/standalone‑verified, not device‑run end‑to‑end.
2. **Away‑push is being debugged right now (see §8).**
3. **P8 distribution (Apple‑account work):** iOS → **TestFlight**; Mac → **notarized Developer‑ID DMG** (direct download). **The Mac App Store is impossible for Shio — it's a real terminal that forks/execs a shell, and the entitlements intentionally disable the sandbox (like Ghostty/iTerm/Warp).** Do not propose MAS.
4. **#40 — full design‑consistency pass.** The hero surfaces (Projects/Machines/Files/Settings) are on `ShioTheme`; the mechanical iOS migration of the supporting cast (Onboarding, Pairing, sheets, Terminal chrome, …) was done, but a *visual* light/dark verification on every surface + retiring the remaining `LegacyButton` call sites + the Mac system‑color files remains. The author wants this done **collaboratively, with his own design ideas, after features.** Don't grind design solo.
5. **Saved‑commands** (a P7 module) is deferred into that design pass (it's a dashboard module + needs a small schema add).
6. **Bake the SwiftData→CloudKit migration on a real 2‑device account** before relying on it.
7. **Landing page** positioning rewrite (see §11).

---

## 8. Away‑push: VERIFIED WORKING on device (2026‑06‑12)

Both tests pass on real hardware: the iOS test button (server‑side subscription check + local rehearsal banner) and the **Mac → iPhone push** (Mac Settings → Remote control → "Send test push to your iPhone" — the exact Signal a blocked agent writes). The temporary diagnostics have been removed.

**The hard‑won lesson, for posterity:** the original one‑device test was unfalsifiable — **CloudKit never delivers a subscription push to the device that wrote the record** (documented Apple behavior). The phone wrote the Signal and waited for its own push; the console showed "0 pushes" because CloudKit never attempted one. The earlier fixes were real (the permission prompt genuinely never fired; APNs registration was skipped on `notDetermined`; the subscription latch wasn't environment‑scoped) but could never make *that* test pass. Any future push test must be **cross‑device**.

Still worth one live pass: the full y/n loop with a real agent (agent blocks in a `shio-*` tmux session → push → lock‑screen Approve → keystroke lands). Mac‑side injection was verified pre‑handoff; delivery is now verified; the composed loop just hasn't been watched end‑to‑end in one sitting.

**Environment note for all CloudKit testing:** a **Debug build talks to CloudKit *Development* + sandbox APNs**; Release/TestFlight talk to *Production*. The schema (`CD_Host/Project/Repo/ProjectCheckout/Skill`, `Signal`, `Action`) is deployed to **both**. When inspecting subscriptions/records during dev, look at **Development**.

---

## 9. Repo layout & how to build

```
Shio/                  iOS/iPad app + the shared core (compiled into ShioMac too)
  Core/Design/         ShioTheme, ShioKit (component kit), CommitSheet, color helpers
  Core/Profiles/       SwiftData models + ShioModelContainer + migration
  Core/Status/         git status + PRs + git writes engine
  Core/Agents/         AgentDetector / AgentStateStore
  Core/Skills/         SkillMaterializer + SkillImporter
  Core/SSH/            SSHClient (NIOSSH), TmuxResume, SystemSSHKeys, SFTP
  Core/Keys/           KeyManager (incl. Secure Enclave), OpenSSHFormatter
  Core/Push/           CloudKitSignalService, PushService
  Features/            Projects, Machines/Hosts, Files, Settings, Skills, Terminal, Keys, …
ShioMac/               the macOS app (MacShell, MacProjectsView, MacMachinesView, MacAppDelegate, …)
ShioWidgets/ ShioLiveActivities/   extensions (App‑Group only; no push entitlement — correct)
Frameworks/GhosttyKit.xcframework  prebuilt libghostty (the .a slices are gitignored)
project.yml            XcodeGen source of truth
scripts/refresh-ghostty.sh         fetch/build GhosttyKit
.github/workflows/     fork-watch, update-ghostty
```

**Build:**
```bash
xcodegen generate                 # after any file add/remove
xcodebuild -scheme ShioMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme Shio   -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Headless/CI/agent builds that can't auto‑provision should pass `CODE_SIGNING_ALLOWED=NO`. A fresh clone needs `GhosttyKit.xcframework` populated first (run `scripts/refresh-ghostty.sh --fetch`).

**Conventions:** match surrounding code style; XcodeGen owns the project; the project enforces Swift 6 strict concurrency + the `ExistentialAny` upcoming feature (write `any Error`, `(any NSObjectProtocol)?`, etc.); design tokens come from `ShioTheme` (never raw hex in new feature code). Commits in this repo end with a `Co-Authored-By: Claude …` trailer.

---

## 10. Constraints & gotchas

- **No Mac App Store** (terminal; unsandboxed). Mac ships as a notarized Developer‑ID DMG.
- **CloudKit Dev vs Prod**: Debug = Development, Release = Production. Raw record types (`Signal`, `Action`) only appear in the schema after a record is *written* (unlike SwiftData `CD_*` types). Query subscriptions/queries need a queryable field (we query `Action` by `sessionId`, not `recordName`).
- **Secrets are gitignored and must stay that way:** `fastlane/.env` (ASC API key id `GSLA8X34NJ`, issuer …), the `.p8` AuthKey, the Turnstile secret for the landing/beta worker. Never print or commit their *values*.
- **Secure Enclave + Live Activities + push** can't be exercised in the Simulator — real device only.
- **Apple‑dashboard work is batched and done by the author himself.** Surface a checklist; don't try to automate his account.
- Team `VRNNS4H6XH`; bundle ids `sh.shio.app` (iOS), `sh.shio.app.mac`, `sh.shio.app.widgets`, `sh.shio.app.liveactivities`; CloudKit container `iCloud.sh.shio.app`; App Group `group.sh.shio.app`.

---

## 11. The landing page (separate repo)

`shio.sh` is a **separate repository** (`~/shio.sh` on the author's Mac), deployed to **Cloudflare Pages** as project `shio`. It carries the **beta‑signup flow** (pasture‑style): the site collects an email → a local Cloudflare worker (`~/shio-beta-worker`) → App Store Connect `betaTesters` → the "beta" group. Gated on the author's screenshots → beta review. A **positioning rewrite** (to the "real terminal for the agent era" / agent‑supervision framing) is still pending. It is **not in this repo** — Fable would need it cloned separately to touch it.

---

## 12. Roadmap pointers / philosophy

- The authoritative build brief lived at `~/.claude/plans/humming-meandering-haven.md` (author's machine). This doc supersedes it for handoff.
- Build philosophy: head‑not‑harness; sovereignty as a *feeling*, shown not told; restraint over AI‑slop; the agent era is the wedge but vendor‑neutral SSH + a real terminal is the moat.
- Everything optional/grounding (Skills, the eventual `shio` CLI, a per‑project MCP) is **opt‑in rails** — Shio works fully without them; power users BYO model/keys.

— End of state of the union. Next concrete action: finish verifying away‑push on device (§8), then the on‑device pass + the Apple distribution batch.
