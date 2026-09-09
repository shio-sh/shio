# Shio Pre-Beta Review

> Generated 2026-06-10 by a 35-agent multi-agent review (Fable 5).
> Findings: 50 total — 19 objective verified, 7 refuted, 23 subjective.
> Method: isolated cold read of live shio.sh → parallel finders (positioning + live competitor research + 3 security surfaces + code/coherence) → adversarial refutation of objective findings only → synthesis.
>
> **Corrections (post-triage with Opus, 2026-06-10):** Two §1 claims were wrong and are struck through inline below.
> (a) "Projects-first doesn't exist in the product" is **false** — it ships (`Shio/Features/Projects/ProjectsView.swift:7`, `ShioMac/MacShell.swift:82,101` `ProjectsPane`, `ShioMac/ShioMacApp.swift:245` `open(project:)`, `case projects` tab). The error came from trusting the README/ROADMAP that §5 itself flags as stale — a methodological miss. Real fix: update docs + surface the wedge, not build it.
> (b) The agent-supervision stub is an **intentional v2 hold** (the first cut wasn't good enough to ship), not an oversight. Fix #3 therefore resolves via honest copy, not by rushing the feature.

You built all of this solo and it shows craft. That's exactly why this is blunt: the gap isn't quality, it's that the headline promises a product you haven't built yet, and two of the things you'd hand a beta tester are broken or non-functional. Read this in priority order.

---

## 1. Positioning — brutal

**The one differentiated thing that's real: projects-first organization + a native Mac companion. Everything else in your pitch is either vapor or table stakes.**

- **Confidence: high.** No mobile/SSH/agent terminal leads with projects→sessions as the primary model. Moshi organizes by SSH connections, Termius by hosts/tags, Onepilot by servers/agents, Blink by hosts. The only projects-style parallel-session product (Conductor) is macOS-desktop-only. That's genuine white space. **Caveat (high):** it's a UX/taste differentiator, not a technical moat — Moshi can add a "projects" grouping in one release, so this is a speed bet, not a durable one.

**~~Now the brutal part: the differentiated thing does not exist in the product.~~ — CORRECTED: it ships.**

- ~~The named wedge — "projects-first" — isn't built and isn't on the launch list. README architecture (README.md:102-129) lists Hosts/Terminal/Settings/Onboarding, no Projects. ROADMAP pre-launch must-haves (ROADMAP.md:11-17) are multi-session, reconnect, known-hosts, Live Activities, widgets — no projects model. **Confidence high.** If projects-first is the wedge, the beta doesn't test the wedge.~~
- **CORRECTION:** Projects-first **ships in both targets** — iOS `ProjectsView` (Shio/Features/Projects/ProjectsView.swift:7) behind a Projects tab (RootView.swift:42), Mac `ProjectsPane` + `case projects` tab (MacShell.swift:82,101) + `open(project:)` (ShioMacApp.swift:245). The "doesn't exist" verdict was a method error: it was derived from the README/ROADMAP that §5 of this very report flags as stale. The wedge is real and in the binary. The actual problem is narrower but still real: **the wedge is shipped yet invisible** — the landing, README, ROADMAP, and GitHub description never mention it, so a stranger can't tell it exists. The fix is *surface + document it*, not build it.

**The headline and the product are two different products.**

- Landing leads with `The terminal for the agent era` (index.html:142) and the manifesto promises `watch its agents work, step in when one needs you`. But a grep across README/ROADMAP/brand.md returns **zero** product-feature hits for agent/Claude/Codex/supervise/orchestrate. README.md:25 defines the product as `a premium iOS and iPadOS SSH client`; brand.md:3 as `Your Mac, in your pocket`. **Confidence high.** You're writing a check the binary can't cash, and the agent power users most excited by the headline are exactly the ones who notice fastest and bounce.

**Two of your stated moats aren't moats:**

- **"Vendor-neutral SSH is the moat"** — false as of mid-2026. It's the definition of every SSH client (Termius, Blink, Prompt all do it). Moshi supports "Claude Code, Codex, and other agents" with a webhook fallback; Onepilot deploys Claude Code + Codex on any SSH server and connects 23+ LLM providers. **Confidence high (med on competitor specifics).** Vendor-neutrality is real *as a counter to Anthropic's lock-in* — but only if your copy explicitly attacks the hosted-agent model. Right now `SSH into anything you own` (index.html:143) reads as a feature any competitor's listing implies.
- **Taste/craft** — real, and a genuine reason people pick Things over Reminders. But it's the *most copyable* axis (a funded competitor ships "clean mode" in a quarter) and it converts only *after* install — your landing can't make a stranger *feel* calm, and brand.md:122 bans the hero-overlay slogans competitors use to sell feeling. **Craft wins retention, not the wedge. Confidence med.**

**The honest objection a working dev makes:** "I already have Termius/Blink + tmux, and I don't supervise agents from my phone." Phone-supervision is real but occasional — a companion, not a daily driver. The one thing that would justify switching muscle-memory (push-notify when the agent stops, one-tap approve/deny from the lock screen, resume exact session) is deliberately held for v2 (ROADMAP.md:15, Live Activities "currently a shell") — **an intentional quality hold, not an oversight** (the first cut wasn't good enough to ship). **So the strategic move is: lead with the shipped wedge (projects-first), frame supervision as the stated direction — don't rush a half-baked v1.** Confidence high.

---

## 2. Security red-team

### Worker (`shio-beta-worker`) — the highest-impact surface

- **BLOCKER — open TestFlight-invite cannon.** `fetch()` at src/index.ts:129 unconditionally POSTs arbitrary emails to ASC `/v1/betaTesters` after a trivial check (src/index.ts:110: `!email.includes('@')`). No auth, no proof of email ownership, no rate limit. An attacker scripts curl to email-bomb strangers with official TestFlight invites *from your developer account*, and can exhaust Apple's 10,000 external-tester cap (~8 min at 20 adds/sec) — after which real signups fail and you manually purge thousands. **Confidence high.**
- **HIGH — Origin/CORS check is theater.** src/index.ts:91: `if (requestOrigin && requestOrigin !== origin && !requestOrigin.includes('localhost'))`. Three bypasses: curl sets `Origin` freely; **omitting Origin short-circuits the whole guard to false (allowed)**; `.includes('localhost')` passes `https://localhost.evil.com`. CORS is browser-enforced — zero protection against scripts. **Confidence high.**
- **BLOCKER — no rate limit / CAPTCHA / KV.** wrangler.toml has no KV/DO/rate-limit binding; package.json has no Turnstile dep; src/index.ts never reads `CF-Connecting-IP`. Nothing stands between the internet and Apple's API. **Confidence med.** Min fix: Turnstile + per-IP rate limit.
- **Verified-good (low):** secret handling is the *strongest* part — JWT errors return static `{error:'jwt_error'}` (src/index.ts:121-127), `.p8` never echoed, key lives only in Wrangler secret store. ES256/P-256 JWT is constructed correctly with a valid 20-min exp and `appstoreconnect-v1` aud (src/index.ts:44-63). No defect.

### SSH + pairing

- **BLOCKER — host-key verification is a no-op.** `SSHHostKeyDelegate.validateHostKey` (SSHClient.swift:380-391) succeeds for **any** key under `#if DEBUG` (full MITM, zero protection) and **fails every key** in Release (`SSHError.authenticationFailed`). Both fastlane lanes build Release (Fastfile:73,103). So your shipped TestFlight/Developer-ID artifact **connects to nothing** — every host shows "Authentication failed." **Confidence high. Flagged intentional-shaped** (comment says "Brick 7 hardens this") but it's unfinished, not an accepted risk — and it's a launch blocker either way.
- **HIGH — TOFU is cosmetic / dead code.** `Host.hostKeyFingerprint` (Host.swift:68-69) is documented as the stored TOFU fingerprint but is **never read or written** anywhere. `PairingPayload.fingerprint` (PairingPayload.swift:22-23) is parsed but never forwarded to the SSH layer. The field names imply protection that does not exist. **Confidence high.**
- **HIGH — pairing handshake is unauthenticated plaintext HTTP.** Phone POSTs its public key to `http://<host>:8730/pair` (PairingService.swift:42-45 accepts `http://`); companion binds `0.0.0.0` and gates only on a one-time token (shio-companion.py:139-151). The token rides in the QR/cleartext body — anyone who sniffs the LAN segment or shoulder-surfs/screenshots the QR can POST **their own** public key to `/pair` and get appended to `~/.ssh/authorized_keys` → persistent SSH access. **Confidence high. Flagged intentional-shaped** (README acknowledges TLS/pinning as TODO) but it ships as the live path.

### CloudKit + Mac

- **HIGH — Mac pairing listener writes attacker-controlled lines to `authorized_keys`.** `MacPairingHost` opens NWListener on TCP 8730 on **all interfaces** (MacPairingHost.swift:32,73), gated only by an in-process UUID token that is *also embedded in the on-screen QR/deep-link base64* (MacPairingHost.swift:51-53,157-163). Recover the token (shoulder-surf, screen-share, port-scan during the pairing window) → POST your key → appended to authorized_keys (MacPairingHost.swift:133-148) → permanent SSH login. Plus: `publicKey` is only trimmed/deduped (lines 141-145), not validated as a single key line, so embedded newlines could inject multiple entries or `command=`/`from=` directives. **Confidence high.** Converts transient network reach into durable account access — highest-value Mac vector.
- **MEDIUM (intentional) — unsandboxed Mac app.** ShioMac.entitlements has no `app-sandbox` key; the app reads all `~/.ssh` private keys (SSHClient.swift:143-152) and writes authorized_keys. **Flagged intentional** — a sandboxed terminal can't read system keys or spawn shells; this is the iTerm/Ghostty model. But a terminal renders untrusted remote output, so a libghostty/NIO parser bug runs with full home-dir authority. **At minimum keep hardened-runtime + library-validation on** (you already do — Fastfile:116).
- **LOW (latent) — CloudKit Signal routing payload is unauthenticated** but the `.shioConnectToHost` consumer doesn't exist yet (grep: only posted, never observed). The private-DB trust model is sound (remote attacker can't inject without the Apple ID). The risk goes live the moment you wire routing: validate `hostId` against locally-synced Hosts and don't display attacker-controlled `title`/`body` verbatim (CloudKitSignalService.swift:50,60,83-89). **Confidence high that it's currently inert.**

---

## 3. Landing — 5-second cold-visitor test

**Passes "what is it," fails "why do I want it."**

- **Works (what-is-it):** `The terminal for the agent era` / `Native on Mac, iPhone, and iPad. SSH into anything you own.` — clear, confident, cross-platform native SSH terminal. **Confidence high.**
- **Pretty-but-vague:** "agent era" is a vibe, not a benefit. **Nothing on the page mentions Claude Code, Codex, running agents, or supervising long jobs** — the entire wedge is invisible. Strip "agent era" and this is indistinguishable from Termius/Blink. A working dev reads "yet another mobile SSH app" and bounces. **Confidence high, impact high.**

**The single strongest asset on the whole site — the Mac page "why not the App Store" copy:** `A real terminal can't live in a sandbox` and `ships the way iTerm, Ghostty, and Warp do: signed with a Developer ID, notarized by Apple, downloaded directly.` It preempts the scary `.dmg` objection, borrows credibility from trusted peers, and shows competence rather than claiming it. **This page makes me trust the product more than the homepage does. Confidence high.**

**Funnel drop-offs:**

- **Pre-click is empty.** CTA is `Get the beta` → `You're in. Check your email for a TestFlight invite from Apple.` That's the *entire* funnel explanation. No "what do I get," no "is it usable today or a waitlist," no timing, no "what's TestFlight," no platform requirement (iPhone? Mac? both?). The success copy is good and concrete; everything *before* the click is blank. **Confidence high, impact high.** One line near the button ("Instant invite. Needs an iPhone or iPad on iOS 17+.") would lift signups.
- **First-connection is hand-waved.** Mac page: `the one-minute setup walks you through Tailscale and a single key.` This is the make-or-break activation moment, deferred to a separate guide, and it assumes you know what Tailscale is and will install a second daemon + account. **Confidence med, impact medium.**
- **The GitHub link reframes the whole product.** Footer links to github.com/shio-sh/shio, whose live description is `A clean, minimal SSH client for iPhone and iPad` and README opens with `premium iOS and iPadOS SSH client`. Devs always click the GitHub link and get a second, conflicting answer — *not* an agent terminal, *and* the self-described "premium" is exactly the show-don't-tell tell you avoid. **Confidence high, impact high.**
- **Honest conversion read:** from the homepage alone, probably no. What flips it to yes is the Mac page + a free, no-email notarized download. The path that actually works is **Mac-download-first, email-second** — the inverse of how the homepage leads. Consider leading with the free Mac download as the trust-builder.

---

## 4. What's missing / why someone wouldn't switch

- **The job that would justify switching isn't shipped.** Push-notify when the agent stops and needs a decision, one-tap approve/deny from the lock screen, resume the exact agent session. Live Activities is "currently a shell" (ROADMAP.md:15). Moshi already ships all of this — Live Activity approvals from the lock screen, Watch app, structured agent feed — and is in users' hands at 4.8 stars / 750+ ratings, free (**competitor confidence med**).
- **Anthropic shipped official Claude Code Remote Control (Feb 25, 2026)** — drive a desktop Claude Code session from the phone, no SSH/Tailscale. This commoditizes your hero use case for the largest agent cohort. **Confidence high it exists; it's a strategic-messaging threat, not a launch blocker** (see §6 — the "blocker" framing and some specifics didn't survive scrutiny). Your honest counter — vendor-neutrality across any agent on machines Anthropic doesn't gate + a *real terminal* vs a remote window — is valid but currently unsaid on the page.
- **Cursor also ships phone-based remote agent control.** "Mobile command deck for agents" is a 2026 baseline expectation, not a novel insight you're introducing. **Confidence high.** Differentiate on *how* (projects, your machines, Mac companion), not on the category's existence.
- **Not a threat (good news):** Termius's "Gloria" AI agent is DevOps-infra, not coding-agent supervision — sleeping giant, not present competitor (**confidence med**). Blink has no agent awareness/notifications — a real gap, but the whole field is filling it, so it's not a Shio-specific edge.

---

## 5. Code correctness + coherence

**The launch-blocking bug (restated because it's #1):** Release builds reject every SSH connection (SSHClient.swift:380-391; Fastfile:73,103; release-mac.yml). **Shipped builds connect to nothing. Confidence high.**

**Real bugs:**

- **`shio://pair` deep link is dead.** PairingPayload and MacPairingHost treat `shio://pair?d=<base64>` as a first-class entry point (PairingPayload.swift:8; MacPairingHost.swift:163 builds exactly that URL into the QR). But `ShioApp.handleDeepLink` only accepts `url.host == "connect"` and returns otherwise (ShioApp.swift:63-74) — no branch calls `PairingPayload.parse`. Tapping the pairing link off-camera is a no-op. **Confidence high, impact medium.**
- **`SSHClient.exec` drops stderr and resolves on EOF.** `ExecCollector` filters to `.channel` only (SSHClient.swift:439) and succeeds with whatever stdout arrived (445-446). A failed command (permission denied, `fd` not installed) returns empty — indistinguishable from "no matches." The 20s timeout (265-267) closes the channel and resolves *success* with partial output. Cross-machine file search reads as "search is broken" with no diagnostic. **Confidence med, impact low.**
- **Mac auth error copy is wrong for the Mac model.** `MacSSHSession` uses `.systemKeys` (offers all `~/.ssh` keys, MacSSHSession.swift:34-35) but the auth-failed message assumes the single Shio key: "Make sure this device's key is in the host's ~/.ssh/authorized_keys" (SSHClient.swift:67). On Mac the likely cause is none of the user's keys are trusted, and the message points at the wrong fix. RSA/passphrase keys are silently skipped (SystemSSHKeys.load) → a Mac user with only an RSA key gets `noUsableKey` and no path forward. **Confidence med, impact low.**

**Coherence drift (multiple surfaces tell different stories):**

- **README is badly stale.** README.md:11 "SSH client for iPhone and iPad", :27 "premium iOS and iPadOS SSH client", :7 "Your Mac, in your pocket", and Brick 2 "Terminal rendering (xterm.js in WKWebView)" — but the app renders with **libghostty + Metal**, has a full Mac target, and the landing markets "not a webview." An App Review engineer or press contact reading the README gets a materially wrong picture. **Confidence high, impact medium.**
- **`llms.txt` says "No account, no relay, no telemetry" and omits Mac entirely** ("a fast, native terminal for iPhone and iPad", "iOS 26+ and iPadOS 26+") while the same site's hero says "Native on Mac, iPhone, and iPad" and the beta runs through an email-harvesting Cloudflare Worker. Reconcilable (signup ≠ runtime) but the copy doesn't draw the line. **Confidence med.**
- **ROADMAP contradicts the built product:** ROADMAP.md:32 lists "A full macOS companion app" under **"Not on the roadmap"** while index.html:155 ships a "Download for Mac" button. **Confidence high.**

**No-tests risk (high):** zero test targets. The scariest untested surface is `SessionViewModel`'s reconnect/backoff state machine — `forceReconnect()` (SessionViewModel.swift:280-289) sets `reconnectAttempt=0` and fire-and-forgets `Task { await stale?.disconnect() }` while re-arming an immediate reconnect, so a flapping cellular/WiFi handoff can produce overlapping connect attempts → "terminal frozen" / "reconnect storm draining battery," the exact thing a mobile SSH user one-stars. Second: a missed libghostty `shutdown()` call (LibGhosttySurfaceView.swift:57-70) silently leaks GPU memory (deinit can't fire due to the `passRetained` +1). Both correct as written, neither covered. **Confidence med.**

---

## 6. Refuted / didn't hold up

The adversarial pass killed these — listed so the rest is trustworthy:

- **"Email input doesn't render / 'You're in' shows pre-submission"** — refuted. index.html:147 contains the literal `<input type="email">`; the success block (:153) carries `hidden` and is only revealed after a successful POST. WebFetch rendering limitation, not a site defect.
- **"localhost leaked into prod is the medium-severity worker exposure"** — refuted as *framed*. The code fact is true (src/index.ts:91), but the localhost carve-out is cosmetic: empty-Origin already allows everything, and CORS isn't an access-control boundary. Fixing it closes nothing — the real hole is the total absence of abuse protection.
- **"Mac `~/.ssh` keys get offered to an attacker server (amplifies broken host-key check)"** — refuted. In the Release artifact testers run, `validateHostKey` fails closed *before* user-auth, so keys are never offered. The DEBUG branch is insecure but Developer-ID distribution doesn't produce Debug builds. (The fail-closed behavior is its own blocker — "nothing connects" — but that's the opposite of "identity leaked.")
- **"Tapped/NFC `shio://pair` link auto-provisions your real key to attacker infra"** — refuted. The only `onOpenURL` handler guards `url.host == "connect"` and never parses a PairingPayload. `provisionKey` is reachable only from the in-app scanner/paste on a screen the user deliberately opened — a much narrower social-engineering threat than "tap a link."
- **"Mac aps-environment=development → away-push silently fails for shipped users"** — refuted. The Mac is the *sender* (writes a CKRecord via CloudKit transport, which doesn't use aps-environment); the iOS app is the receiver and correctly uses production for Release. The Mac target doesn't even compile the Push code. Latent hygiene wart, not a shipped failure.
- **"Developer-ID build may lack hardened runtime/notarization"** — refuted. Fastfile:116 sets `ENABLE_HARDENED_RUNTIME=YES`, Fastfile:118 notarizes, release-mac.yml staples. All prescriptions already satisfied; the grep just looked in the wrong file (project.yml instead of Fastfile).
- **"Anthropic Remote Control is a launch blocker"** — partially refuted. The product is real (Feb 25, 2026) and a genuine strategic threat, but "blocker" is wrong (nothing in your app/build breaks), and specifics like a `/rc` slash command, QR pairing, and "$20 Pro bundled at no extra cost" appear fabricated/unverified. The positioning advice (hit vendor-neutrality + real-terminal head-on) is sound; the severity was inflated.

---

## The 5 things I'd fix first (ranked by 2-week launch impact)

1. **Fix the host-key delegate** (SSHClient.swift:380-391): implement TOFU-pin-and-accept (store + compare `hostKeyFingerprint` that already exists) so Release builds can actually connect — otherwise the beta connects to nothing.
2. **Put Cloudflare Turnstile + a per-IP rate limit on the Worker** (src/index.ts) before it's a public email-bomb cannon against your ASC account.
3. **Surface the wedge you already shipped.** Projects-first is in the binary but invisible everywhere it matters (landing, README, ROADMAP, GitHub). Lead with it; frame agent-supervision as the stated direction (it's a deliberate v2 hold, not a gap). This is honest copy + docs, *not* rushing the supervision feature.
4. **Reconcile the story:** rewrite README/ROADMAP/llms.txt + the GitHub repo description to "native terminal for the agent era, Mac/iPhone/iPad, libghostty" — kill "premium / xterm.js / SSH-client-only / Mac-not-on-roadmap" so the dev who clicks through sees one product.
5. **Add ~3 lines of beta expectation-setting near the homepage CTA** (what you get, instant-vs-waitlist, platform requirement) and lead with the free Mac download as the trust-builder — Mac-download-first, email-second.

## The 1 thing I'd cut

**Cut "vendor-neutral SSH is the moat" from your positioning** — it's table stakes every competitor already has, a 5-minute competitor scan kills it, and leaning on it wastes the one place vendor-neutrality is actually sharp: as an explicit attack on Anthropic/Cursor's hosted-agent lock-in. Say *that* instead, or say nothing.
