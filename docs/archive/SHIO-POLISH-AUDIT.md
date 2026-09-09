# Shio Polish Audit — Phase 1 (2026-06-12)

> 28-agent audit (9 dimension finders + adversarial verifiers on every blocker/high correctness claim) over the full codebase. 123 findings, **0 refuted** — every high-severity claim below survived an independent refutation attempt against the actual code (and the pinned swift-nio-ssh sources where relevant). Part A is the prioritized synthesis; Part B has full per-finding evidence, keyed by ID.

## Build health ✅

Both targets build green from a fresh `xcodegen generate`:
- `ShioMac` Debug / macOS — **BUILD SUCCEEDED** (one benign `appintentsmetadataprocessor` notice).
- `Shio` Debug / iOS Simulator — **BUILD SUCCEEDED**, zero warnings. Note: the documented build command targets an `iPhone 16` simulator that doesn't exist on this machine (iPhone 17-era runtimes only); docs need a tweak.

## In-flight check: away-push permission fix (§8 of the handoff)

**The fix is correctly wired.** Test button → `PushService.requestAuthorizationAndRegister()` → prompt → `registerForRemoteNotifications` → APNs token → `CKQuerySubscription` traces end-to-end in code. The temporary `print("[shio] push: …")` diagnostics live in `Shio/Core/Push/PushService.swift` (AG-13 lists every line) — **removal stays gated on your on-device confirmation.**

The audit found four adjacent gaps to fix while we're in there: the notification delegate is set after an async post-launch hop, so a lock-screen Approve from a terminated app can be dropped (AG-3); the subscription is latched by a local UserDefaults flag that survives the Debug→TestFlight CloudKit-environment switch — on the very device you're using to verify, the Prod subscription may silently never be created (AG-6); a denied permission and the token race both produce a misleading "capability missing" diagnosis from the test button (AG-9); and the banner always says the static "A session needs you." instead of the per-agent title/body the Mac writes (AG-7).

## The headline

The architecture is sound and the happy paths are genuinely solid — the porcelain-v2 parser, bcrypt_pbkdf port, shell quoting, CloudKit schema validity, and actor discipline all checked out clean. The debt is concentrated in two places:

1. **Failure paths.** When anything goes wrong (auth rejected, host asleep, command fails, record stale), the error is swallowed and the UI either lies ("Committed and pushed."), hangs ("Connecting…" for 2 minutes), or silently no-ops.
2. **The connective tissue.** The single biggest finding, converged on by three independent finders: **`.shioConnectToHost` has zero observers.** Every "jump in" entry point — away-push tap, widget tap, Siri intent, Handoff, `shio://` URLs — posts a notification nothing listens to. The supervision loop's marquee moment (push arrives → tap → you're in the session) is dead code today, on every platform, and the Mac's signals carry an empty `hostId` anyway.

---

## Tier 0 — broken core promises (fix first, all verified)

| # | What | IDs |
|---|---|---|
| 1 | **Dead routing hub**: nothing observes `.shioConnectToHost`; push-tap/widget/Siri/Handoff all no-op; producers use 3 incompatible host-id formats; Mac signals send `hostId: ""`; `shio://pair` QR scanned with the Camera app opens Shio and does nothing (still unfixed from the pre-beta review) | AG-1/LC-1/PAR-1, AG-8, LC-4/PAR-6 |
| 2 | **SSH auth failures are invisible**: `connect()` resolves at TCP; wrong password / key-not-installed (the #1 first-run failure) = ~2-min hang → generic `eof`; `SSHError.authenticationFailed` and its actionable copy are unreachable dead code | SSH-1 |
| 3 | **Auto-reconnect stalls forever after one failed retry** — permanent "Reconnecting…" spinner, the ~31s backoff never happens, no disconnected overlay | SSH-2/LC-2 |
| 4 | **TOFU is half-shipped**: a changed host key surfaces as generic `eof` + endless reconnect (never the security warning), and `ShioKnownHosts.forget()` has zero callers so the documented recovery doesn't exist | SSH-3, SSH-4 |
| 5 | **`exec()` reports failure as success** (stderr dropped, exit code ignored, timeout returns partial output) → **GitWriter can claim "Committed and pushed." when nothing was** | SSH-5/ST-1, ST-7 |
| 6 | **iOS never refreshes status while visible** — no timer, no foreground refresh; the needs-you card never clears after Approve | ST-2/PAR-4 |
| 7 | **Skills lifecycle leaks**: rename/delete orphan `SKILL.md` dirs on every machine (remote deletes never happen — no tombstones); `materialize()` targets the *previous* active checkout; imported skills never sync back to the tool dir they came from | SK-1–SK-4, CK-3/CK-4/PAR-5 |
| 8 | **App lock bypassed by force-quit + relaunch** (cold launch never authenticates); Settings promises a 10s grace period that doesn't exist | LC-3, LC-9 |
| 9 | **Mac Files pane uses the wrong SSH auth** (Shio key the Mac never creates, instead of system keys) — remote browse/search fails while the terminal next to it works; cross-machine search also SSHes into the Mac itself | PAR-2, PAR-7 |
| 10 | **CloudKit lifecycle**: deleting a Host orphans checkouts (dead "This Mac" rows, silent no-op taps); the migration race creates duplicate Repos `reconcile()` never collapses — this is exactly what the unbaked 2-device test would hit | CK-1, CK-2 |
| 11 | **Action channel races**: stale-action replay (no TTL), swallowed delete failures, overlapping polls can double-inject keystrokes into tmux | AG-2, LC-6 |

## Tier 1 — robustness & correctness (high-value mediums)

- **Away-push quality**: AgentDetector's `waiting` outranks `running` on bare substrings in an 800-char window — inverts its own stated false-positive bias (AG-4); `fireAwaySignals` re-fires on Mac restart / transient empty scans (AG-5); subscription UserDefaults latch (AG-6); blind static banner (AG-7); notification delegate timing (AG-3/LC-11); test-button diagnosis (AG-9).
- **Status engine**: `isStale()` dead code — week-old cache renders as fresh (ST-3); `refresh()` cancels unrelated in-flight refreshes, dropping cold-host results (ST-4); remote agents wiped on transient probe failure — the needs-you signal flickers out (ST-5); session-name key mismatch hides project-level/indexed tmux sessions from the phone (ST-6/AG-10); local probes have no timeout + unread stderr pipe (ST-10); PR state not disk-cached, gh-missing indistinguishable from zero PRs (ST-11); CommitSheet doesn't refresh after push (ST-12).
- **SSH/session lifecycle**: stop() during in-flight connect resurrects the session (SSH-6); old SSHClient leaks on reconnect (SSH-7); Mirror-based fingerprint reflection fails *open* (SSH-8); Mac shows Swift enum dumps as error copy (SSH-9); remote scripts break silently on fish/csh login shells (SSH-10/ST-8); tilde paths quoted literally (SSH-12); Secure Enclave load failure aborts connect instead of falling back to Ed25519 (SSH-13).
- **Data**: `host.lastConnectedAt` never stamped on iOS → iPhone-only machines permanently "asleep" (CK-5); reconcile tie-break nondeterminism (CK-6); deleting a Project silently *promotes its skills to global* and fans them out everywhere (CK-7); orphaned Repo/Checkout records sync forever (CK-8).
- **Skills**: symlink guard re-points user-owned symlinks (SK-5); kill switch bypassed by one path + no iOS toggle (SK-6/PAR-13); cross-device disable never reconciles (SK-7); remote write failures fully swallowed (SK-8); CRLF breaks the frontmatter parser, then doubles frontmatter on re-materialize (SK-9); dirName collisions (SK-10).
- **Lifecycle**: orphaned Live Activities after force-quit (LC-5); MacPairingHost crashes on malformed Content-Length + appends unvalidated keys to authorized_keys (LC-7, LC-8); reconnect-on-foreground no-ops on stale `.connected` (LC-12); RunCommandIntent ships a fake placeholder result (LC-10/PAR-10); widget host list never prunes (LC-16).
- **Process**: the "19 unit tests" for GitStatus.parse don't exist — the repo has **no test target at all** (ST-13). Worth adding one and landing the parser tests for real.

## Tier 2 — design bugs (real rendering defects, not taste)

- **Light mode: lock/privacy screens render the wordmark invisible** — theme-ink text on hardcoded black (DI-1).
- Terminal surface hardcoded `#282C34` in both modes; the entire TerminalTheme light/dark pipeline is a dead no-op (DI-2).
- Mac empty-terminal mascot hardcodes dark-palette bone — invisible in light (DM-1).
- Raw system `.green/.orange/.yellow` status colors across ~10 sites bypassing the deepened-in-light status tokens (DI-4, DI-5, DI-6, DM-7).

## Tier 3 — design consistency, mechanical (#40)

- **19 `LegacyButton` call sites** (full retire list in DI-3) — blocked on adding two ShioButton variants first: destructive + full-width.
- Mac: MacFilesPane wholly on system List chrome (DM-2); command-palette selection on system blue + white (DM-3); tab strip on `.windowBackgroundColor` (DM-6); find bar / search field materials (DM-9); inconsistent confirm-button language across sheets (DM-10).
- iOS: Form sheets on stock system chrome vs. the kit's mono uppercase language (DI-7); KeyboardAccessoryView is the one terminal-adjacent chrome with zero tokens (DI-12); off-token radii/paddings/shadow (DI-11); hand-rolled status washes (DI-10).
- **Dead code to retire**: MacPromptRows + last MacInk remnants (DM-5), legacy ShioColor/TerminalTheme/ShioOpacity layer (DI-8), IPadRootView (PAR-16), and the `relay/` + `companion/` Python dirs that contradict the no-relay architecture (LC-17).
- DM-11 is the keep-list: system colors that are genuinely correct (menu-bar extra, Settings form, QR quiet zone) — don't churn these.

## Tier 4 — taste-level (PROPOSE FIRST — your input shapes these)

1. **iPad master/detail** (PAR-3): cheapest credible path per the audit — a size-class-gated `NavigationSplitView` reusing the existing iPhone views (sections sidebar → content), plus keyboard shortcuts. IPadRootView is dead code to delete either way.
2. **Mac sections sidebar** (DM-4): system source-list material + blue selection vs. bone ShioRail — making it match the rail is a look change you should sign off on.
3. **Form sheet restyle** (DI-7): migrating AddHost/AddProject/Settings off stock `Form` chrome changes their whole appearance.
4. **Split-pane focus ring** (DM-8): needs a deliberate pick — `ShioTheme.accent` would vanish over a dark terminal in light mode.
5. **Mac in-app Approve/Deny** on needs-you rows (PAR-11) and **Mac Files write parity** (PAR-12) — scope calls.
6. **Saved-commands module** — still parked for this pass, per the plan.

## Yours (device / Apple account) — checklist

- [ ] Away-push on device: tap "Send test notification" → Allow → tap again → `Push token: …xxxx ✓` → banner with Approve/Deny → full y/n loop. Then I remove the AG-13 diagnostics.
- [ ] Re-verify push **on a TestFlight build too** once AG-6 is fixed (Dev→Prod subscription latch).
- [ ] Secure Enclave key on device (#36) — Simulator hides the toggle.
- [ ] Live Activities on device.
- [ ] 2-device iCloud migration bake (after CK-1/CK-2 land).
- [ ] Visual light/dark pass on every surface once Tier 2/3 land (code audit can't see rendering).
- [ ] The Apple distribution batch (TestFlight + notarized Developer-ID DMG) — unchanged, batched last.

---
## Part B — full findings by dimension

> Generated 2026-06-12 by a 28-agent audit (9 finders + adversarial verifiers on every blocker/high correctness claim). 123 findings, 0 refuted. IDs are referenced from the priority plan in Part A.


### SSH transport & keys (SSH)

**Dimension summary:** The SSH layer's happy path is genuinely solid — the bcrypt_pbkdf/Blowfish port matches the OpenBSD reference, the OpenSSH key parser and wire formats are correct, shell quoting of paths/messages/session names is injection-safe everywhere I checked, and TOFU pinning works against the algorithms NIOSSH actually negotiates. The failure paths are where it breaks: connect() resolves at TCP so authentication failures (wrong password, key not installed — the most common first-run failure) and host-key changes never surface as their prepared errors, instead hanging ~2 minutes and collapsing into generic 'eof'; the iOS reconnect loop dies after one failed retry leaving a permanent spinner; a changed host key permanently locks the user out because nothing ever clears a pin; and exec()'s timeout-as-success plus dropped stderr/exit-status lets GitWriter report 'Committed and pushed.' when nothing was. Most of these share one root (no auth-completion gate on connect) and are fixable in the SSHClient layer without touching the architecture.


#### SSH-1 · `high` · Auth failure never surfaces: connect() returns at TCP, exhausted auth offers stall silently, SSHError.authenticationFailed is unreachable dead code

`Shio/Core/SSH/SSHClient.swift:206` · confidence high · platform all · **verified real**

SSHClient.doConnect resolves at TCP establishment: `let parent = try await bootstrap.connect(host: cfg.host, port: cfg.port).get()` (SSHClient.swift:206) — the SSH version exchange/KEX/userauth all happen *after* this future fires, so `connect()` succeeding does not mean authenticated. When the server rejects the offered credentials, the auth delegate runs out and resolves nil: `nextChallengePromise.succeed(nil)` (SSHClient.swift:368, 383, 396). In the pinned swift-nio-ssh (checkout 1a915a3), a nil offer is handled in NIOSSHHandler.processInboundMessageResult as `case .success(.none): // Do nothing` — no error is fired, no close happens; the connection idles until the server's LoginGraceTime (~120s default) kills it. The subsequent `requestShell()` promise is only failed at handler removal with `ChannelError.eof` (NIOSSH NIOSSHHandler.handlerRemoved: `next.promise?.fail(ChannelError.eof)`). Net effect: wrong password or key-not-in-authorized_keys (the single most common first-run failure) = "Connecting…" hang for ~2 minutes, then a generic eof error — and `case authenticationFailed` (SSHClient.swift:53) with its actionable copy ("Make sure this device's key is in the host's ~/.ssh/authorized_keys", line 69) is never thrown anywhere in the codebase (verified by grep). exec()/SFTP/status probes against an auth-stalled host hang the same way since the exec timeout (SSHClient.swift:288) is only scheduled after channel creation succeeds.

**Suggested fix:** Gate connect() on auth completion: add a parent-pipeline handler that listens for UserAuthSuccessEvent / errorCaught and complete a handshake promise with a deadline (e.g. 15s); when the auth delegate exhausts its offers, record that and fail the promise with SSHError.authenticationFailed instead of relying on the server to hang up.

<details><summary>Verifier notes</summary>

Every link in the claimed chain reproduces from the actual code. (1) /Users/amrith/Shio/Shio/Core/SSH/SSHClient.swift:206 resolves connect() at TCP establishment; the SSH handshake starts after channelActive in NIOSSHHandler. (2) The pinned swift-nio-ssh is exactly 1a915a324afefd4031e396e81a0e210178621be8 (Package.resolved, v0.13.0). When SSHAuthenticationDelegate exhausts offers it calls nextChallengePromise.succeed(nil) (SSHClient.swift:368/383/396); that nil maps via AcceptsUserAuthMessages.transform(nil)->nil into possibleFutureMessage, handled in NIOSSHHandler.processInboundMessageResult as `case .success(.none): // Do nothing` (NIOSSHHandler.swift:241-243) — no error, no close. Decisively, UserAuthenticationStateMachine.noFurtherMethods() (the only client transition to .authenticationFailed) has zero callers anywhere in NIOSSH Sources, so the library itself never surfaces client auth exhaustion; the connection idles until the server's LoginGraceTime closes it. (3) requestShell/exec channel creation queues in pendingChannelInitializations, gated on stateMachine.hasActivated (false during .userAuthentication, SSHConnectionStateMachine.swift:1265), and the pending promise is only failed with ChannelError.eof in handlerRemoved (NIOSSHHandler.swift:142-144). The exec timeout (SSHClient.swift:288) is scheduled only after `chPromise.futureResult.get()` (line 284), so GitStatusReader's 8s probe timeout never arms against an auth-stalled host. (4) grep confirms SSHError.authenticationFailed appears only at its declaration (SSHClient.swift:53) and description (line 69) — never thrown. Aggravating detail beyond the claim: SessionViewModel.connectOnce (SessionViewModel.swift:388-396) treats the eventual eof as an unexpected disconnect and enters the auto-reconnect loop (maxReconnects=6), re-running the same doomed auth, so a wrong password / unauthorized key shows Connecting/Reconnecting for many minutes with no actionable error. Severity: high is correct — valid-credential flows work (so not a blocker), but this is a real robustness bug in the most common first-run failure path of a shipped flow, and the actionable error copy is unreachable.
</details>


#### SSH-2 · `high` · Auto-reconnect loop dies after its first failed retry — session stuck on 'reconnecting' forever, never retries, never shows the disconnected overlay

`Shio/Features/Terminal/SessionViewModel.swift:401` · confidence high · platform ios · **verified real**

connectOnce(isReconnect: true) sets `state = isReconnect ? .reconnecting : .connecting` (SessionViewModel.swift:322). When that attempt fails, the catch calls `handleUnexpectedDisconnect(reason:)` (line 392), whose first statement is `if case .reconnecting = state { return }` (line 401, the "don't pile on a duplicate task" guard). Since connectOnce itself already set state to .reconnecting, every failed retry early-returns without scheduling the next backoff and without ever reaching the give-up branch (`state = .disconnected`, line 403). kickReconnect's task performs exactly one attempt (lines 440-457) and nothing else continues the chain. So a sleeping/dead Mac produces: first drop → one retry ~0.5s later → permanent `.reconnecting` UI with zero further attempts. The advertised "~31s of exponential backoff" (comment, line 93) never happens; recovery requires a network-path change or app foregrounding (reconnectIfNeeded) to re-kick.

**Suggested fix:** In connectOnce's catch path, bypass the dedupe guard — e.g. call kickReconnect directly (after incrementing/checking reconnectAttempt), or have handleUnexpectedDisconnect take an `isRetryFailure` flag that skips the `.reconnecting` early-return.

<details><summary>Verifier notes</summary>

Confirmed real by full code trace. connectOnce(isReconnect: true) sets state = .reconnecting (SessionViewModel.swift:322) before attempting. On failure its catch calls handleUnexpectedDisconnect (line 392), whose first line `if case .reconnecting = state { return }` (line 401) early-returns — so no new kickReconnect is scheduled and the give-up branch (line 403) is unreachable. kickReconnect's Task (lines 440-457) performs exactly one attempt and ends; it is the only continuation of the chain, and SSHClient.onDisconnect cannot rescue it because the handler that fires it (ShellDataHandler.onClose, SSHClient.swift:231-235) is only installed in requestShell, never for a failed TCP connect. Net behavior on a dead/sleeping host: one retry ~0.5s after the drop, then permanent `.reconnecting` showing the passive "Reconnecting…" capsule (TerminalScene.swift:325-339, no retry button); the disconnectedOverlay never appears and reconnectAttempt is stuck at 1, so the advertised ~31s backoff (comment lines 91-94) never happens. All rescue paths verified as conditional: path monitor re-kick requires the phone's own NWPath to go unsatisfied→satisfied (line 249); interface-switch forceReconnect requires state == .connected (line 260); reconnectIfNeeded only fires on app foregrounding and yields one attempt that dies at the same guard. Corroborating drift: connectOnce's doc comment (lines 318-320) claims failure "leaves state at .disconnected" — stale contract the line-401 guard was written against. Severity high (not blocker) is correct: real bug in a shipped core resilience path, but tmux preserves the session and foregrounding the app recovers it, so the flow is degraded rather than fully broken.
</details>


#### SSH-3 · `high` · Host-key-changed (TOFU mismatch) never shows its security warning — surfaces as generic 'eof' plus an endless reconnect loop

`Shio/Core/SSH/SSHClient.swift:477` · confidence high · platform all · **verified real**

SSHHostKeyDelegate fails only the *validation* promise: `validationCompletePromise.fail(SSHClient.SSHError.hostKeyChanged)` (SSHClient.swift:477). Because host-key validation happens after `connect()` has already returned (see TCP-completion finding), the error can't propagate out of connect(); NIOSSH tears the connection down and the pending requestShell/exec child-channel promise is failed with `ChannelError.eof` in NIOSSHHandler.handlerRemoved — the original hostKeyChanged error is discarded. Grep confirms no code anywhere catches `.hostKeyChanged`; the carefully written warning copy ("…or that the connection is being intercepted. Refused for safety.", SSHClient.swift:80-81) is unreachable. On iOS the user instead sees the reconnect spinner (SessionViewModel treats the eof as an ordinary drop and retries); on Mac they see a raw "eof" line. The pin still *protects* (connection is refused), but the user is never told why — defeating the entire point of surfacing a MITM/reinstall.

**Suggested fix:** Stash the mismatch on the delegate (or a per-connection error box) when validation fails, and have connect()/requestShell()/onDisconnect consult it to rethrow SSHError.hostKeyChanged; suppress auto-reconnect when that error is set.

<details><summary>Verifier notes</summary>

Verified every link in the claimed chain against the actual code and vendored dependencies. (1) Grep confirms `.hostKeyChanged` is thrown only at SSHClient.swift:477 and caught nowhere; the warning copy at SSHClient.swift:80-81 is unreachable. (2) `doConnect()` resolves on `bootstrap.connect().get()` (TCP establishment, SSHClient.swift:206), while host-key validation runs during KEX a round trip later (vendored swift-nio-ssh SSHKeyExchangeStateMachine.swift:316-321), so the error structurally cannot fail connect(). (3) The failed validation promise only triggers `context.fireErrorCaught` (NIOSSHHandler.swift:244-246); NIOSSHHandler has no errorCaught override, SSHClient adds no other parent-pipeline handler, and NIO's tail `errorCaught0` is a no-op — the error is silently dropped and the channel is not even closed locally. requestShell's createChannel promise stays queued behind `stateMachine.hasActivated` (NIOSSHHandler.swift:286) until the server's LoginGraceTime closes TCP, when handlerRemoved fails it with ChannelError.eof (NIOSSHHandler.swift:142-143) — so each attempt also hangs for up to ~2 minutes, worse than claimed. (4) iOS SessionViewModel.connectOnce (388-396) treats the eof as an ordinary drop → reconnect backoff (capped at 6, not literally endless, but restarted on every foreground via reconnectIfNeeded) ending in a generic `.disconnected(reason:)`; Mac ConnectErrorTranslator falls through to `return raw` = "eof" (ConnectErrorTranslator.swift:44) printed as a raw error line (MacSSHSession.swift:95-98). Aggravating factor the claim missed: ShioKnownHosts.forget has zero callers and the pin is keyed by host:port in UserDefaults, so after a legitimate server reinstall the host is permanently unconnectable — the recovery the error copy describes does not exist. The pin still refuses the connection (security holds), and a host-key change is an infrequent event, but the entire user-facing half of the TOFU feature is dead in every shipped path with a hang + generic error + no recovery. Severity high is correct (not blocker: requires a host-key-change event; core connect flow otherwise unaffected).
</details>


#### SSH-4 · `high` · No way to clear a changed host-key pin: ShioKnownHosts.forget() has zero callers, so the documented recovery ('remove the host and re-add it') does not work

`Shio/Core/SSH/SSHClient.swift:424` · confidence high · platform all · **verified real**

`static func forget(_ hostPort: String)` (SSHClient.swift:424-429) is never called — grep across Shio/ and ShioMac/ finds no reference to ShioKnownHosts outside SSHClient.swift itself. Pins live in `UserDefaults.standard` under "shio.knownHosts.v1" keyed by "host:port" (lines 408-421), so deleting the Host model and re-adding it changes nothing. Yet the hostKeyChanged error copy explicitly instructs: "Remove the host and re-add it if you trust the change." (line 81). After any legitimate host-key change (macOS reinstall, server rebuild, sshd key rotation) the user is permanently locked out of that host:port — the only real escape is deleting and reinstalling the app.

**Suggested fix:** Call ShioKnownHosts.forget("host:port") from the Host-delete flow (and/or add an explicit 'Trust new key' action on the hostKeyChanged error), keeping the wording and behavior in sync.

<details><summary>Verifier notes</summary>

Verified end-to-end. (1) ShioKnownHosts.forget (Shio/Core/SSH/SSHClient.swift:424-429) has zero callers: repo-wide grep shows ShioKnownHosts referenced only within SSHClient.swift (fingerprint at :473, pin at :480). (2) Pins persist in UserDefaults.standard under "shio.knownHosts.v1", keyed by "\(cfg.host):\(cfg.port)" (SSHClient.swift:184, :408). (3) All three host-delete flows (HostListView.swift:141-144, MacMachinesView.swift remove() ~:196-200, IPadRootView.swift:59) are bare `context.delete(host); try? context.save()` — none clear the pin, so re-adding the same host:port hits the same stale fingerprint and SSHHostKeyDelegate.validateHostKey fails with .hostKeyChanged again (SSHClient.swift:473-478). (4) The error copy at SSHClient.swift:81 explicitly instructs "Remove the host and re-add it if you trust the change," which is a no-op. (5) No UI handles .hostKeyChanged specially — grep finds it only in SSHClient.swift. After any legitimate key rotation the user is locked out of that host:port; on iOS the only escape is app reinstall (clears UserDefaults), and on macOS even reinstall does not clear ~/Library/Preferences, so the Mac app has no user-reachable recovery at all (the only undocumented workaround is re-adding the host under a different address/IP, which changes the pin key). Severity high is correct: the trigger is occasional (server rebuild, macOS reinstall, sshd key regen) but the consequence is permanent loss of connectivity to a machine — the app's core function — in a shipped path, with actively misleading recovery copy. Not a re-flag of the known-good TOFU pinning (ce829ef); the pinning works, the recovery path is the gap.
</details>


#### SSH-5 · `high` · exec() reports timeouts and stderr-only failures as success — GitWriter can claim 'Committed and pushed.' when nothing was committed or pushed

`Shio/Core/Status/GitWriter.swift:58` · confidence high · platform all · **verified real**

SSHClient.exec has three blind spots: the 20/40s timeout closes the channel and the collector *succeeds* with partial output (SSHClient.swift:286-291, "Timeout closes the channel → EOF → the collector succeeds"); stderr is dropped (`guard channelData.type == .channel else { return }`, line 533); and the exit-status channel event is never read (ExecCollector implements no userInboundEventTriggered). GitStatusReader defends itself by echoing `"$?"` into stdout, but GitWriter does not: its command redirects only push's stderr (`git -C p add -A && git -C p commit -m m && git -C p push 2>&1`, GitWriter.swift:21), and interpret() treats empty output as success: `return .ok(t.isEmpty ? "Committed and pushed." : t)` (line 58). Concrete failure: on a host with no git identity configured, `git commit` prints "Please tell me who you are" to *stderr* and exits non-zero → the && chain stops, exec returns "", and Shio reports "Committed and pushed." Same false success if push hangs past the 40s timeout after the commit landed (commit output contains no 'fatal:'/'error:').

**Suggested fix:** Append `; printf '__SHIO_EXIT__%d' "$?"` (and 2>&1 the whole chain) so GitWriter can see the real exit code, and make SSHClient.exec distinguish timeout from EOF (e.g. fail the promise or return a (output, timedOut, exitCode) struct).

<details><summary>Verifier notes</summary>

VERIFIED REAL. Every link in the claimed chain checks out against the actual code, and I reproduced the git stream behavior empirically.

1) ExecCollector drops stderr and never reads the exit status (/Users/amrith/Shio/Shio/Core/SSH/SSHClient.swift:521-546). Line 532: `guard channelData.type == .channel else { return }   // stdout only`. The handler implements only channelRead/channelInactive/errorCaught — no userInboundEventTriggered, so SSHChannelRequestEvent.ExitStatus is never observed. Line 538-540: channelInactive resolves the promise with whatever stdout arrived, as success.

2) The 40s timeout closes the channel, which lands in that same channelInactive → success-with-partial-output path (SSHClient.swift:286-291, comment literally says "Timeout closes the channel → EOF → the collector succeeds").

3) GitWriter's command redirects only push's stderr: `git -C \(p) add -A && git -C \(p) commit -m \(shellQuote(message)) && git -C \(p) push 2>&1` (GitWriter.swift:21) — the `2>&1` binds to the last simple command in the && chain, so add/commit stderr is dropped by ExecCollector on remote hosts. interpret() then treats empty output as success: `return .ok(t.isEmpty ? "Committed and pushed." : t)` (GitWriter.swift:58).

4) Empirical confirmation: `git commit` with unresolvable identity exits 128 with ALL output on stderr, stdout empty ("Author identity unknown / *** Please tell me who you are. / fatal: no email was given..."). Same for `git -C <missing path> add -A` ("fatal: cannot change to ...: No such file or directory" — stderr only, exit 128). The stale/missing-path case is especially relevant given Shio's cross-machine checkout model. In both cases the remote exec returns "" → CommitSheet shows "Committed and pushed." in green and fires onCommitted() (/Users/amrith/Shio/Shio/Core/Design/CommitSheet.swift:78).

5) The asymmetry with GitStatusReader is real: GitStatusReader.swift:66 echoes `printf '\(exMarker)%d\(endMarker)' "$?"` into stdout to recover the exit code; GitWriter has no such defense.

6) Timeout scenario also real: if push hangs past 40s after commit landed, stdout contains only the commit summary (no "fatal:"/"error:"/"rejected") → reported as .ok while nothing was pushed.

Scope check: the local macOS path is largely immune (Process merges stdout+stderr into one pipe, so the "fatal:"/"error:" heuristic catches failures, though it too ignores exit codes). But on iOS — the hero device — there is no local path (GitWriter.swift:42 "No local shell on this device."), so EVERY commit-and-push from the iPhone dashboard goes through the broken SSH exec path. Mitigation: a later status refresh would show the repo still dirty, which keeps this from being a blocker, but the explicit false "Committed and pushed." success message in a shipped, user-facing flow is a real correctness bug. Severity HIGH is appropriate.
</details>


#### SSH-6 · `medium` · stop() during an in-flight connect resurrects the session: connectOnce's success path never re-checks userInitiatedStop/cancellation

`Shio/Features/Terminal/SessionViewModel.swift:362` · confidence high · platform ios

connectOnce assigns `self.client = client` (line 359) then awaits `client.connect()` / `client.requestShell()` (362-363). Neither NIO future is cancellation-aware, so if the user closes the session mid-connect, stop() (lines 459-468) runs: it awaits `client?.disconnect()` (which no-ops if the channel isn't set yet), nils client, and sets `state = .idle` — but the still-running connectOnce then completes, sets `state = .connected` (line 364), fires success haptics, starts a Live Activity (367-372), and writes the tmux resume command. The success path checks neither `userInitiatedStop` nor `Task.isCancelled` (only the catch path does, line 391). Result: a session the user closed shows .connected, a Live Activity appears for it, and the now-unreferenced SSH connection stays open with no owner to close it.

**Suggested fix:** After each await in connectOnce, guard on `!userInitiatedStop` (and Task.isCancelled); if tripped, disconnect the freshly-connected client and return.


#### SSH-7 · `medium` · Reconnect replaces the SSHClient without disconnecting the old one — parent SSH/TCP connection leaks when only the shell channel died

`Shio/Features/Terminal/SessionViewModel.swift:359` · confidence high · platform ios

connectOnce always allocates a fresh client and overwrites the previous one: `let client = SSHClient(configuration: configuration)` (line 325) … `self.client = client` (line 359), with no disconnect of the prior instance. onDisconnect fires from ShellDataHandler on the *child* (shell) channel (SSHClient.swift:514-516), so when only the shell ends while the parent connection survives — e.g. the user types `exit` and tmux/shell terminates, or requestShell throws after connect succeeded — handleUnexpectedDisconnect → kickReconnect → connectOnce replaces the client and the old parent channel is never closed. SSHClient has no deinit cleanup ("No deinit shutdown — ELG is shared", SSHClient.swift:108) and NIO keeps the registered channel alive, so each such cycle leaks a live SSH connection until the server reaps it. forceReconnect shows the intended pattern (`let stale = client; client = nil; Task { await stale?.disconnect() }`, lines 284-286) but the main reconnect path doesn't use it.

**Suggested fix:** At the top of connectOnce (or in handleUnexpectedDisconnect), capture the old client and `await`/fire-and-forget `disconnect()` on it before assigning the new one, mirroring forceReconnect.


#### SSH-8 · `medium` · hostKeyFingerprint's Mirror-based reflection fails open: any NIOSSH internal rename silently disables TOFU pinning for every host

`Shio/Core/SSH/SSHClient.swift:469` · confidence high · platform all

Fingerprinting reflects on NIOSSH internals: `Mirror(reflecting: key).children.first(where: { $0.label == "backingKey" })` (SSHClient.swift:438), and a nil fingerprint is accepted *without consulting the existing pin*: `guard let fp = hostKeyFingerprint(hostKey) else { validationCompletePromise.succeed(()); return }` (lines 469-471). Today this is not exploitable — I verified the pinned swift-nio-ssh (1a915a3) advertises only `ssh-ed25519, ecdsa-sha2-nistp384, ecdsa-sha2-nistp256, ecdsa-sha2-nistp521` as server host key algorithms (SSHKeyExchangeStateMachine.swift:604-606), all four of which the switch at lines 442-445 handles, and `backingKey` exists on NIOSSHPublicKey. But the failure mode of any future package bump that renames/restructures `backingKey` is that *every* fingerprint returns nil and the app accepts *all* host keys, pinned or not — a silent, total loss of MITM protection with no compile-time or test signal.

**Suggested fix:** Fail closed when a pin exists but the key can't be fingerprinted (only accept-without-pinning on first contact), and add a unit test that fingerprints a known NIOSSHPublicKey so a dependency bump that breaks reflection fails CI.


#### SSH-9 · `medium` · Mac connect failures render Swift enum dumps ('connectionFailed(\"…\")', 'eof') instead of the prepared human copy

`ShioMac/MacSSHSession.swift:95` · confidence high · platform mac

MacSSHSession.connect's catch re-translates errors that are already SSHError values: `let msg = ConnectErrorTranslator.translate(error, host: hostName, port: port)` (MacSSHSession.swift:95). ConnectErrorTranslator works on `String(describing: error)` (ConnectErrorTranslator.swift:18) and falls through to `return raw` (line 44). For `SSHError.connectionFailed(why)` — which client.connect() throws with an *already translated* message (SSHClient.swift:211) — String(describing:) yields the enum case dump `connectionFailed("Tried mac:22 but couldn't get through…\n• …")` with escaped quotes/newlines, which matches none of the contains() patterns and is printed verbatim on the terminal (line 97). requestShell failures surface as ChannelError.eof → the literal string "eof". The iOS path uses `error.localizedDescription` and gets the proper copy; the Mac path (the system-keys flow this audit was asked to compare) shows debug output.

**Suggested fix:** In MacSSHSession, use `error.localizedDescription` when the error is an SSHError (or LocalizedError) and only run ConnectErrorTranslator on raw transport errors — translate once, not twice.


#### SSH-10 · `medium` · Status/agents/skills remote scripts are POSIX-shell-only; fish (or csh) login shells break them silently — every checkout reads 'timedOut', skills never materialize

`Shio/Core/Status/GitStatusReader.swift:69` · confidence medium · platform all

sshd executes exec commands via the user's login shell (`$SHELL -c "…"`). GitStatusReader.remoteScript emits POSIX constructs fish cannot parse: `command -v git >/dev/null 2>&1 || { printf '…'; }` (brace group, line 69), `if command -v tmux …; then` / `while IFS= read -r s; do … done` (lines 73-79), and `"$?"` (line 66, fish uses $status). SkillMaterializer.writeRemote similarly emits `if [ -d … ]; then …; fi` lines. On a fish parse error the whole script produces nothing on stdout and stderr is dropped by ExecCollector, so probeRemoteWithAgents falls through to `for p in paths where parsed[p] == nil { parsed[p] = .timedOut }` (GitStatusReader.swift:51): every checkout on that host permanently shows timed-out git status, remote agents are never detected, and skills silently never sync — with no error anywhere. fish is a common dev login shell, and the interactive terminal path (tmux attach, which is fish-compatible) works fine, making the broken dashboard look like a Shio bug rather than a shell mismatch.

**Suggested fix:** Run the scripts shell-agnostically, e.g. wrap as `sh -c '<script>'` (the existing single-quote escaping already handles the embedding) or `exec sh` first, in GitStatusReader, SkillMaterializer.writeRemote, and SkillImporter.


#### SSH-11 · `low` · Remote skill materialization swallows every error (try? + empty catch) — skills silently absent on remote machines

`Shio/Core/Skills/SkillMaterializer.swift:212` · confidence high · platform all

writeRemote runs the whole sync as `_ = try? await client.exec(script, timeout: .seconds(12))` and its catch block only does `await client.disconnect()` (SkillMaterializer.swift:209-216) — connect failures, script failures, and 12s timeouts (which exec also reports as success with partial output) all vanish. The local writes are `try?` as well (lines 130-131). The product promise is "writes those files on every machine"; when it doesn't, neither the user nor a log knows.

**Suggested fix:** Bubble a per-host success/failure status out of writeRemote (even just into a log/last-sync field shown in the Skills library) instead of discarding the error.


#### SSH-12 · `low` · Tilde paths are single-quoted into remote commands literally — '~/code/x' breaks git status and makes the guarded clone create a literal '~' directory

`Shio/Core/SSH/TmuxResume.swift:73` · confidence high · platform all

TmuxResume.resumeCommand single-quotes startDir/cloneURL: `"[ -d \(singleQuoted(startDir)) ] || git clone \(singleQuoted(cloneURL)) \(singleQuoted(startDir)); "` (TmuxResume.swift:73) — quoting is injection-safe, but a stored path like `~/code/x` is never tilde-expanded, so `[ -d '~/code/x' ]` is always false and `git clone … '~/code/x'` creates a directory literally named `~` in $HOME. GitStatusReader's `git -C '~/code/x'` likewise exits 128 and the checkout reads as notARepo. The Mac add-project form takes free-text paths (`@State private var location = ""`, MacAddProjectForm.swift:26) and nothing normalizes a leading `~` (SkillMaterializer expands tilde locally at line 120, showing the case was anticipated elsewhere).

**Suggested fix:** Normalize stored checkout paths (reject or expand a leading `~`, e.g. rewrite to \"$HOME/…\" outside the single quotes) at entry time or in the command builders.


#### SSH-13 · `low` · Secure Enclave key load failure aborts the whole connect instead of falling back to the still-valid Ed25519 key

`Shio/Core/SSH/SSHClient.swift:139` · confidence high · platform ios

resolveShioKey: `if KeyManager.useEnclaveKey, let se = try KeyManager.existingEnclaveKey() { … }` (SSHClient.swift:139) — the `try` propagates, so if the enclave blob loads but can't be reconstructed (KeyManager.existingEnclaveKey throws `.keyDataCorrupted`, KeyManager.swift:130-131 — e.g. after a device-to-device migration where the opaque dataRepresentation is bound to the old device's Enclave), the whole connect fails with "Keychain error — the SSH key looks corrupted" even though the Ed25519 key appended at line 142 would have authenticated fine. The systemKeys path already does this correctly with `try?` (line 169).

**Suggested fix:** Use `try?` (or catch and continue) for the enclave key in resolveShioKey so a broken opt-in enclave key degrades to the default Ed25519 key instead of blocking all connections.


#### SSH-14 · `low` · SSHClient mutable channel state is unsynchronized across threads (@unchecked Sendable without a lock)

`Shio/Core/SSH/SSHClient.swift:96` · confidence medium · platform all

`private var channel: (any Channel)?` / `childChannel` (SSHClient.swift:96-97) are written by non-isolated async funcs (connect/requestShell/disconnect run on the concurrent executor) and read by `write(_:)`/`resize` called synchronously from the MainActor (terminal.onInput → client.write, SessionViewModel.swift:131-132). E.g. `stop()`'s `await client?.disconnect()` nils both vars on a pool thread (lines 326-327) while a keystroke can concurrently execute `guard let child = childChannel` (line 301). There is no lock; the class is `@unchecked Sendable` (line 18). In practice the races are read-vs-nil on Optional refs and unlikely to corrupt, but it's UB under the Swift memory model and exactly the kind of thing strict concurrency was enabled to prevent.

**Suggested fix:** Protect channel/childChannel/resolvedKeys with an NIOLockedValueBox (or make SSHClient an actor with nonisolated callback entry points).


### SwiftData + CloudKit sync (CK)

**Dimension summary:** The SwiftData schema itself is genuinely CloudKit-valid — every attribute is optional or defaulted, every relationship is optional with an explicit inverse and .nullify, no unique constraints — and the container fallback chain (CloudKit → local → in-memory) is sound, so the store won't silently drop to local-only from a modeling mistake. The real risk is lifecycle, not schema: ProjectMigration's multi-device story is only half-implemented (the reconciler collapses duplicate checkouts but not the duplicate Repos the documented race creates, and its createdAt tie-break is nondeterministic), and none of the delete flows (Host, Project, Skill) clean up what .nullify orphans — producing silently dead project rows after a host delete, permanent orphan records in the private DB, and stale/escalated SKILL.md files on machines. Actor discipline is good (all stores are @MainActor @Observable; model mutations stay on main; SSH/file fan-out works on pre-resolved Sendable values). The unbaked 2-device migration bake the handoff doc calls out is the right next gate — findings 1-3 are exactly what it would surface.


#### CK-1 · `high` · Migration race creates duplicate Repos that reconcile() never collapses, and can steal checkouts from the real Repo

`Shio/Core/Profiles/ProjectMigration.swift:36` · confidence high · platform all · **verified real**

ProjectMigration.swift's header (lines 10-16) promises "A reconciler collapses any duplicates created in the narrow window before sync converges", but reconcile() (lines 94-111) only dedups ProjectCheckouts keyed on (host,path) — there is no Repo dedup anywhere (grep confirms `identityKey` is referenced only inside Core/Profiles/). backfillRepos guards on `guard (project.repos ?? []).isEmpty else { continue }` (line 36). On a second device whose CloudKit import is mid-flight (or two devices migrating concurrently), the Project record can be present while its Repo record hasn't imported yet → a duplicate Repo with the same identityKey is created (lines 45-49). Worse, line 50 `for checkout in checkouts { checkout.repo = repo }` reparents any already-imported checkouts onto the duplicate, so when the real Repo arrives it has zero checkouts and that reparent syncs back to the origin device. The duplicate Repo is permanent: it shows in `repoCount: (project.repos ?? []).count` (ProjectsView.swift:52) and `project.sortedRepos` rows, and a zero-checkout Repo selected as `activeRepo` makes `SessionStore.openOrCreate(repo:)` (SessionStore.swift:101) return nil → tapping the project silently does nothing. SHIO_STATE_OF_THE_UNION.md §7.6 admits this path is "Not yet baked on a real 2-device iCloud account".

**Suggested fix:** Add a Repo dedup pass to reconcile(): collapse repos under one project sharing the same non-nil identityKey (keep oldest, move checkouts over), and/or have backfillRepos skip projects whose checkouts already reference a Repo.

<details><summary>Verifier notes</summary>

Verified against the code. (1) reconcile() (ProjectMigration.swift:94-113) only dedups ProjectCheckouts by (host,path); no Repo dedup exists anywhere (identityKey referenced only in Core/Profiles; Repo.swift:21-22 states the 'same repo' invariant nothing enforces), despite the header (lines 12-16) promising the reconciler collapses race-created duplicates. (2) The race is reachable: backfillRepos guards solely on the synced `(project.repos ?? []).isEmpty` (line 36); CloudKit mirroring is the active first-choice store (HostStore.swift:41, .private("iCloud.sh.shio.app")); ProjectMigration.run executes every launch on both targets (ShioApp.swift:18, MacShell.swift:76); the standard deployment is exactly two devices (Mac companion + iPhone). A second device launching before the first device's Repo record imports creates a duplicate Repo (lines 45-49) and line 50 reparents the legacy checkouts onto it — the two Repo records are never merged. (3) Downstream effects confirmed: ProjectsView.swift:52 shows inflated repoCount; both backfilled repos get identical lastOpenedAt (ProjectMigration.swift:47) so activeRepo (Project.swift:115) picks arbitrarily; SessionStore.openOrCreate(project:) (SessionStore.swift:91-95) has no fallback when openOrCreate(repo:) returns nil for a zero-checkout repo (line 101 guard), and ProjectsView.swift:104-109 only opens the terminal on non-nil — tap silently no-ops. Refutations tested and rejected: reconcile doesn't cover it; CloudKit never merges distinct records; migration runs synchronously at launch before async import can converge; sync is enabled in the shipped config (SHIO_STATE_OF_THE_UNION.md line 57 marks 2-device verification as untested, not disabled). Severity high (not blocker): requires the multi-device window plus an activeRepo coin-flip for the dead-tap symptom, but it is permanent, self-heals never, pollutes the UI, and silently breaks the core open-project flow in the primary topology. Minor fix nit: an identityKey-keyed dedup misses concurrent M0 upgrades where each device stamps its own UUID; the 'skip if checkouts already reference a Repo' guard is the stronger half.
</details>


#### CK-2 · `high` · Deleting a Host leaves orphaned checkouts: project taps silently no-op on iOS, and dead checkouts masquerade as "This Mac" on macOS

`Shio/Features/Hosts/HostListView.swift:141` · confidence high · platform all · **verified real**

Host deletion is bare everywhere: `context.delete(host); try? context.save()` (HostListView.swift:141-144, MacMachinesView.swift:196-200, IPadRootView.swift:59) — `.nullify` (Host.swift:87-95) sets checkout.host = nil but nothing removes or reassigns the orphaned checkouts. Consequences: (1) iOS — `openOrCreate(repo:)` does `guard let checkout = repo.activeCheckout, let host = checkout.host else { return nil }` (SessionStore.swift:101) and the caller `if sessionStore.openOrCreate(repo: repo) != nil { showingTerminal = true }` (ProjectsView.swift:99) — tapping the project does nothing, no error, even when the repo has another checkout on a live host (`Repo.activeCheckout` sorts only by lastOpenedAt, Repo.swift:49-53, with no host-validity fallback). (2) macOS — `projectsOn(host:)` treats nil-host checkouts as local: `return c.host.map(MacSelfHost.isThisMac) ?? true` (MacMachinesView.swift:184), so the deleted VPS's checkout appears under "This Mac"; opening it goes down the local branch of `open(project:checkout:)` (ShioMacApp.swift:283-296) and starts a local tmux in the remote machine's path.

**Suggested fix:** On host delete, also delete (or prompt to reassign) the host's checkouts (`host.checkouts`), and make `Repo.activeCheckout`/`openOrCreate` skip nil-host checkouts in favor of a live one, surfacing an error when none exists.

<details><summary>Verifier notes</summary>

Every link in the claimed chain reproduces from the code. (1) Host deletion is bare at all three cited sites (HostListView.swift:141-144, MacMachinesView.swift:196-200, IPadRootView.swift:58-61) and Host.checkouts uses .nullify (Host.swift:94-95) — Host.swift:83 even documents "Deleting a host orphans its projects." No code anywhere deletes or reassigns orphaned checkouts: a grep of all context.delete sites finds none, and ProjectMigration.reconcile (ProjectMigration.swift:94-114) only collapses duplicate (host,path) checkouts, keeping nil-host orphans. (2) iOS: Repo.activeCheckout (Repo.swift:49-53) sorts only by lastOpenedAt with no host-validity check, so the orphan (most recently opened) shadows any live checkout; SessionStore.openOrCreate(repo:) (SessionStore.swift:101) guards `let host = checkout.host else { return nil }`, and ProjectsView.openRepo (ProjectsView.swift:97-102) silently drops the nil — tapping the repo does nothing, no error. The only recovery is a hidden context menu ("Open on", ProjectOverviewView.swift:277-287) that appears only with >1 checkouts and lists the orphan as "Unknown"; a single-checkout repo has no recovery. (3) macOS: MacMachinesView.swift:184 `c.host.map(MacSelfHost.isThisMac) ?? true` classifies nil-host checkouts as This Mac (display-only list — the claim slightly overstates that surface), but the real harm is the open path: MacProjectsView.swift:132/197 → ShioMacApp.open(repo:) (256-273) / open(project:checkout:) (277-297) fall into the local branch on nil host and launch MacLocalProjectSession with the remote checkout's path; MacLocalLaunch.forProject (MacLocalSession.swift:34) will even `git clone "$SHIO_CLONE" "$SHIO_DIR"` locally if the dir is missing — a local tmux (or fresh local clone) at the dead VPS's path instead of an error. The nil-host local fallback was intended for legacy host-less projects (ShioMacApp.swift:281 comment) but accidentally swallows deletion orphans. Severity: host removal is first-class shipped UI on all three surfaces and the result silently breaks the core open-project flow (iOS) or does the actively wrong thing (Mac); not a blocker since it needs the delete precondition and re-adding the project recovers — high is correct.
</details>


#### CK-3 · `medium` · SkillEditor's Delete button skips file cleanup that the context-menu Remove performs; deleted skills are never removed from remote machines at all

`Shio/Features/Skills/SkillsLibraryView.swift:186` · confidence high · platform all

The library context menu does `SkillMaterializer.shared.removeGlobalLocally(dirName: skill.dirName); context.delete(skill)` (SkillsLibraryView.swift:101-104), but SkillEditor's Delete does only `if let skill { context.delete(skill); try? context.save() }` (SkillsLibraryView.swift:186-188) — no removeGlobalLocally, no scheduleGlobalSync. The canonical `~/.agents/skills/<dir>/SKILL.md` and tool symlinks stay on the Mac and the agent keeps obeying a rule the user deleted; since the record is gone, no future sync can remove it (SkillMaterializer.swift:86-87: "the record is gone, so the sync can't reach it"). Additionally, removeGlobalLocally is `#if os(macOS)` local-only (lines 88-93) — neither delete path ever removes the skill from REMOTE machines, so deleting a skill from the phone leaves it active on every remote box forever.

**Suggested fix:** Call removeGlobalLocally(dirName:) from SkillEditor.delete() too, and add a remote tombstone pass (e.g. capture dirName before delete and run the writeRemote disable branch against known hosts).


#### CK-4 · `medium` · Renaming a skill orphans its old materialized directory — agents follow both the old and new rule

`Shio/Features/Skills/SkillsLibraryView.swift:177` · confidence high · platform all

`Skill.dirName` is derived from `name` (Skill.swift:48-55). SkillEditor.save() mutates the name in place (`skill.name = n`, SkillsLibraryView.swift:177) and calls `scheduleGlobalSync()`, but syncGlobalsLocal only iterates the *current* items (SkillMaterializer.swift:141-162) — it never reconciles the skills directory against the store, so the previous `~/.agents/skills/<old-dir>/` (plus its tool symlinks, plus remote copies) survives indefinitely. The agent then loads two copies of the rule, one stale.

**Suggested fix:** Capture the old dirName before saving and remove it (local + remote) when it changes, or have syncGlobalsLocal delete subdirectories of ~/.agents/skills that don't match any current skill's dirName (it owns that canonical dir).


#### CK-5 · `medium` · host.lastConnectedAt is never stamped on iOS, so iPhone-only machines read as permanently asleep and never warm

`Shio/Features/Terminal/SessionStore.swift:131` · confidence high · platform ios

All assignments are in the Mac target only: MacMachinesView.swift:191, MacShell.swift:204, CommandPalette.swift:192 (`host.lastConnectedAt = .now`); grep finds no assignment anywhere in Shio/ (iOS + shared core), including the SSH connect path. For a host the user only ever reaches from the iPhone (a VPS added on the phone — a headline use case): HostListView's reachability dot is permanently dim (`guard let last = host.lastConnectedAt else { return false }`, HostListView.swift:152), MacMachinesView.reach shows it asleep on the synced Mac (line 213), and ProjectStatusStore.isWarm is always false (ProjectStatusStore.swift:262-265) so the Mac's 20s warmOnly refresh timer (MacProjectsView.swift:51-52) permanently skips that machine's checkouts.

**Suggested fix:** Stamp host.lastConnectedAt (on the main actor) after a successful SSH connect in the iOS session path, mirroring what MacShell.swift:204 does.


#### CK-6 · `medium` · reconcile() tie-breaks duplicate checkouts on identical createdAt — two devices can each delete the other's copy, losing both

`Shio/Core/Profiles/ProjectMigration.swift:102` · confidence medium · platform all

backfillCheckouts copies the project's timestamp onto the new checkout: `checkout.createdAt = project.createdAt` (ProjectMigration.swift:79). So when two devices both backfill the same legacy project, the two duplicate checkouts have byte-identical createdAt. reconcile() keeps "the oldest by createdAt" via `checkouts.sorted(by: { $0.createdAt < $1.createdAt })` (line 102) — an unstable sort with equal keys, so which copy survives is nondeterministic and can differ per device. Device A keeps cA/deletes cB while device B keeps cB/deletes cA; CloudKit merges both deletions and the project ends up with zero checkouts (recreated from legacy host/path next launch for the primary repo, but checkouts added via `addRepo` have no legacy fallback — Project.swift:139-150 never populates the legacy path/host).

**Suggested fix:** Break ties deterministically — e.g. sort by (createdAt, a stable per-record key like the CloudKit record name / a stored UUID) — so every device keeps the same survivor.


#### CK-7 · `medium` · Deleting a Project silently promotes its project-scoped Skills to global and fans them out to every machine

`Shio/Features/Projects/ProjectsView.swift:118` · confidence medium · platform all

Skill scope is `nil = global` (Skill.swift:31, `var isGlobal: Bool { project == nil }` line 44) and `Project.skills` uses `.nullify` — the comment says "removing a project leaves its skills as globals" (Project.swift:38-41). Combined with the materializer, deletion is an escalation: the next `scheduleGlobalSync()`/project open fetches `all.filter(\.isGlobal)` (SkillMaterializer.swift:68-71) and writes the ex-project rules into `~/.agents/skills` plus symlinks into ~/.claude, ~/.cursor, ~/.codex on the Mac (lines 141-162) and onto every remote machine on project open (lines 108-116) — a rule that was scoped to one deleted project now silently governs every agent everywhere. The already-materialized copies in the deleted project's checkout `.claude/skills` dirs are also never cleaned (ProjectsView.swift:118-121 and MacProjectsView.swift:184-189 just `context.delete(project)`).

**Suggested fix:** On project delete, either delete the project's skills (after confirmation) or keep them but disabled; at minimum never auto-promote to global — e.g. set `enabled = false` when nullifying scope.


#### CK-8 · `low` · Project delete leaks orphaned Repo/ProjectCheckout records that sync forever

`Shio/Features/Projects/ProjectsView.swift:119` · confidence high · platform all

Project deletion is bare (`context.delete(project)`, ProjectsView.swift:119 and MacProjectsView.swift:186) and all relationships are `.nullify` (Project.swift:33, Repo.swift:35), so the project's Repos and their ProjectCheckouts survive with `project == nil` — unreachable from any UI (all views drive off `@Query<Project>`) but permanently stored and mirrored to CloudKit on every device. Repeated add/delete cycles accumulate dead records in the user's private DB.

**Suggested fix:** When deleting a project, explicitly delete its repos and each repo's checkouts first (manual cascade, since CloudKit forbids .cascade).


#### CK-9 · `low` · Pull-to-refresh's only real job (flushing pending writes) swallows save failures

`Shio/Core/Profiles/SyncRefresh.swift:16` · confidence high · platform all

SyncRefresh.run is documented as "flush local pending writes (save) so they export to CloudKit promptly" but does `try? context.save()` (SyncRefresh.swift:16) — if the save throws, the gesture still spins for 700ms and reads as success while nothing was exported. The same `try? context.save()` pattern silently drops user edits in SkillsLibraryView.swift:84/103/181, ProjectsView.swift:120, and ProjectMigration.swift:54/84/113 (the migration case is benign — it retries next launch — but the UI cases lose the edit without feedback).

**Suggested fix:** In SyncRefresh at least, catch the save error and surface it (the Settings sync-status row already exists for this kind of message).


#### CK-10 · `low` · Skill import dedup is device-local only — concurrent imports on two devices create duplicate Skills with no reconciler, and duplicates fight over one file

`Shio/Core/Skills/SkillImporter.swift:42` · confidence medium · platform all

SkillImporter.upsertGlobals dedups against the local store at import time only (`var existing = Set(...map { $0.name.lowercased() })`, SkillImporter.swift:42-47). Two devices importing the same dotfiles (synced ~/.claude across machines is common for this audience) before CloudKit converges produce duplicate global Skill records; unlike checkouts (ProjectMigration.reconcile) there is no Skill reconciler. Duplicates share the same `dirName`, so once one twin is disabled and the other enabled, syncGlobalsLocal both removes and rewrites the same directory in unspecified fetch order (SkillMaterializer.swift:145-160) — whether the SKILL.md exists after a sync is nondeterministic.

**Suggested fix:** Add a launch-time Skill dedup (collapse same-name globals, keep oldest) mirroring the checkout reconciler, or key dedup on a synced identity rather than local presence.


#### CK-11 · `low` · MacSelfHost.ensure adopts unstamped Host records by computer name — a second same-named Mac can steal the record pairing created for the first

`ShioMac/MacSelfHost.swift:53` · confidence medium · platform mac

ensure() claims any record with `$0.deviceID == nil && $0.name.caseInsensitiveCompare(computerName) == .orderedSame` (MacSelfHost.swift:53-56), stamps it with its own deviceID (lines 61-63), then overwrites name/hostname/username (lines 80-82) and re-points the dup's projects/checkouts (lines 74-78). The file's own comment (lines 23-27) notes two Macs both default to "MacBook-Pro" — exactly that setup makes Mac B adopt the unstamped host the phone QR-paired for Mac A, rewriting its hostname to Mac B's address and re-routing Mac A's checkouts. isThisMac was hardened to deviceID-only, but this adoption path still keys on the colliding name.

**Suggested fix:** Only adopt unstamped records that match on something machine-specific (e.g. hostname equals one of this Mac's current addresses/MagicDNS name) in addition to the name, or skip adoption when another Mac's stamped record with the same name exists.


### Status engine (git / PRs / writes) (ST)

**Dimension summary:** The status engine's read core is genuinely solid: the porcelain-v2 parser handles renames, conflicts, detached/unborn HEAD, and space/leading-space filenames correctly (verified against real `git status --porcelain=v2 --branch -z` byte output), and shell quoting in the batched script and GitWriter is injection-safe for POSIX shells. The weak layer is everything around result interpretation and refresh orchestration: GitWriter can report false success on remote failures (stderr dropped + exit code ignored + timeout-returns-partial in SSHClient.exec) and false failure from commit-message text; ProjectStatusStore's cancel-everything refresh races drop cold-host results; iOS has no refresh cadence at all so the needs-you/approve loop visibly never updates; and isStale() is dead code so week-old disk-cached data renders as fresh. Remote agent state is also wiped on transient failures and missed entirely for project-level/indexed tmux sessions, weakening the supervision hero flow the engine exists to serve.


#### ST-1 · `high` · GitWriter reports false 'Committed and pushed.' on remote failures — stderr dropped, exit code ignored, timeout returns partial output

`Shio/Core/Status/GitWriter.swift:21` · confidence high · platform all · **verified real**

GitWriter.swift:21 only redirects the push step: `git -C \(p) add -A && git -C \(p) commit -m \(shellQuote(message)) && git -C \(p) push 2>&1` — stderr of `add`/`commit` is not redirected. Over SSH, SSHClient.swift's ExecCollector explicitly drops stderr (SSHClient.swift:520 "stderr is dropped", :532 `guard channelData.type == .channel else { return }   // stdout only`) and never reads the exit status (no userInboundEventTriggered handler). GitWriter.swift:49-58 `interpret(_:)` is purely textual: an empty output returns `.ok("Committed and pushed.")`. So a remote `git commit` that fails with a stderr-only fatal (e.g. "fatal: unable to auto-detect email address", "fatal: detected dubious ownership", index.lock held) produces empty stdout → the user is told the commit and push succeeded when nothing happened. Additionally SSHClient.swift:286-289: "Timeout closes the channel → EOF → the collector succeeds with whatever stdout arrived" — a push hanging past the 40s timeout (GitWriter.swift:31) returns just the commit summary line → also interpreted as `.ok`. Local Mac is partially protected (GitWriter.swift:68-70 merges both pipes) but `p.terminationStatus` is never read there either.

**Suggested fix:** Adopt the GitStatusReader pattern: wrap the whole compound in `{ ...; } 2>&1; printf '<MARKER>%d' "$?"`, parse the exit code, and treat a missing marker (timeout/truncation) as failure.

<details><summary>Verifier notes</summary>

Every cited line verifies. GitWriter.swift:21 redirects only the push step's stderr ('git add ... && git commit ... && git push 2>&1' — redirection binds to the last simple command). Over SSH, ExecCollector (SSHClient.swift:521-546) explicitly drops stderr (line 520 comment 'stderr is dropped'; line 532 'guard channelData.type == .channel else { return } // stdout only') and the codebase has zero userInboundEventTriggered/ExitStatus handlers, so the remote exit code is never read. interpret() (GitWriter.swift:49-58) is purely textual and returns .ok("Committed and pushed.") on empty output. Therefore a remote add/commit failure that writes only to stderr (no user.email, dubious ownership, index.lock held — the last being realistic when an agent is concurrently active in the repo, Shio's hero use case) yields empty stdout and a green false-success in CommitSheet (CommitSheet.swift:78), which is shipped on both iOS (ProjectOverviewView.swift:105) and Mac (MacProjectsView.swift:356). The timeout path also verifies: SSHClient.swift:286-290 closes the channel on the 40s timeout and the collector succeeds with partial stdout, so a hung push returns the commit summary and is reported .ok. Refutation attempts failed: common push failures are caught textually (push has 2>&1 and git prints fatal:/error:/rejected), but that does not cover add/commit stderr or >40s hangs; no second verification layer exists; and GitStatusReader.swift:64-69 already uses the exit-code marker pattern ('printf exMarker%d "$?"'), confirming the exec layer is known not to carry exit codes — GitWriter just didn't adopt it. Local Mac path merges pipes (GitWriter.swift:68-74) so it is mostly protected textually, though terminationStatus is indeed never read. Severity high is right: a false 'Committed and pushed.' is a real correctness bug in a shipped core flow (git writes, P7), not merely a cosmetic or unreachable edge case.
</details>


#### ST-2 · `high` · iOS never refreshes status while visible — no 20s timer, no foreground refresh; needs-you card never clears after Approve

`Shio/Features/Projects/ProjectOverviewView.swift:117` · confidence high · platform ios · **verified real**

The 20s visible-only timer exists only on Mac (MacProjectsView.swift:47-54 `.task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(20)) ... } }`). On iOS the only refresh triggers are ProjectsView.swift:93 `.onAppear { refreshStatus() }`, the pull-to-refresh at :65, and ProjectOverviewView.swift:117-121 `.onAppear`. ShioApp.swift:42-57's scenePhase handler only reconnects sessions/Live Activities — no status refresh on foregrounding. Consequence: ProjectOverviewView.swift:160-161 documents "The card clears itself on the next status refresh" for the in-app Approve/Deny — but while the dashboard stays on screen no refresh ever fires, so after tapping Approve the needs-you card persists indefinitely (until the user navigates away and back), remote agent badges and git lines freeze, and returning from background shows frozen data. For the supervision-first iPhone hero surface this is a shipped-path robustness gap.

**Suggested fix:** Add the same 20s visible-only `.task` loop to ProjectsView/ProjectOverviewView (warmOnly), plus a refresh on scenePhase → .active.

<details><summary>Verifier notes</summary>

Verified every element of the claim against the code. (1) The 20s visible-only refresh loop exists only on Mac (ShioMac/MacProjectsView.swift:47-54); exhaustive grep of the iOS target shows the only status-refresh triggers are ProjectsView.swift:93 onAppear, ProjectsView.swift:65-66 pull-to-refresh (root list only), and ProjectOverviewView.swift:117-121 onAppear — no timer anywhere. (2) ShioApp.swift:50-56 scenePhase->.active only calls SessionStore.reconnectActiveOnForeground() + reconcileLiveActivities(); no status refresh, and onAppear does not re-fire on foregrounding, so dashboard data freezes after backgrounding. (3) The Approve/Deny needs-you card is exclusively the remote-agent path (ProjectOverviewView.swift:150-151 sets sessionTmux only for remote agents), driven by status.remoteAgent (:147), which reads ProjectStatusStore.remoteAgents — mutated only inside run() during a refresh (ProjectStatusStore.swift:172). No TTL: isStale (ProjectStatusStore.swift:62) is defined but never consumed by any view. answer() (:162-164) just writes a CloudKit Action with no local state change; the code's own comment (:160-161) concedes "The card clears itself on the next status refresh" — which never fires while the dashboard stays on screen, and ProjectOverviewView's ScrollView has no .refreshable. (4) Push arrival (CloudKitSignalService.handleNotification:87-100) only posts shioConnectToHost, and the Mac fires signals only on the not-waiting->waiting edge, so nothing clears the card from the outside. Consequence chain holds: after in-app Approve the card and the "needs you" glance persist indefinitely, git/agent data freezes while visible and after foregrounding; an aggravator is that re-tapping Approve queues a second Action record that the Mac (which polls only while an agent is waiting) will inject as a stray auto-"y" at the next prompt. Severity: high is correct — it is the shipped iPhone hero supervision flow with broken primary-action feedback, but not a blocker since the keystroke is delivered and navigating away/back or pull-to-refresh on the list recovers the UI.
</details>


#### ST-3 · `medium` · isStale() is dead code — week-old cached status renders identically to fresh data on every surface

`Shio/Core/Status/ProjectStatusStore.swift:62` · confidence high · platform all

ProjectStatusStore.swift:62 defines `func isStale(_ cached: Cached, maxAge: TimeInterval = 90)` and its doc (:60-61) promises "surfaces decide how loudly to say so (a dimmed dot, a '·· ' prefix)" — but a repo-wide grep finds zero call sites. The disk cache loads `.ok` probes up to 7 days old (ProjectStatusStore.swift:49-50), GitLineModel has no staleness state (GitLine.swift:7), and both MacProjectsView.gitLine (MacProjectsView.swift:587-618) and ProjectOverviewView.gitLine (:295-322) render a cached probe exactly like a live one. Compounding: warm-host gating skips any host not connected in 10 min (ProjectStatusStore.swift:262-265, stamped only by Mac session opens — MacShell.swift:204, MacMachinesView.swift:191), and transient failures deliberately keep the last good payload (:176-180) — so branch/dirty counts can be hours-to-days old with zero indication.

**Suggested fix:** Surface `fetchedAt` through GitLineModel (e.g. a `stale: Bool`) and render the promised dimmed treatment in both dashboards.


#### ST-4 · `medium` · refresh() cancels any in-flight refresh regardless of target overlap — cold-host results silently dropped by the warm-only timer or a narrower refresh

`Shio/Core/Status/ProjectStatusStore.swift:146` · confidence high · platform all

ProjectStatusStore.swift:146-151: `func refresh(_ targets: [Target]) { inFlight?.cancel(); ... inFlight = Task ... }`, and run() drops results once cancelled (:169 `if !Task.isCancelled`). The Mac 20s timer (MacProjectsView.swift:47-54) refreshes warmOnly; a user-initiated full refresh (rail click → MacProjectsView.swift:200-204, or onAppear) probing a cold remote host takes up to ~8s (exec timeout, GitStatusReader.swift:44) — if a timer tick lands in that window it cancels the full refresh, and the replacement warm-only set excludes the cold host, so its probe results never land (status stays "—"). Same on iOS: navigating list → dashboard fires ProjectOverviewView.swift:119 `status.refresh(targets for [project])`, cancelling the list-wide refresh from ProjectsView.swift:127 and discarding all other projects' pending results. Note also :147-148 cancels in-flight even when the new target list is empty.

**Suggested fix:** Only cancel in-flight work when the new target set covers the old one (or key in-flight probes per hostKey and let disjoint groups complete).


#### ST-5 · `medium` · Remote agents wiped on transient probe failure/timeout — needs-you signal cleared while git statuses are preserved

`Shio/Core/Status/ProjectStatusStore.swift:172` · confidence high · platform all

ProjectStatusStore.swift:171-173: `remoteAgents[hostKey] = result.agents   // replace: empty clears stale agents` — but GitStatusReader.swift:53-57's catch path returns `([:paths → unreachable], [:])`, so one failed SSH connect replaces the host's agent map with empty. Also the agent capture is the LAST block of the batched script (GitStatusReader.swift:69-81), so an 8s exec timeout truncates agents first while git bodies may survive. This is the opposite bias from git statuses, where transient failures deliberately keep last-good data (:176-180, "Never discard a good status for a transient failure"). Net effect: a network blip or slow host clears a waiting agent's needs-you card/badge until the next successful refresh — which on iOS requires re-navigation (see the no-timer finding).

**Suggested fix:** Skip the `remoteAgents[hostKey]` replacement when the probe failed (e.g. return agents as Optional and only replace on a successful round trip).


#### ST-6 · `medium` · Remote-agent lookup misses project-level and indexed tmux sessions (key mismatch with session naming)

`Shio/Core/Status/ProjectStatusStore.swift:92` · confidence high · platform all

ProjectStatusStore.swift:91-93 looks up only `remoteAgents[host]?["shio-\(TmuxResume.scrubName(repoName))"]`, and ProjectOverviewView.swift:147 likewise iterates repos only. But sessions are created as `shio-<project.name>` for project-level opens (ShioMacApp.swift:285 `named: "shio-\(TmuxResume.scrubName(project.name))"`; SessionStore.swift:164 `let base = repoName ?? project.name`) and as `shio-<name>-<index>` for second+ sessions (SessionStore.swift:166). The status fetch captures ALL `shio-*` panes (GitStatusReader.swift:74 `grep '^shio-'`), so the agent is detected but never surfaced: for a multi-repo project whose name differs from its repo names (the flagship "Shio = app + landing + worker" shape) or any secondary session, a waiting agent on another machine is invisible in the dashboard/needs-you list.

**Suggested fix:** Match by prefix (`shio-<scrubbed>` and `shio-<scrubbed>-N`) and also try the project-name key when aggregating a project's agents.


#### ST-7 · `medium` · GitWriter.interpret false failure when the commit message itself contains 'error:'/'fatal:'/'rejected'

`Shio/Core/Status/GitWriter.swift:55` · confidence high · platform all

GitWriter.swift:55-57: `if lower.contains("fatal:") || lower.contains("error:") || lower.contains("rejected") { return .failed(...) }`. `git commit` echoes the message's first line to stdout (e.g. `[main 1a2b3c4] Fix rejected promise handling` or `[main ...] handle error: nil host`), so a fully successful commit+push is reported as failed in the CommitSheet (CommitSheet.swift:79 shows it in red), likely prompting the user to retry — and the retry then fails with "Nothing to commit", compounding the confusion. Realistic trigger for an audience writing commit messages about errors/rejections.

**Suggested fix:** Decide success from the actual exit code (see the marker-based fix in the stderr/exit finding) and keep text only for display.


#### ST-8 · `medium` · Batched status script is POSIX-only but executes in the remote user's login shell — breaks entirely on fish/tcsh hosts

`Shio/Core/Status/GitStatusReader.swift:60` · confidence medium · platform all

GitStatusReader.remoteScript (GitStatusReader.swift:60-81) uses `|| { printf ...; }`, `printf ... "$?"`, `if ...; then ... fi`, and `while IFS= read -r s; do ... done` — sshd runs exec commands via the user's login shell (`$SHELL -c`). fish rejects `$?` ("$? is not the exit status") and `{ }` blocks as parse errors and aborts the whole -c script, so every checkout on a fish-login-shell host yields no markers → all paths become `.timedOut` (GitStatusReader.swift:51) and render as "—"/unreachable forever. tcsh similarly breaks on `2>/dev/null`. GitWriter's and GitHubReader's simpler `&&` commands survive fish, making the status engine the only thing mysteriously dead on such hosts. Quoting itself (shellQuote, :100-102) is injection-safe; this is a shell-dialect issue, not injection.

**Suggested fix:** Pin POSIX by wrapping the batch as `sh -c '<script>'` (one extra shellQuote layer) or `exec sh <<'EOF' ... EOF`.


#### ST-9 · `low` · git exit 128 universally mapped to .notARepo — dubious-ownership and other fatal errors render as 'not a repo'

`Shio/Core/Status/GitStatusReader.swift:125` · confidence high · platform all

GitStatusReader.swift:121-127: `case 128: return .notARepo          // fatal: not a git repository (the common case)`. git exits 128 for every fatal error, notably "fatal: detected dubious ownership in repository" (common for repos on external volumes or owned by another user over SSH), corrupt objects, and bad config. GitLine.swift:33-34 then renders the branch as "not a repo" — a misdiagnosis the user may act on. stderr is discarded (`2>/dev/null` at GitStatusReader.swift:65), so there is no signal to disambiguate.

**Suggested fix:** Capture a stderr tail per block (e.g. `2>&1 >/dev/null | tail -c 200` into a separate marker) and only map to .notARepo when it matches "not a git repository".


#### ST-10 · `low` · Local Mac probes have no timeout and an unread stderr pipe — one hung repo blocks all local statuses and leaks threads

`Shio/Core/Status/GitStatusReader.swift:146` · confidence high · platform mac

GitStatusReader.swift:146-167 `runLocalGitSync`: `process.standardError = Pipe()` is never drained and `stdout.fileHandleForReading.readDataToEndOfFile()` + `process.waitUntilExit()` have no deadline (remote probes get 8s, GitStatusReader.swift:44). A git that blocks (repo on a disconnected SMB/NFS mount, or >64KB of stderr filling the unread pipe) hangs the probe forever; probeLocal is serial (:132-135 `for path in paths { out[path] = await runLocalGit(at: path) }`) so every local checkout behind it never updates, and each 20s timer tick parks another blocked global-queue thread (the cancelled task's continuation never resumes).

**Suggested fix:** Drain stderr (or set it to FileHandle.nullDevice) and add a kill-after-N-seconds watchdog mirroring the remote 8s timeout.


#### ST-11 · `low` · PR lists discarded on transient failure and absent from the disk cache — PR chips flicker out, and gh-missing/not-authed is indistinguishable from zero PRs

`Shio/Core/Status/ProjectStatusStore.swift:126` · confidence high · platform all

ProjectStatusStore.swift:126 `if !Task.isCancelled { prs[key] = list }` unconditionally overwrites with `[]` whenever the fetch fails (GitHubReader.swift:32-35 catch → `return []`; :25 `2>/dev/null || true` swallows not-authed), unlike git statuses which keep last-good on transient failure (:176-180). saveDiskCache persists only `statuses` (:55), so PR chips also vanish on every cold launch until gh answers. The swallow-everything behavior is documented as deliberate (GitHubReader.swift:7-8 "all degrade to 'no PRs', never an error") but it is inconsistent with the cache-first promise on the same dashboard rows (MacProjectsView.swift:554, ProjectOverviewView.swift:298).

**Suggested fix:** Keep the previous list on failure (have fetchPRs return Optional and only assign non-nil), and consider persisting prs alongside statuses.


#### ST-12 · `low` · CommitSheet never triggers a status refresh after a successful push — dirty badge lingers

`Shio/Core/Design/CommitSheet.swift:11` · confidence high · platform all

CommitSheet.swift:11 `var onCommitted: () -> Void = {}` and :78 calls it on `.ok`, but no caller passes it (MacProjectsView.swift:356-357 and ProjectOverviewView.swift:105-106 construct CommitSheet without onCommitted; repo-wide grep confirms). After a successful commit+push the repo row keeps showing the warning dot/dirty count — on Mac until the next 20s warm tick, on iOS until the user re-navigates (no timer) — undermining confidence that the push worked.

**Suggested fix:** Pass onCommitted from both call sites to re-run status.refresh for that checkout's target.


#### ST-13 · `low` · Claimed '19 unit tests' for GitStatus.parse do not exist in the repo — no test target at all

`project.yml:40` · confidence high · platform all

SHIO_STATE_OF_THE_UNION.md:65 claims "`GitStatus.parse(...)` (porcelain-v2, 19 unit tests)", but `find` over repo sources (excluding build/SourcePackages) shows zero files referencing `porcelainV2`/`GitStatus.parse` outside Shio/Core/Status, and project.yml defines no test target. The parser is currently correct (I verified rename ordering, NUL-terminated headers, and leading/double-space filenames against real `git status --porcelain=v2 --branch -z` output), but it has no regression guard despite the handoff doc implying one.

**Suggested fix:** Add a unit-test target with the porcelain-v2 fixtures (rename, conflict, detached, unborn, spaces, truncation) — or correct the handoff doc.


### Agent detection, remote control & away-push (AG)

**Dimension summary:** The away-push approve loop (Mac detects waiting → Signal → CloudKit banner → lock-screen Approve → Action → tmux inject) is genuinely wired end-to-end and the permission fix in sendTestPush is correctly connected — but the surrounding half of the story has real holes: nothing in the app (and nothing in git history, ever) observes .shioConnectToHost, so push-tap deep-links, the Connect App Intent, Handoff, and shio:// URLs are all silent no-ops, and the Mac's Signal carries an empty hostId anyway. The Action channel has concrete replay/double-injection races (orphaned records, swallowed delete failures, overlapping polls, no per-session waiting re-check), and the AgentDetector's waiting-takes-priority substring matching inverts its own stated false-positive bias. The menu-bar watcher lifecycle itself is clean (start() is idempotent via the timer guard; both call sites hit the shared singleton, so no duplicate monitors), but signaledWaiting's in-memory/empty-scan re-arm means duplicate pushes on restart or transient tmux failures, and the UserDefaults-latched subscription flag can silently kill away-push across the Debug→TestFlight environment switch on the very device used for verification.


#### AG-1 · `high` · Nothing observes .shioConnectToHost — push-tap deep-link, App Intent, Handoff, and shio:// URL routing are all dead code

`Shio/Core/Util/ShioNotifications.swift:8` · confidence high · platform ios · **verified real**

Six places post `.shioConnectToHost` (ShioApp.swift:37 and :71 — Handoff + `shio://connect` deep link; CloudKitSignalService.swift:93 — push received; PushService.swift:103 — notification tap, :139 — relay push; ConnectToHostIntent.swift:19 — Siri/App Intent), but no code anywhere observes it. `grep -rn "addObserver|onReceive|publisher(for"` across Shio/ and ShioMac/ finds only OverlayWindow (UIApplication notifications), FileSpotlightSearcher (NSMetadataQuery), and MacAppDelegate (UserDefaults). Git history (`git log -G shioConnectToHost`) shows an observer never existed in any commit. So tapping the away-push banner opens the app but never navigates (SOTU §2 claims "Away-push deep-links here"), the "Connect to host" App Intent silently does nothing, and the Handoff receive path is a no-op. Note also CloudKitSignalService.handleNotification posts on mere foreground *receipt*, not tap — when an observer is added, receipt-vs-tap must be distinguished or the app will jump hosts mid-use.

**Suggested fix:** Add an observer at the app root (e.g. in RootView) that looks up the Host by id and routes to it, wiring tap (userNotificationCenter didReceive) rather than receipt; validate the hostId against synced Hosts and ignore unknown ids.

<details><summary>Verifier notes</summary>

Verified end-to-end. Six call sites post .shioConnectToHost (ShioApp.swift:36-40 Handoff, :71-75 shio://connect deep link, CloudKitSignalService.swift:93-97 push receipt, PushService.swift:103-105 notification tap, :139-143 relay push, ConnectToHostIntent.swift:18-22 Siri intent), but a grep across all four targets for addObserver/onReceive/publisher(for:)/notifications(named:) finds zero observers of it — only OverlayWindow (UIApplication), FileSpotlightSearcher (NSMetadataQuery), and MacAppDelegate (UserDefaults) observe anything. The raw name string "sh.shio.app.connectToHost" appears only in its definition (ShioNotifications.swift:8). A full git-history sweep over every commit confirms an observer never existed. RootView.swift is a plain TabView with no routing, so no alternate mechanism handles the hostId. The code self-documents the gap: ConnectToHostIntent.swift:15-17 says the routing was deferred to a "Brick 11 second pass" that never shipped ("For now we just bring Shio to the front"), and all later posters were wired into that same dead end. Consequence: the away-push banner whose own text promises "Tap to jump back in" (CloudKitSignalService.swift:62) opens the app but never navigates; shio:// URLs, Handoff receive, and the Connect-to-host App Intent are silent no-ops beyond foregrounding the app. The claim's receipt-vs-tap caveat is also correct (handleNotification fires from didReceiveRemoteNotification on receipt, not tap). Severity stays high, not blocker: the lock-screen Approve/Deny loop works independently (sendAction path, verified on device), and a tap still opens the app so the user can navigate manually — but tap-to-jump routing is a real bug in a shipped, advertised path.
</details>


#### AG-2 · `high` · Action channel: stale-action replay, swallowed delete failure, and overlapping polls can double-inject keystrokes

`ShioMac/MacProjectAgentMonitor.swift:60` · confidence high · platform mac · **verified real**

Three compounding races. (1) Orphaned actions replay later: injectPendingActions is gated `guard !signaledWaiting.isEmpty else { return }` (MacProjectAgentMonitor.swift:61) and fireAwaySignals runs first in poll() (line 51-53), so if the agent un-blocks (user answered at the Mac) between the phone's Approve and the next poll, the Action record is never consumed and sits in iCloud indefinitely — it is fetched and injected the NEXT time any agent waits (days later), sending `y Enter` into whatever that pane then shows. The Settings "Create approve channel" probe (SettingsView.swift:194, sessionId "shio-schema-probe") is a guaranteed such orphan. (2) Delete failure swallowed: CloudKitSignalService.swift:152 `if !ids.isEmpty { _ = try? await database.modifyRecords(saving: [], deleting: ids) }` — if the delete fails after the fetch succeeded, the same actions are returned and injected again on the next poll. (3) No in-flight guard: poll() fires every 4s (line 31) and each spawns an async Task; a CloudKit fetch slower than 4s lets two fetchAndClearActions overlap, both returning the same records before either deletes — double `send-keys ... y Enter`, where the second Enter/y lands in the agent's input box as a submitted message. Also, injection never re-verifies that action.sessionId is still .waiting (lines 64-69) — an action for an un-blocked session is injected as long as ANY other session is waiting. Two devices approving simultaneously likewise produce two records, both injected. Shell quoting itself is safe: args go to Process directly (run(), line 106-119), no shell.

**Suggested fix:** In injectPendingActions, fetch unconditionally (drop the signaledWaiting gate or poll a few times after re-arm), delete every fetched record, but only inject actions whose sessionId is currently classified .waiting; add an age cutoff (e.g. creationDate > now-2min) and an in-flight flag so polls never overlap.

<details><summary>Verifier notes</summary>

All three compounding defects verify against the code. (1) Stale replay: /Users/amrith/Shio/ShioMac/MacProjectAgentMonitor.swift:61 gates the ONLY consumer of Action records on `guard !signaledWaiting.isEmpty`, and poll() (lines 51-53) runs fireAwaySignals first, which re-arms signaledWaiting to only-currently-waiting sessions (line 87). An Approve that lands when the agent has already un-blocked (user answered at the Mac, Mac asleep/closed — the menu-bar watcher is opt-in and the lock-screen notification persists, so Approve can be tapped long after the prompt resolved) is never fetched or deleted; grep confirms fetchAndClearActions (CloudKitSignalService.swift:134) is the sole consumer and there is no age cutoff, TTL, or dedupe anywhere. The orphan is injected the NEXT time any agent waits — `tmux send-keys -t <sessionId> y Enter` (lines 64-69) fires unconditionally, never re-verifying that action.sessionId itself is still .waiting. Shio tmux sessions are long-lived by design, so the stale `y Enter` plausibly lands in a live agent pane, silently approving a prompt the user never saw. The Settings probe (SettingsView.swift:194, sessionId "shio-schema-probe") is a confirmed guaranteed orphan, though its injection is harmless (no such tmux session; run() swallows the tmux error). (2) Swallowed delete: CloudKitSignalService.swift:152 is verbatim `if !ids.isEmpty { _ = try? await database.modifyRecords(saving: [], deleting: ids) }` — actions already returned/injected are re-fetched and re-injected next poll if the delete fails. (3) Overlap: the 4s Timer (line 31) spawns a new Task per tick with no in-flight flag; the awaits on scan and fetchAndClearActions are MainActor suspension points, so a CloudKit fetch slower than 4s lets two fetches both return the same records before either delete — double `y Enter`, where the second lands in the agent input as a submitted message. Two devices approving simultaneously likewise write two records, both injected. The shell-quoting-safe caveat is also correct (run(), lines 106-119, passes args to Process directly). Severity: lock-screen approve is a shipped flagship path (P6); injecting unattended keystrokes into live agent sessions is a real correctness/safety bug, not merely exotic — high is right (not blocker: the happy path was device-verified and works in the common case). The proposed fix (unconditional fetch+delete, inject only into currently-.waiting sessions, age cutoff, in-flight guard) addresses all modes.
</details>


#### AG-3 · `high` · UNUserNotificationCenter delegate is set only after an async post-launch hop — lock-screen Approve from a terminated app can be dropped

`Shio/Core/Push/PushService.swift:77` · confidence medium · platform ios · **verified real**

`center.delegate = self` lives in configureNotificationActions() (PushService.swift:77), which is only reached via `registerIfAuthorized()` — called from RootView's `.task` (ShioApp.swift:26) — and only after `await UNUserNotificationCenter.current().notificationSettings()` (PushService.swift:51), an async XPC round trip. Apple requires the delegate be assigned before the app finishes launching; a lock-screen Approve/Deny (non-.foreground actions, PushService.swift:69-72) launches a terminated app in the background, where the SwiftUI `.task` may run late or not at all before the system delivers the response — `userNotificationCenter(_:didReceive:)` is then never called and the approval is silently lost. The known-good end-to-end verification most plausibly ran with the app alive/suspended, which doesn't exercise this path.

**Suggested fix:** Set the notification-center delegate (and call setNotificationCategories) synchronously in ShioAppDelegate.application(_:didFinishLaunchingWithOptions:) — both are safe to do before authorization is known.

<details><summary>Verifier notes</summary>

VERIFIED REAL. (1) PushService.swift:77 (`center.delegate = self`) is the only delegate assignment in the repo; repo-wide grep finds no other UNUserNotificationCenter usage and no application(_:did/willFinishLaunchingWithOptions:) anywhere — ShioAppDelegate (PushService.swift:181-209) only bridges the three remote-notification callbacks. (2) The only launch-time path to line 77 is RootView's .task (ShioApp.swift:26) → registerIfAuthorized(), which runs Haptics.prepare() + ProjectMigration.run() first and then awaits notificationSettings() (PushService.swift:51, async XPC) before configureNotificationActions() at line 58 — so the delegate is set well after didFinishLaunching, violating Apple's documented requirement that it be assigned before launch finishes for apps launched in response to a notification. (3) Approve/Deny (PushService.swift:69-72) lack .foreground, so a lock-screen tap on a terminated app launches it in the BACKGROUND, where the SwiftUI WindowGroup scene may never connect — RootView's .task then never runs and the delegate is never set in that process lifetime, not just set late; the response is dropped. (4) No fallback exists: action responses are delivered only via userNotificationCenter(_:didReceive:); sendAction(sessionId:key:"y") (PushService.swift:97) has no other caller, so the CloudKit Action record is never written and the Mac never injects the keystroke. Failure is silent and the user authenticated (.authenticationRequired) believing the approval landed. (5) The known-good "verified end-to-end" run (SHIO_STATE_OF_THE_UNION.md:80, §8) was done with the app actively launched/foregrounded, so the delegate was already set from a prior activation — it does not exercise the terminated-app path, which is the most likely state in real away usage (iOS jetsams the app over hours). Severity HIGH is correct: lock-screen approve is the hero flow (SHIO_STATE_OF_THE_UNION.md:13, P6 complete at :102) but the bug only manifests from terminated state, so not a full blocker. Proposed fix (set delegate + setNotificationCategories synchronously in didFinishLaunchingWithOptions) is the canonical correct fix and safe before authorization is known.
</details>


#### AG-4 · `medium` · AgentDetector: waiting outranks running and matches bare substrings in an 800-char window — prompt-like text in displayed content fires false away-pushes

`Shio/Core/Agents/AgentDetection.swift:81` · confidence high · platform all

classify() checks waiting before running (AgentDetection.swift:81-86: "Waiting takes priority"), and waitingPrompt() does plain `window.contains(c)` over the last 800 chars for patterns like `"(y/n)"`, `"proceed?"`, `"continue?"`, `"are you sure"` (lines 107-113). Any diff, code listing, doc, or agent prose containing these — e.g. Claude Code displaying a patch to a CLI that prompts `input("Continue? (y/n)")`, or this very file — classifies .waiting even while the live `esc to interrupt` running marker is on screen, and on the Mac that immediately fires a real push (MacProjectAgentMonitor.fireAwaySignals). The stated bias (lines 29-31: "a false 'waiting' ping … is worse than a missed one") is inverted by this ordering. On iOS the effect persists: the stream tail is append-only (SessionViewModel.swift:148-153), so an already-answered prompt keeps the session classified .waiting until ~800 fresh cleaned chars arrive — the needs-you card lingers after you answered, and tapping its Approve then injects `y Enter` into a running agent. Also `window.contains("1. yes")` (line 102) matches any numbered list containing those words, not just a live menu.

**Suggested fix:** Require waiting evidence near the end of the tail (anchor confirmation patterns to the last few lines, as the [y/n]$ regex at line 117 already does), and demote waiting below an active running marker — or require the prompt to be the last non-empty content.


#### AG-5 · `medium` · fireAwaySignals re-fires on Mac app restart and whenever a scan transiently returns empty

`ShioMac/MacProjectAgentMonitor.swift:87` · confidence high · platform mac

`signaledWaiting` is in-memory only (MacProjectAgentMonitor.swift:44), so relaunching ShioMac while an agent is still blocked pushes the phone again for the same block. Worse, line 87 `signaledWaiting = signaledWaiting.filter { snapshots[$0]?.activity == .waiting }` re-arms on ANY scan where the session is missing — and scan() returns empty whenever `tmux list-sessions` transiently fails (run() returns "" on any throw, line 118) or a single capture comes back empty (`guard !pane.isEmpty else { continue }`, line 98), or when classification flickers waiting→running→waiting (see the detector finding). Each such blip = another push for the same block. The opposite direction is safe: an agent that went waiting while the watcher was off gets signaled on the watcher's first poll, since signaledWaiting starts empty.

**Suggested fix:** Persist signaledWaiting (e.g. UserDefaults with timestamps) and only re-arm a session after it has been observed non-waiting for N consecutive successful scans; treat an empty/failed list-sessions result as 'no data' rather than 'nothing waiting'.


#### AG-6 · `medium` · CloudKit subscription latched by a local UserDefaults flag — survives Dev→Prod environment switch and iCloud account changes, silently killing away-push

`Shio/Core/Push/CloudKitSignalService.swift:52` · confidence high · platform ios

ensureSubscription short-circuits on `UserDefaults.standard.bool(forKey: didSubscribeKey)` (CloudKitSignalService.swift:52). The flag is device-local and environment/account-blind: a device that ran a Debug build registered the subscription in CloudKit *Development* (SOTU §8: Debug=Dev, Release=Prod); when the same device upgrades to the TestFlight/Release build, the flag is still true, so the subscription is never created in *Production* — away-push is silently dead on exactly the developer's own device. Same failure if the user signs into a different iCloud account (subscriptions are per-user). Additionally lines 75-78 treat any `.serverRejectedRequest` as success and latch the flag, which can permanently mask a genuine rejection.

**Suggested fix:** Verify instead of latch: call database.fetch(withSubscriptionID:) (cheap) or key the flag by environment + CKContainer userRecordID, and clear it on CKAccountChanged notifications.


#### AG-7 · `medium` · Away-push banner is always the static "A session needs you." — the per-agent title/body written by the Mac are never displayed, so lock-screen Approve is blind

`Shio/Core/Push/CloudKitSignalService.swift:62` · confidence high · platform ios

The subscription sets `info.alertBody = "A session needs you. Tap to jump back in."` (CloudKitSignalService.swift:62); record fields ride only in `desiredKeys` (line 69) which affects the payload, not the displayed text. So the title/body the Mac carefully builds — `"\(snap.agentName ?? "An agent") needs you"` / `snap.detail` (MacProjectAgentMonitor.swift:79-80) — never appear. With two agents blocked on different projects, the user sees two identical banners and Approves whichever, with no way to tell which project/agent/prompt they just authorized. For an action that runs `tmux send-keys ... y`, that's a safety problem, not just polish.

**Suggested fix:** Use alertLocalizationKey/alertLocalizationArgs (e.g. key "%1$@ — %2$@" with args ["title","body"]) so the banner shows the record's own title/body; requires bumping didSubscribeKey to re-register.


#### AG-8 · `medium` · Mac away-signal sends hostId: "" — even once tap-routing exists, Mac-originated pushes can never deep-link

`ShioMac/MacProjectAgentMonitor.swift:83` · confidence high · platform mac

fireAwaySignals calls `sendAgentSignal(hostId: "", sessionId: name, ...)` (MacProjectAgentMonitor.swift:82-83). Every consumer routes exclusively by hostId and treats empty as absent: CloudKitSignalService.handleNotification:92 `if let hostId = ..., !hostId.isEmpty`, PushService didReceive default branch :101 `if let host` (parse() returns nil for empty, :111-115). Nothing routes by sessionId. So for the real production signal (a local Mac agent blocking), a banner tap can never navigate to the right project even after the missing observer (separate finding) is fixed.

**Suggested fix:** Have the Mac include a stable self-host identifier (the synced Host record id for this Mac) in the Signal, or add sessionId-based routing on the phone that maps shio-<repo> back to the project dashboard.


#### AG-9 · `medium` · Test-notification flow: denied permission and the token race both produce a misleading 'capability missing' diagnosis; subscription isn't re-ensured

`Shio/Features/Settings/SettingsView.swift:212` · confidence high · platform ios

The fix itself is wired correctly: sendTestPush → requestAuthorizationAndRegister (SettingsView.swift:203) → prompt → configureNotificationActions + registerForRemoteNotifications (PushService.swift:38-44) → token via ShioAppDelegate:182-187 → didRegister stores it (PushService.swift:120-126). Remaining gaps: (a) requestAuthorizationAndRegister swallows denial — `guard granted else { return }` (PushService.swift:41) — so if the user taps Deny (or previously denied), sendTestPush continues, writes the Signal, and shows "Likely the Push Notifications capability isn't enabled on the sh.shio.app App ID" (SettingsView.swift:212), blaming the wrong cause and never pointing at Settings.app; (b) the acknowledged first-tap race (comment at :204-205) shows the same wrong message because the APNs token hasn't arrived yet — a 1-2s wait/retry on `PushService.shared.deviceToken` would make the first tap truthful; (c) sendTestPush never calls ensureSubscription, so if the launch-time call no-op'd (iCloud unavailable at launch, or the latched-flag bug), the test reports full success ('Signal saved ✓ Push token ✓') yet no banner can ever arrive.

**Suggested fix:** Return the authorization status from requestAuthorizationAndRegister and branch the alert text on denied; poll deviceToken briefly before composing the result; call ensureSubscription() in sendTestPush and report its outcome.


#### AG-10 · `low` · Indexed tmux sessions (shio-<repo>-1) are invisible to the phone's remote-agent lookup and untargetable by the needs-you card

`Shio/Core/Status/ProjectStatusStore.swift:92` · confidence high · platform all

A second concurrent session for a repo is named `shio-<repo>-1` (SessionStore.swift:166). The remote probe captures ALL shio-* panes keyed by real session name (GitStatusReader.swift:74-77), but the lookup only checks the base name: ProjectStatusStore.swift:92 `remoteAgents[...]["shio-\(TmuxResume.scrubName(repoName))"]`, and the needs-you card hardcodes the same base target (ProjectOverviewView.swift:151). Same for the Mac dashboard (MacProjectAgentMonitor.swift:38-40). So an agent blocked in an indexed session never surfaces on the phone or Mac dashboards — yet fireAwaySignals (which iterates the full scan) WILL push for it, and the push's Approve works (sessionId is the real name). Inconsistent: you get the buzz but the in-app card never appears.

**Suggested fix:** Match any session with prefix `shio-<repo>` (optionally `-<n>` suffixed) in remoteAgent/snapshot(forProjectNamed:), carrying the actual session name through to the card's sessionTmux.


#### AG-11 · `low` · Signal records accumulate forever in the user's private database; orphan Actions only die if a later fetch happens to run

`Shio/Core/Push/CloudKitSignalService.swift:108` · confidence high · platform all

sendAgentSignal (CloudKitSignalService.swift:108-116) and sendTestSignal (:163-170) save a Signal per block/test and nothing ever deletes them — they pile up in the user's private DB (and iCloud storage) indefinitely. Actions are deleted only when fetchAndClearActions runs (which is gated on a waiting agent — see the replay finding), so unconsumed approvals linger too. Writes are also `_ = try? await database.save(record)` (:115, :128) — a quota-exceeded or network failure drops the away-push silently with no log at all.

**Suggested fix:** Delete (or set a TTL field and periodically purge) Signal records after a few days — e.g. the Mac cleans up its own old Signals during fetchAndClearActions; log save failures.


#### AG-12 · `low` · send-keys/capture-pane target the session's *active* pane — a mirror device switching tmux windows can misroute an approval keystroke

`ShioMac/MacProjectAgentMonitor.swift:66` · confidence medium · platform mac

Both detection (`tmux capture-pane -p -t name`, MacProjectAgentMonitor.swift:97; same remotely, GitStatusReader.swift:76) and injection (`["send-keys", "-t", action.sessionId, action.key, "Enter"]`, MacProjectAgentMonitor.swift:66-67) address the bare session, i.e. the currently active window/pane. With mirror mode (any device shares the session, TmuxResume.swift:103-107), the active window can change between the waiting classification, the push, and the injected keystroke — `y Enter` then lands in whatever pane is now active (e.g. a shell the user opened in window 2). Also worth noting send-keys is used without `-l`, so the key string is interpreted as a tmux key name — fine for "y"/"n", but a constraint to remember. Shell injection is not possible (Process arg array, no shell; run() at lines 106-119).

**Suggested fix:** Record the pane id (#{pane_id}) at detection time, carry it in the Signal/Action, and send-keys to that pane; or re-verify the active pane still classifies .waiting immediately before injecting.


#### AG-13 · `polish` · Temporary '[shio] push:' diagnostics to remove once away-push is device-confirmed

`Shio/Core/Push/PushService.swift:52` · confidence high · platform ios

Per SOTU §8 these are explicitly temporary. The print("[shio] push: …") set: PushService.swift:52 (`registerIfAuthorized authStatus=…`), PushService.swift:55 (`NOT authorized — skipping registerForRemoteNotifications`), PushService.swift:59 (`calling registerForRemoteNotifications()`), PushService.swift:122 (`✅ APNs token registered \(hex.prefix(8))…` — note this logs a token prefix; fine for debug, shouldn't ship). Related diagnostics that are error-path and arguably worth keeping (or converting to Logger): PushService.swift:129 ('[shio] APNs registration failed'), CloudKitSignalService.swift:79 ('[shio] CloudKit subscribe failed'). Unrelated leftover debug prints also found: AppLock.swift:38,42,47,50, OverlayWindow.swift:76,84, SettingsView.swift:73.

**Suggested fix:** Delete PushService.swift:52,55,59,122 after device confirmation; convert the two error-path prints to os.Logger; sweep the AppLock/OverlayWindow/SettingsView debug prints in the same pass.


#### AG-14 · `polish` · Duplicate "[y/n]" literal in the confirmations list

`Shio/Core/Agents/AgentDetection.swift:111` · confidence high · platform all

AgentDetection.swift:110-112: `"(y/n)", "[y/n]", "(yes/no)", "[y/n]", "press enter to continue"` — "[y/n]" appears twice; harmless but suggests an intended variant (e.g. "[yes/no]") was lost.

**Suggested fix:** Drop the duplicate or replace it with the intended "[yes/no]".


### Skills grounding layer (SK)

**Dimension summary:** The Skills grounding core is sound where it was clearly designed-for: frontmatter generation, base64+single-quote shell quoting (injection-safe), the real-dir clobber guard, and the enable/disable reconcile for skills that still exist as records. The lifecycle edges are where it breaks: rename and delete leave orphaned SKILL.md dirs on disk (delete leaks on every remote machine permanently — there are no tombstones), materialize targets the stale previously-active checkout so multi-repo opens ground the wrong machine, and imported skills never sync back to the real tool dir they came from, silently breaking both the edit-on-phone arc and the enabled⇔file-present invariant. Every failure path (dead host, exec error, denied macOS access) is swallowed with try?/empty catch and nothing is surfaced or retried; the syncEnabled kill switch misses one write path and isn't honored cross-device. Fixes are mostly localized: a dirName tombstone mechanism, stamping lastOpenedAt before materialize, an ownership check on symlinks, and a sentinel-verified remote script would close the bulk of it.


#### SK-1 · `high` · Renaming a skill orphans the old directory on every machine (and import resurrects it)

`Shio/Features/Skills/SkillsLibraryView.swift:177` · confidence high · platform all · **verified real**

SkillEditor.save() (SkillsLibraryView.swift:176-182) does `skill.name = n; ... SkillMaterializer.shared.scheduleGlobalSync()` — nothing records the previous dirName. SkillMaterializer.syncGlobalsLocal (SkillMaterializer.swift:141-162) and writeRemote (180-217) only write/remove dirs for items that currently exist in the model, so after a rename the old `~/.agents/skills/<old>` dir, its tool symlinks, and every remote copy persist forever; the agent now loads BOTH the old and new rule. Worse, the Mac 'Import from this Mac' button (SkillImporter.importLocal scans `.agents/skills` etc., SkillImporter.swift:62) re-imports the stale dir as a brand-new Shio skill, resurrecting the pre-rename version. Same staleness for project-scoped skills in checkout `.claude/skills`.

**Suggested fix:** On rename, capture the old dirName and enqueue a removal Item (enabled:false) for it in the same sync (local + included in the next writeRemote per host), e.g. keep a synced `previousDirNames` list per skill until confirmed cleaned.

<details><summary>Verifier notes</summary>

VERIFIED REAL. Every link in the claimed chain checks out in the code, and I found no countervailing cleanup mechanism anywhere.

1) Rename loses the old dirName. /Users/amrith/Shio/Shio/Features/Skills/SkillsLibraryView.swift:176-182 — `SkillEditor.save()` does `skill.name = n; skill.skillDescription = desc; skill.content = content` then `try? context.save(); SkillMaterializer.shared.scheduleGlobalSync()`. `dirName` is a computed property derived purely from `name` (/Users/amrith/Shio/Shio/Core/Profiles/Skill.swift:48-55), so the rename silently changes the target directory with no record of the old one. The editor's name field is editable in the shipped edit sheet on both platforms (SkillsLibraryView.swift:75 for globals, ShioMac/MacProjectsView.swift:486 for project skills).

2) Sync is item-driven and never sweeps. `syncGlobalsLocal` (/Users/amrith/Shio/Shio/Core/Skills/SkillMaterializer.swift:141-162) iterates only the passed `items`; removal (`try? fm.removeItem(atPath: canonical)`, line 155) happens only for items with `enabled == false` that still exist in the model under their CURRENT dirName. `writeRemote` (lines 180-217) is identical in structure (`rm -rf "$AG/<d>"` only for current disabled items). Neither ever enumerates `~/.agents/skills` (or a tool dir, or a checkout's `.claude/skills`) to delete directories absent from the model — I grepped: the only `contentsOfDirectory` in the skills code is in the importer. So after a rename the old canonical dir, its tool symlinks (`~/.claude/skills/<old>` etc.), and every previously-materialized remote copy persist indefinitely, and the old SKILL.md still carries the old frontmatter name/description — agents scanning those dirs load BOTH the stale and the new rule (conflicting instructions if the content was also edited, which is the common case).

3) Import resurrects the stale skill. `SkillImporter.importLocal` (/Users/amrith/Shio/Shio/Core/Skills/SkillImporter.swift:60-77) scans `.claude/skills`, `.agents/skills`, `.cursor/skills`, `.codex/skills`; `upsertGlobals` (lines 41-54) dedups only against names currently in the model — after a rename the old name is gone from the model, so the orphaned dir is re-inserted as a brand-new global Skill. The UI then immediately calls `scheduleGlobalSync()` (SkillsLibraryView.swift:46), re-materializing the resurrected pre-rename rule, which CloudKit-syncs to all devices and fans back out to every machine on next project open. The same vector exists remotely via `importRemote` (ShioMac/MacMachinesView.swift:24).

4) The only cleanup paths in the codebase are `removeGlobalLocally(dirName:)` (context-menu Remove, current dirName, Mac-local only, SkillsLibraryView.swift:102) and the enabled==false removal — neither covers rename. (Side observation reinforcing the incomplete lifecycle: `SkillEditor.delete()` at SkillsLibraryView.swift:186-188 deletes the record without calling removeGlobalLocally at all, so editor-delete orphans files too.)

Severity: HIGH is fair. Skills is a headline shipped subsystem (the grounding layer), rename is a first-class operation in its CRUD UI, the failure is completely silent, persists on every machine the skill ever reached, degrades agent behavior (duplicate/stale rules), and the advertised import feature turns the orphan into a self-amplifying loop (the stale rule re-enters the synced library and propagates everywhere). Not a blocker — terminal/SSH/supervision core flows are unaffected and skills still materialize, just duplicated/stale.
</details>


#### SK-2 · `high` · Deleting a skill never cleans files on remote machines; the editor's Delete button cleans nothing anywhere

`Shio/Features/Skills/SkillsLibraryView.swift:186` · confidence high · platform all · **verified real**

SkillEditor.delete() (SkillsLibraryView.swift:186-189) is `if let skill { context.delete(skill); try? context.save() }` — no removeGlobalLocally, no remote removal. The context-menu Remove (lines 101-104) does call removeGlobalLocally first, but that is `#if os(macOS)` only (SkillMaterializer.swift:88-93) and only touches THIS Mac. There is no tombstone: materialize() reconciles only skills that still exist as records (SkillMaterializer.swift:104-109, `let all = ... fetch(FetchDescriptor<Skill>())`), so a deleted skill's SKILL.md survives on every other machine forever and agents keep following the deleted rule. Project-scoped skills are worst: deleting one never removes `<checkout>/.claude/skills/<dir>` on any machine, and project skills have no enabled-toggle UI, so deletion is the only lifecycle exit — and it leaks.

**Suggested fix:** Route all deletes through one helper that (a) removes locally, (b) records a synced tombstone (dirName + scope) consumed by materialize()/launch sync on each device until each known host has been cleaned.

<details><summary>Verifier notes</summary>

Verified every element of the claim against the code. (1) SkillEditor.delete() at Shio/Features/Skills/SkillsLibraryView.swift:186-189 is exactly `if let skill { context.delete(skill); try? context.save() }` — no file cleanup local or remote, and this editor is the delete path for both global skills (line 75) and project skills (ShioMac/MacProjectsView.swift:485-486). (2) The context-menu Remove (lines 101-104) does call removeGlobalLocally first, but its body is entirely `#if os(macOS)` (SkillMaterializer.swift:88-93) and only touches the local FileManager — there is no remote removal path for deleted skills anywhere in the codebase (grep for tombstone/removeRemote/cleanup confirms). (3) No tombstone: both reconciliation entry points — globalItems() (SkillMaterializer.swift:69) and materialize() (line 104) — fetch FetchDescriptor<Skill>() and only remove files for records that still exist with enabled==false (lines 122, 192, 204). So disable propagates to every machine but delete propagates to none; a deleted skill's SKILL.md survives in ~/.agents/skills + symlinked tool dirs on every remote host and every other synced device forever. (4) Project skills confirmed worst: Mac dashboard rows (MacProjectsView.swift:489-490) only open the editor, SkillEditor has no enabled toggle, and the global library toggle filters to isGlobal — so the cleanup-free Delete is the ONLY lifecycle exit for project skills, leaving <checkout>/.claude/skills/<dir> on every machine. (5) Aggravating factor beyond the claim: SkillImporter.upsertGlobals (SkillImporter.swift:42-47) dedups only against live records, so a deleted skill's surviving file on any machine gets re-imported on the next scan, resurrecting the deleted skill. Severity: high is right — Skills is a shipped P5 pillar whose promise is cross-machine file materialization; delete silently fails fleet-wide and agents keep following deleted rules. Not a blocker (core terminal/SSH flows unaffected; globals have a disable-before-delete workaround), but no workaround exists for project skills.
</details>


#### SK-3 · `high` · materialize() targets the PREVIOUS active checkout: skills land on the wrong repo/machine when opening a repo

`Shio/Core/Skills/SkillMaterializer.swift:102` · confidence high · platform all · **verified real**

materialize resolves `project.activeRepo?.activeCheckout` (SkillMaterializer.swift:102), where activeRepo/activeCheckout = most-recently-opened (Project.swift:115, Repo.swift extension). But every repo-open call site materializes BEFORE the lastOpenedAt stamp: iOS ProjectsView.openRepo does `materializeSkills(p)` then `sessionStore.openOrCreate(repo:)` which stamps at SessionStore.swift:172-174; Mac dashboard openRepo closure (MacProjectsView.swift:128-132) materializes then `model.open(repo:)` which stamps at ShioMacApp.swift:260-261. So in a multi-repo project (the flagship case — 'Shio = app + landing + worker'), clicking repo B writes the project's skills (and that host's globals) to repo A's checkout/machine, and B's agent runs without grounding until B is opened a second time.

**Suggested fix:** Pass the repo/checkout being opened into materialize (e.g. materialize(project:checkout:)) or stamp lastOpenedAt before calling materialize at every openRepo call site.

<details><summary>Verifier notes</summary>

Verified end-to-end. SkillMaterializer.materialize (Shio/Core/Skills/SkillMaterializer.swift:102) resolves its write target solely from `project.activeRepo?.activeCheckout ?? project.allCheckouts.first`; it has no parameter for the repo being opened. activeRepo/activeCheckout are most-recently-opened by lastOpenedAt (Shio/Core/Profiles/Project.swift:108-115, Shio/Core/Profiles/Repo.swift:49-53). Both per-repo open paths materialize BEFORE the stamp: iOS ProjectsView.openRepo (Shio/Features/Projects/ProjectsView.swift:97-102) calls materializeSkills(p) then openOrCreate(repo:), which stamps only inside createNewSession (Shio/Features/Terminal/SessionStore.swift:172-174) — and not at all when an existing session is reused (SessionStore.swift:102-105); Mac dashboard openRepo closure (ShioMac/MacProjectsView.swift:128-133) materializes then model.open(repo:), which stamps at ShioMac/ShioMacApp.swift:260-262. The machine-switcher (ProjectOverviewView.swift:283) stamps only the checkout, not the repo, so it doesn't save the multi-repo case. No other code path writes project skills or remote globals (scheduleGlobalSync is Mac-local globals only). So in a multi-repo project — the documented flagship shape — opening repo B writes the project's skills and the host globals to the PREVIOUSLY active repo A's checkout/host (an unsolicited SSH to a possibly different/dead machine), B's checkout gets nothing, and B's agent runs ungrounded until B is opened a second time; disabled-skill removals also target the stale checkout. Mitigations keep it below blocker: single-repo projects are unaffected, project-level opens are internally consistent (both resolve via activeRepo), freshly added repos are stamped at creation (Project.swift:143), and it self-heals on the second open. High is the right severity: a shipped headline feature (P5 grounding) silently writes to the wrong machine on the primary dashboard open path in the product's flagship multi-repo scenario. Proposed fix (pass repo/checkout into materialize, or stamp lastOpenedAt before materializing) is sound.
</details>


#### SK-4 · `high` · Imported skills never sync back to the tool dir they came from: edits and disables silently don't reach the agent

`Shio/Core/Skills/SkillMaterializer.swift:167` · confidence high · platform all · **verified real**

When a skill is imported from an existing REAL dir (e.g. `~/.claude/skills/foo/`), fan-out refuses to replace it: linkLocal `else if fm.fileExists(atPath: link) { return } // a REAL dir/file — never clobber` (SkillMaterializer.swift:167); remote equivalent `if [ -L "$T" ] || [ ! -e "$T" ]` (line 189). Correct as a clobber guard, but it means: (1) edits made in Shio land only in `~/.agents/skills` while Claude Code keeps reading the stale original in `~/.claude/skills/foo` — the headline 'edit on your phone, it lands on every box' flow silently no-ops for every imported skill on its source machine; (2) disabling removes only the canonical dir and symlinks (lines 154-159, remote 192-194: `[ -L "$T" ] && rm -f`), so the real `~/.claude/skills/foo` survives and the agent keeps following a rule Shio shows as off — the `enabled ⇔ file present` invariant breaks in both directions. Also note disable does `rm -rf "$AG/<d>"` / removeItem on the canonical dir, which deletes any auxiliary files (scripts/, references/) a user kept there.

**Suggested fix:** On import (or first materialize), detect a real same-named dir in a tool folder and either adopt it (move to canonical + leave a symlink, with user consent) or mark the skill 'externally managed' and surface that edits/disable won't apply to that machine's tool dir.

<details><summary>Verifier notes</summary>

Verified end-to-end in code. (1) Import is read-only: SkillImporter.importLocal (SkillImporter.swift:60-77) and importRemote (:88-112) never touch the source dir, and both are in shipped UI (SkillsLibraryView.swift:43-47 'Import from this Mac'; MacMachinesView.swift:133/:24 'Import skills'). (2) Skill.dirName (Skill.swift:48-55) kebab-cases the name (taken from frontmatter or the source dir basename), so the fan-out path collides with the original tool dir for typical skills. (3) linkLocal (SkillMaterializer.swift:166-167) returns without linking when a real dir exists ('a REAL dir/file — never clobber'); remote guard at :189. So after import, edits in Shio land only in ~/.agents/skills while the agent keeps reading the stale ~/.claude/skills/<d>/SKILL.md on the source machine — silently, with no UI indication. (4) Disable removes only canonical + symlinks (SkillMaterializer.swift:154-159; remote :192-194), so the real dir survives and the agent keeps following a rule Shio shows as off, breaking the documented 'enabled ⇔ file present' invariant (SkillMaterializer.swift:10) and 'a disabled global stops applying everywhere' (Skill.swift:25). Secondary point also confirmed: importer scans ~/.agents/skills itself (SkillImporter.swift:62), so a real user skill dir there gets adopted as canonical — enable rewrites its SKILL.md (dropping all frontmatter keys except name/description, per parse + fileBody), and disable rm -rf's the whole dir including scripts/references aux files. No adoption/migration logic exists anywhere to handle this (grepped all callers; createSymbolicLink appears only in SkillMaterializer). Severity 'high' is right: not a blocker (core flows unaffected; sync works on machines without a pre-existing real dir; nothing breaks until the user edits/disables an imported skill), but it silently defeats the advertised bidirectional-skills flow on the source machine — typically the user's primary box — and the disable direction makes the UI report a state the agent doesn't honor.
</details>


#### SK-5 · `medium` · Symlink guard re-points and deletes user-owned symlinks (only real dirs are protected)

`Shio/Core/Skills/SkillMaterializer.swift:166` · confidence high · platform all

linkLocal: `if isSymlink(link) { try? fm.removeItem(atPath: link) }   // re-point our own symlink` (SkillMaterializer.swift:166) — the comment claims ownership but the code removes ANY symlink without checking its destination. A user who symlinks `~/.claude/skills/swift-style` → their dotfiles repo gets it silently re-pointed to Shio's canonical copy when a same-named Shio skill is enabled, and DELETED when it's disabled (line 158 `if isSymlink(link) { try? fm.removeItem(atPath: link) }`; remote line 194 `[ -L "$T" ] && rm -f "$T"`). The header doc's guarantee 'symlinks we own ... a user's own skill dir is never clobbered' (lines 16-18) is not implemented for foreign symlinks.

**Suggested fix:** Before removing/re-pointing, read the symlink destination and only touch links that already resolve under `~/.agents/skills` (the Shio-owned canonical store); same `readlink` check in the remote script.


#### SK-6 · `medium` · syncEnabled kill switch bypassed by removeGlobalLocally, and it is per-device with no iOS toggle

`Shio/Core/Skills/SkillMaterializer.swift:88` · confidence high · platform all

scheduleGlobalSync (line 80) and materialize (line 101) guard on `Self.syncEnabled`, but removeGlobalLocally (SkillMaterializer.swift:88-93) does not — with 'Sync skills to your coding agents' OFF, removing a skill still runs syncGlobalsLocal which removeItem()s inside `~/.claude`, `~/.cursor`, `~/.codex`, exactly the cross-app access MacSettings promises never happens ('Off = Shio never touches those folders', MacSettings.swift:~70). Separately, the switch is `UserDefaults.standard` (line 32-34, device-local, not synced) and the toggle is only exposed on Mac (MacSettings.swift:39); iOS Settings has no toggle (SettingsView.swift only links the library), so turning it off on the Mac does not stop the iPhone from writing skills into remote machines' folders on project open.

**Suggested fix:** Add `guard Self.syncEnabled` to removeGlobalLocally, and either expose the toggle on iOS or document/sync the switch as per-device.


#### SK-7 · `medium` · Disable made on another device never reconciles: Mac launch sync skipped when no globals are enabled, and no CloudKit-change resync

`ShioMac/MacShell.swift:110` · confidence high · platform mac

maybeSyncSkills: `guard skillSyncEnabled, SkillMaterializer.shared.hasGlobalsToMaterialize() else { return }` (MacShell.swift:110) where hasGlobalsToMaterialize requires an ENABLED global (`globalItems().contains(where: \.enabled)`, SkillMaterializer.swift:38). Disable your only/all global skills from the iPhone while the Mac is off → next Mac launch the guard fails and syncGlobalsLocal (whose disabled branch would remove the files, lines 154-159) never runs — the agent keeps following 'disabled' rules indefinitely. There is also no CloudKit-change-triggered resync anywhere (call sites are launch `.task`, library edits, and project open only), so toggles from the phone never apply to a Mac that stays running.

**Suggested fix:** Make the launch guard `!globalItems().isEmpty` (sync also when everything is disabled, since the sync is what removes files), and trigger scheduleGlobalSync from a SwiftData/CloudKit remote-change notification.


#### SK-8 · `medium` · Remote skill writes swallow every failure (dead host, exec error, non-zero exit) with no surfacing or retry

`Shio/Core/Skills/SkillMaterializer.swift:212` · confidence high · platform all

writeRemote: `_ = try? await client.exec(script, timeout: .seconds(12))` and `catch { await client.disconnect() }` (SkillMaterializer.swift:210-216). SSHClient.exec additionally never checks the command's exit status and resolves with partial stdout on timeout (SSHClient.swift:269-298, 'Timeout closes the channel → EOF → the collector succeeds'). So if the host is asleep/offline at project open, or any line of the batched script fails, the skills simply don't land, the UI shows the skill enabled, and there is no retry/queue — the agent runs ungrounded silently. SkillImporter.importRemote has the same swallow (SkillImporter.swift:103-110: connect failure `return 0`), which MacMachinesView then reports as the affirmatively wrong "No new skills found on <host>." (MacMachinesView.swift:25).

**Suggested fix:** Echo a sentinel at the end of the remote script and verify it in the exec output; on failure surface a non-blocking 'skills didn't sync to <host>' note and retry on the next warm-host status pass. Distinguish SSH failure from zero results in importRemote (return an enum/throw).


#### SK-9 · `medium` · CRLF SKILL.md files break the frontmatter parser (verified): frontmatter imported as body, then doubled on re-materialize

`Shio/Core/Skills/SkillImporter.swift:24` · confidence high · platform all

parse() splits on "\n" and compares `line.trimmingCharacters(in: .whitespaces) == "---"` (SkillImporter.swift:23-25). CharacterSet.whitespaces does NOT include \r — verified by running Swift: `"---\r".trimmingCharacters(in: .whitespaces) == "---"` → false. A CRLF-authored SKILL.md (Windows checkout/editor) therefore fails fence detection: the name falls back to the directory name, the description is lost, and the raw `---\r\nname:...---` block becomes part of the body. When Shio re-materializes it, fileBody (SkillMaterializer.swift:53-60) prepends a second frontmatter block, producing a SKILL.md with doubled fences that agents will misparse on every machine.

**Suggested fix:** Trim with .whitespacesAndNewlines in the fence comparison and strip a trailing \r from each line (or split on /\r?\n/) before parsing keys/values.


#### SK-10 · `medium` · dirName collisions: distinct skills can map to the same directory and clobber/delete each other

`Shio/Core/Profiles/Skill.swift:48` · confidence high · platform all

Dedup is by raw lowercased name (`p.name.lowercased()`, SkillImporter.swift:43-47), but materialization keys on the sanitized dirName (Skill.swift:48-55 maps every non-alphanumeric to '-'). "My Skill" (key "my skill") and "my-skill" (key "my-skill") can both exist as records yet share `~/.agents/skills/my-skill` — last writer wins (syncGlobalsLocal writeLocal, SkillMaterializer.swift:147-152), and disabling either one deletes the shared dir (line 155 `try? fm.removeItem(atPath: canonical)`), silently un-materializing the other, still-enabled skill.

**Suggested fix:** Dedup and uniqueness-check on dirName (the materialization key), or suffix colliding dirNames with the skill id.


#### SK-11 · `low` · Project-scoped skills cannot be disabled from any UI, and disabled ones still display/count as active

`Shio/Features/Projects/ProjectOverviewView.swift:29` · confidence high · platform all

The only enabled-toggle is the globals list in SkillsLibraryView (filtered `allSkills.filter(\.isGlobal)`, SkillsLibraryView.swift:18); SkillEditor has no enabled control, and the iOS project dashboard's Skills row links to the GLOBAL library (ProjectOverviewView.swift:49-54), so `enabled=false` is unreachable for project skills even though materialize has a remove path keyed on it (SkillMaterializer.swift:122, 203-204). Meanwhile skillsCount counts project skills regardless of enabled (`($0.isGlobal && $0.enabled) || $0.project?... == pid`, ProjectOverviewView.swift:28-31) and the Mac dashboard skillRow renders an unconditional checkmark (MacProjectsView.swift skillRow).

**Suggested fix:** Add an enabled toggle to SkillEditor (or per-row in the project skills module) and filter the count/checkmark on `enabled`.


#### SK-12 · `low` · `base64 -d` in the remote write script fails on pre-Ventura macOS hosts (skills silently never materialize there)

`Shio/Core/Skills/SkillMaterializer.swift:187` · confidence medium · platform all

writeRemote decodes on the remote host: `printf '%s' <b64> | base64 -d > .../SKILL.md` (SkillMaterializer.swift:187, 202). macOS before 13 (Ventura) ships a base64 that only accepts `-D`/`--decode`, so on an older Mac remote every write line fails; combined with the unchecked exec exit status the failure is invisible. This is the only place in the codebase that decodes base64 ON the remote — GitStatusReader and SkillImporter encode remotely and decode in-app (GitStatusReader.swift:76, SkillImporter.swift:96), so they're unaffected.

**Suggested fix:** Use `openssl base64 -d` or `base64 --decode 2>/dev/null || base64 -D` fallback, or write via a quoted heredoc instead of remote decoding.


#### SK-13 · `polish` · Mac cross-app-prompt explainer bypassed when the first write comes from a library edit instead of launch

`Shio/Features/Skills/SkillsLibraryView.swift:182` · confidence high · platform mac

MacShell gates the launch sync behind the one-time explainer (`if skillsExplained { scheduleGlobalSync() } else { showSkillsExplainer = true }`, MacShell.swift:109-113), but SkillEditor.save() and the enable-toggle call `SkillMaterializer.shared.scheduleGlobalSync()` directly (SkillsLibraryView.swift:84, 182) with no `skillsExplained` check — on a fresh Mac, creating the first skill in Settings triggers the macOS "data from other apps" prompt without the explainer that exists precisely to precede it.

**Suggested fix:** Route library-initiated syncs through the same explained-gate (e.g. a SkillMaterializer.requestSync() that consults shio.skills.crossAppExplained).


### App lifecycle, deep links, widgets, pairing, app lock (LC)

**Dimension summary:** The lifecycle/integration layer is the weakest part of an otherwise carefully built app: every routing entry point (widget tap-to-connect, Siri intent, Handoff, away-push tap, and the still-dead shio://pair link) posts a notification that has never had an observer, so all of them silently no-op; on top of that the producers use three incompatible host-id formats. Two further high-severity bugs sit in shipped core paths: the auto-reconnect loop stalls permanently after its first failed retry (infinite 'reconnecting' spinner, no error), and the Face ID app lock is fully bypassed by force-quit + relaunch. The pairing, Live Activity, and lock-screen-approve subsystems are largely sound in their happy paths but have real edge failures: a crashable header parse and unvalidated authorized_keys writes on the Mac pairing listener, no TTL on Action records (stale keystroke injection), no orphan Live Activity cleanup after force-quit, and a late-set notification delegate that can drop cold-launch Approve taps. Legacy relay/ and companion/ Python directories contradict the no-relay positioning and should be removed or archived.


#### LC-1 · `high` · All host-routing entry points are dead: .shioConnectToHost has zero observers (widget taps, Siri intent, Handoff, push tap all silently no-op)

`Shio/Core/Util/ShioNotifications.swift:8` · confidence high · platform ios · **verified real**

Notification.Name `.shioConnectToHost` (Shio/Core/Util/ShioNotifications.swift:8) is POSTED from five places — the shio://connect deep link (Shio/ShioApp.swift:71-75), the Handoff continuation (ShioApp.swift:36-40), the away-push notification tap (Shio/Core/Push/PushService.swift:103 `NotificationCenter.default.post(name: .shioConnectToHost, ...)`), the CloudKit push handler (Shio/Core/Push/CloudKitSignalService.swift:93-97), and ConnectToHostIntent (Shio/Intents/ConnectToHostIntent.swift:18-22) — but a repo-wide grep finds NO observer (no addObserver/onReceive/notifications(named:) for it anywhere; the only observers in the app are OverlayWindow lifecycle, FileSpotlightSearcher, and MacAppDelegate's UserDefaults observer), and `git log -S` shows none ever existed in any commit. Consequence: the home-screen widget's "Tap to connect" Links (ShioWidgets/ShioWidgetsBundle.swift:104,136), the App Shortcut "Connect to machine" (which says only "the user lands on the host list with the selection ready" — also untrue), Handoff from another device, and the away-push tap (advertised in SHIO_STATE_OF_THE_UNION.md §2 as "Away-push deep-links here" to the project dashboard) all just open the app and do nothing. Compounding it, the three producers use three incompatible id schemes that no observer could reconcile: HostEntity uses hostname (Shio/Intents/HostEntity.swift:16 `var id: String // hostname`), the widget/Handoff use a stringified PersistentIdentifier (`"\(host.persistentModelID)"`, SessionStore.swift:141, TerminalScene.swift:85 — not parseable and meaningless on another device), and the Mac's Signal writes `hostId: ""` (ShioMac/MacProjectAgentMonitor.swift:83).

**Suggested fix:** Add a single router (e.g. in RootView or a @MainActor AppRouter observed by the tab shell) that resolves a unified host id (use Host.deviceID or hostname) and calls SessionStore.openOrCreate; for the away-push tap route to the project dashboard via sessionId. Unify the id format across widget, intent, Handoff, and Signal.

<details><summary>Verifier notes</summary>

VERIFIED REAL. The notification .shioConnectToHost (Shio/Core/Util/ShioNotifications.swift:8) is posted from SIX sites (the claim found five; PushService.swift:139-143 handleRemoteNotification is a sixth): ShioApp.swift:36-40 (Handoff), ShioApp.swift:71-75 (shio://connect deep link), PushService.swift:103 (push-tap default case), CloudKitSignalService.swift:93-97 (CloudKit push), ConnectToHostIntent.swift:18-22 (Siri intent). Exhaustive repo-wide greps confirm ZERO observers: no onReceive anywhere in the codebase, no notifications(named:), no publisher(for:), no raw-string usage beyond the definition, and the only addObserver calls are OverlayWindow (UIApplication lifecycle), FileSpotlightSearcher (NSMetadataQuery), and MacAppDelegate (UserDefaults). git log -S across all history shows no observer ever existed. The id fragmentation is also confirmed: HostEntity.id = hostname (HostEntity.swift:16), widget/Handoff use stringified persistentModelID (SessionStore.swift:141, TerminalScene.swift:84-85), and the Mac writes hostId: "" (MacProjectAgentMonitor.swift:82-83) — which means real away-pushes fail the !hostId.isEmpty guards in CloudKitSignalService.swift:93 and PushService.parse:112, so the tap-routing path is doubly dead. Net effect: widget "Tap to connect", the "Connect to machine" App Shortcut, Handoff, and away-push tap-to-dashboard all just foreground the app and silently do nothing. Severity HIGH is right (not blocker): manual connect works, and lock-screen Approve/Deny works independently via sendAction (verified end-to-end), so no core flow is broken — but multiple advertised, shipped entry points are entirely non-functional. Mitigating color: ConnectToHostIntent.swift:15-17 has a comment marking routing as a "Brick 11 second pass" TODO, so part of this is known-incomplete scaffolding, but the widget and away-push surfaces present it to users as working today.
</details>


#### LC-2 · `high` · Auto-reconnect state machine stalls forever after the first failed retry (and dead-host connects show an infinite 'reconnecting' spinner)

`Shio/Features/Terminal/SessionViewModel.swift:401` · confidence high · platform ios · **verified real**

connectOnce sets `state = isReconnect ? .reconnecting : .connecting` (SessionViewModel.swift:322) before attempting. On failure it calls handleUnexpectedDisconnect (line 392), but that function's first line is `if case .reconnecting = state { return }` (line 401, comment: "Already retrying? Don't pile on a duplicate task."). So when retry attempt 1 (scheduled by kickReconnect) fails, state is already .reconnecting and handleUnexpectedDisconnect returns without scheduling another attempt — the documented exponential backoff ("0.5, 1, 2, 4, 8, 16 seconds", line 445) never runs past the first retry, `reconnectAttempt` never reaches maxReconnects, and the `.disconnected` overlay (line 403) is never shown. The only rescues are the path monitor's unsatisfied→satisfied transition (line 249-252) and app foregrounding (reconnectIfNeeded line 295) — a brief server-side outage (sleeping Mac, sshd restart) on a stable network leaves the user staring at 'reconnecting…' forever. Same for a first connect to a wrong/dead host: start() fails, reconnectAttempt(0) < 6 routes into the same loop, retry 1 fails, and the user gets a permanent spinner with no error message.

**Suggested fix:** In connectOnce's catch when isReconnect is true, schedule the next attempt directly (kickReconnect) or surface .disconnected when reconnectAttempt >= maxReconnects, instead of routing through handleUnexpectedDisconnect; keep the .reconnecting guard only for the onDisconnect callback path.

<details><summary>Verifier notes</summary>

Verified by full code trace. connectOnce(isReconnect: true) sets state = .reconnecting (SessionViewModel.swift:322); on connect failure the catch routes to handleUnexpectedDisconnect (line 392), whose first line `if case .reconnecting = state { return }` (line 401) returns without scheduling another attempt or changing state. So the backoff loop dies after retry #1: reconnectAttempt never advances past what kickReconnect set (line 454), maxReconnects is never reached, and the .disconnected overlay (line 403) — the only UI with Reconnect/Diagnose buttons (TerminalScene.swift:342-371) — is unreachable; the .reconnecting state shows a button-less spinner capsule (TerminalScene.swift:325-339). I confirmed no hidden rescue: SSHClient.onDisconnect is only wired via ShellDataHandler.onClose inside requestShell() (SSHClient.swift:231-235) so it never fires on a failed connect, and even if it did the same guard returns; the path monitor only re-kicks on an unsatisfied→satisfied network transition (line 249) or an interface switch while .connected (lines 260-262), neither of which occurs for a dead host on a stable network; reconnectIfNeeded (line 295, sole caller ShioApp.swift:54 on foreground) resets reconnectAttempt to 0 and buys exactly one silent attempt per foreground, never surfacing the error. Severity 'high' is correct (not blocker): the most common drop cause (network blip/radio switch) IS rescued by the path monitor, and connects to live hosts work — but a server-side outage on a stable network (sshd restart, sleeping Mac — a use case named in the file's own doc comment, line 14) leaves a permanent 'Reconnecting…' spinner even after the host recovers, and a first connect to a dead/wrong host gives an infinite spinner with no error message instead of the ConnectErrorTranslator copy. The proposed fix is sound: keep the .reconnecting guard only for the onDisconnect callback path, and on a failed retry either schedule the next attempt or surface .disconnected when the budget is exhausted.
</details>


#### LC-3 · `high` · App lock is bypassed by force-quitting and relaunching: cold launch never authenticates

`Shio/Core/Security/OverlayWindow.swift:23` · confidence high · platform ios · **verified real**

`private var pendingLock: Bool = false` (OverlayWindow.swift:23) is only ever set in handleWillResignActive (`if appLockEnabled { pendingLock = true }`, lines 76-80). On a cold launch the sequence is install() → didBecomeActive, and handleDidBecomeActive (lines 83-90) sees pendingLock == false and calls hide() — nothing checks `appLockEnabled` at launch, so the full app (hosts, terminals, keys) is visible with no Face ID prompt even when 'Require Face ID' is on. Anyone with the unlocked phone defeats the lock by swiping Shio away and reopening it. RootView (Features/Shared/RootView.swift) has no lock state either — the AppLock.swift:5-7 doc comment about "@State for the lock flag in RootView" is stale.

**Suggested fix:** In OverlayWindow.install() (or its init), set pendingLock = appLockEnabled so the first didBecomeActive on a fresh process shows the lock overlay.

<details><summary>Verifier notes</summary>

Verified end-to-end. OverlayWindow.swift:23 declares `private var pendingLock: Bool = false`; the only code that sets it true is handleWillResignActive (lines 77-79), which never runs on a cold launch. handleDidBecomeActive (lines 83-90) checks only pendingLock and calls hide() when false; install() (48-71) creates the window hidden and never reads appLockEnabled. Grep confirms AppLockOverlay is presented solely by OverlayWindow (line 136); RootView.swift has no lock state (only OverlayWindow.shared.install() at line 21), ShioApp.swift and ShioAppDelegate (PushService.swift:181) contain no launch-time auth, and the AppLock.swift:4-8 doc comment about a RootView @State lock flag is stale. So with 'Require Face ID' on, force-quit + relaunch (or routine iOS jetsam of the backgrounded app, which erases the in-memory flag) opens the full app — hosts, terminals, keys — with no biometric prompt, directly contradicting the Settings promise at SettingsView.swift:84 ('Shio re-authenticates if you leave the app'). The feature is shipped (Settings Security toggle, SettingsView.swift:68; onboarding enableAppLock step). Severity high is right: not a blocker (core terminal flow unaffected) but a trivial, complete bypass of an explicitly enabled security feature in a shipped path. Fix note: seeding pendingLock in init alone is insufficient because show(.locked) guards on the window existing; install() must re-show the lock once the window is created.
</details>


#### LC-4 · `medium` · shio://pair is still a dead deep link — Mac QR encodes it, iOS only routes shio://connect (prior finding NOT fixed)

`Shio/ShioApp.swift:67` · confidence high · platform ios

handleDeepLink guards `url.host == "connect"` only (ShioApp.swift:66-69) and silently returns otherwise. The Mac pairing sheet encodes exactly this link into its QR: `return "shio://pair?d=\(b64)"` (ShioMac/MacPairingHost.swift:163), and PairingPayload.swift:8-9 explicitly advertises "a `shio://pair?d=<base64url>` deep link (so a tap on the same link works off-camera too)". The `shio` scheme is registered in Info.plist (CFBundleURLTypes, Shio/Info.plist:79-86), so scanning the Mac's QR with the system Camera app (the most natural first move) opens Shio and then does nothing — a silent dead end. The in-app scanner path works (PairingPayload.parse handles the pair form), but the OS-level link form has no handler. The legacy Python companion also prints this link as the simulator fallback (companion/README.md).

**Suggested fix:** In handleDeepLink, route `url.host == "pair"` to PairingPayload.parse(url.absoluteString) and present PairingView pre-populated (run the same provisionKey/upsertHost flow).


#### LC-5 · `medium` · Orphaned Live Activities are never cleaned up after force-quit/crash — stale 'Connected to <host>' sits on the lock screen indefinitely

`Shio/Core/LiveActivities/LiveActivityController.swift:19` · confidence high · platform ios

`activityIDs: [UUID: String]` (LiveActivityController.swift:19) is in-memory only, and lookupActivity (lines 76-79) only matches activities created in the current process run. SessionStore.reconcileLiveActivities (SessionStore.swift:234-257) iterates `sessions`, which is also empty on a fresh launch. Nothing anywhere enumerates `Activity<ShioSessionAttributes>.activities` at startup to end leftovers, so after the app is killed (or crashes) with a session open, its Live Activity stays on the lock screen — claiming "Connected" until the 90s staleDate dims it, then lingering as a dimmed dead tile that the app can never update or end (a new launch creates a second activity alongside it).

**Suggested fix:** On launch (e.g. in the RootView .task or reconcileLiveActivities), iterate Activity<ShioSessionAttributes>.activities and end every activity whose id isn't in activityIDs.


#### LC-6 · `medium` · Stale Approve/Deny Actions have no TTL and are injected into tmux whenever the next agent blocks

`Shio/Core/Push/CloudKitSignalService.swift:140` · confidence high · platform mac

fetchAndClearActions queries `NSPredicate(format: "sessionId > %@", "")` with no creation-date filter (CloudKitSignalService.swift:140-141), and the Mac only polls while something is waiting: `guard !signaledWaiting.isEmpty else { return }` (MacProjectAgentMonitor.swift:61). Sequence: agent blocks → push fires → user ignores it and answers at the desk → monitor re-arms and stops polling → hours later the user taps Approve on the still-visible lock-screen notification → the Action record sits in iCloud untouched → days later a different agent blocks → the next poll fetches the stale Action and runs `tmux send-keys -t <old-session> y Enter` (MacProjectAgentMonitor.swift:66-67) — typing 'y⏎' into whatever that old session is doing now. Keystroke injection into a shell on a timestamp-free queue is a real correctness/safety edge.

**Suggested fix:** Stamp Actions with a creationDate field and have fetchAndClearActions discard (but still delete) records older than ~2 minutes; optionally also verify the target session is currently waiting before injecting.


#### LC-7 · `medium` · MacPairingHost crashes on a malformed Content-Length header (index out of range) while the pairing listener is open

`ShioMac/MacPairingHost.swift:179` · confidence high · platform mac

parseHeaders does `length = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0` (MacPairingHost.swift:179). For a header line that is exactly `content-length:` (no value), `split(separator: ":")` yields a single element (split omits empty subsequences), so `[1]` traps and crashes ShioMac. The listener accepts raw TCP from anyone on the LAN/tailnet on port 8730 whenever the pairing sheet is open (startListener, lines 70-81), so any buggy or hostile client can kill the app mid-pairing.

**Suggested fix:** Parse defensively: split with maxSplits/omittingEmptySubsequences handling, or use `line.dropFirst("content-length:".count)`, guarding the empty case.


#### LC-8 · `medium` · Pairing host appends the POSTed key to authorized_keys with no format validation (interior newlines = multi-line injection)

`ShioMac/MacPairingHost.swift:141` · confidence high · platform mac

authorize(publicKey:) does `let line = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)` then appends `line + "\n"` to ~/.ssh/authorized_keys (MacPairingHost.swift:141-146). Trimming only strips the ends — interior `\n` survives, so a single token-bearing POST can append multiple arbitrary authorized_keys lines (including ones with `command=`/options or extra keys). There is no check that the payload matches an expected `ssh-ed25519 AAAA… comment` shape, no key-type allowlist, and no length cap. It's gated by the one-time token in the QR, but anyone who can photograph/shoulder-surf the QR during the pairing window gets a free write primitive into authorized_keys.

**Suggested fix:** Validate before appending: reject strings containing newlines, require exactly 2-3 space-separated fields with an allowlisted key type (ssh-ed25519 / ecdsa-sha2-nistp256) and base64-decodable blob.


#### LC-9 · `medium` · Settings copy promises a 10-second re-auth grace period that doesn't exist — lock engages on every resign-active

`Shio/Features/Settings/SettingsView.swift:84` · confidence high · platform ios

SettingsView.swift:84 tells the user "Shio re-authenticates if you leave the app for more than 10 seconds." But OverlayWindow.handleWillResignActive (OverlayWindow.swift:75-81) sets `pendingLock = true` unconditionally on willResignActive — there is no timer or threshold anywhere (no Date comparison exists in OverlayWindow/AppLock). Pulling down Notification Center, an incoming-call banner, or a 1-second app switch all force a full Face ID re-auth, contradicting the shipped copy and making the away-push 'glance at the banner then come back' flow needlessly hostile.

**Suggested fix:** Record the resign-active timestamp and only set pendingLock in handleDidBecomeActive when more than ~10s elapsed (or fix the copy if instant locking is intended).


#### LC-10 · `medium` · RunCommandIntent ships in Shortcuts/Siri but returns a fake placeholder result

`Shio/Intents/ConnectToHostIntent.swift:43` · confidence high · platform ios

RunCommandIntent.perform() returns `.result(value: "\(command) — pending implementation")` (ConnectToHostIntent.swift:43-47, comment: "Brick 11 second pass implements headless SSH execution. For now we return a placeholder"), yet it is registered as a public App Shortcut with the Siri phrase "Run a command on <host> with Shio" (ShioAppShortcuts.swift:15-22). A real user invoking it gets a string that looks like output but ran nothing — a silent no-op masquerading as success, and an easy App Review / first-impression failure.

**Suggested fix:** Either implement headless exec over SSHClient.exec or remove RunCommandIntent from ShioAppShortcuts until it works.


#### LC-11 · `medium` · UNUserNotificationCenter delegate is set too late (async, post-launch) — cold-launch notification taps and lock-screen Approve/Deny can be dropped

`Shio/Core/Push/PushService.swift:77` · confidence medium · platform ios

`center.delegate = self` lives in configureNotificationActions (PushService.swift:77), which is only reached from registerIfAuthorized after `await UNUserNotificationCenter.current().notificationSettings()` (line 51), itself launched from RootView's `.task` (ShioApp.swift:26). Apple requires the notification-center delegate be assigned before the app finishes launching for the launch-triggering notification response to be delivered; ShioAppDelegate (PushService.swift:181) implements no didFinishLaunching to set it synchronously. So when the user taps the away-push banner — or its Approve/Deny actions — while Shio is not running, the `userNotificationCenter(_:didReceive:)` callback (line 89) that writes the CloudKit Action can be missed. The end-to-end on-device verification of lock-screen approve very likely ran with the app alive in the background, which doesn't exercise this path.

**Suggested fix:** Set UNUserNotificationCenter.current().delegate (and the category registration) synchronously in ShioAppDelegate's application(_:didFinishLaunchingWithOptions:).


#### LC-12 · `medium` · Reconnect-on-foreground no-ops in the most common case: stale .connected state after suspension

`Shio/Features/Terminal/SessionViewModel.swift:297` · confidence medium · platform ios

ShioApp.swift:52-54 says "Nudge the visible session back to life — iOS killed our sockets while suspended" and calls SessionStore.reconnectActiveOnForeground(), but reconnectIfNeeded begins `switch state { case .connected, .connecting: return ... }` (SessionViewModel.swift:297-299). After a long suspension the SSH client typically hasn't observed the dead socket yet, so state is still `.connected` and the nudge does nothing — the user gets a frozen terminal until a write times out. The same stale state makes reconcileLiveActivities (SessionStore.swift:237-242) re-assert "connected" to the lock screen. The path monitor only catches interface changes (wifi↔cellular), not same-network NAT/server drops.

**Suggested fix:** On foreground, when state == .connected, actively verify liveness (send an SSH keepalive/channel request with a short timeout) and forceReconnect() on failure, instead of returning early.


#### LC-13 · `low` · Delayed Live Activity 'end' task can kill the activity of a session that has since reconnected

`Shio/Features/Terminal/SessionViewModel.swift:414` · confidence high · platform ios

When reconnects are exhausted, handleUnexpectedDisconnect schedules `update("disconnected")` then `try? await Task.sleep(nanoseconds: 25_000_000_000)` then `end(..., finalState: "disconnected")` (SessionViewModel.swift:413-425). The task is never cancelled, so if the user foregrounds the app and reconnectIfNeeded succeeds within those 25s (LiveActivityController.update("connected") fires), the pending end() still executes and removes the now-truthful activity from the lock screen of a live session.

**Suggested fix:** Store the cleanup Task and cancel it on successful reconnect, or have end() check the current connection state before ending.


#### LC-14 · `low` · Onboarding auto-advance guard is dead code — verification beat advances the step even if the user navigated away

`Shio/Features/Onboarding/OnboardingView.swift:380` · confidence high · platform ios

handleVerification's .passed branch contains `if case .checking = verification {} else {}` (OnboardingView.swift:380) directly above `onPass()` — a literal no-op despite the comment "Only advance if we're still on the same step the user just verified — they might have already navigated elsewhere." After the 700ms sleep, onPass() always fires, so a user who moved on (e.g. opened the pairing sheet from .welcome via another path) gets yanked to the next verification step.

**Suggested fix:** Capture the step at schedule time and guard `guard step == capturedStep else { return }` before onPass().


#### LC-15 · `low` · MacPairingHost Retry leaks the old NWListener and a failed authorize leaves the port listening with a non-rotating token

`ShioMac/MacPairingHost.swift:34` · confidence high · platform mac

`token` is a `let` created once per MacPairingHost instance (MacPairingHost.swift:31), and start() (line 34) never cancels an existing listener before `self.listener = listener` in startListener (line 80) — so the Retry button after a `.failed` state (MacPairingView line 229 `Button("Retry") { host.start() }`) leaks the previous listener on the same port (allowLocalEndpointReuse lets both bind). Also, the authorize-failure path in handleBody (lines 123-126) sets `.failed` but does not call stop(), so the endpoint keeps accepting POSTs while the UI shows failure. Shutdown after success/cancel is otherwise correct (stop() on .paired and onDisappear).

**Suggested fix:** Call stop() at the top of start() (and in the handleBody failure path); regenerate the token per start() so each shown QR is single-use.


#### LC-16 · `low` · Widget host list never prunes deleted/renamed hosts and uses unstable PersistentIdentifier strings as ids

`Shio/Core/Widgets/WidgetSharedState.swift:35` · confidence high · platform ios

recordConnect is the only writer (called from SessionStore.createNewSession, SessionStore.swift:140-144) and there is no removal/rename hook anywhere — a deleted machine stays in the widget's "Tap to connect" list forever (timeline policy is .never, ShioWidgetsBundle.swift:61, so it refreshes only on the next connect). The stored id is `"\(host.persistentModelID)"` — a SwiftData debug description that is not stable across stores/devices and not parseable, so even a future deep-link handler couldn't resolve it reliably.

**Suggested fix:** Mirror host deletes/renames into WidgetSharedState (remove by id, reload timelines) and key entries by a stable id (Host.deviceID or hostname).


#### LC-17 · `low` · Legacy relay/ and companion/ Python directories (plus PushService relay scaffold) contradict the shipped no-relay architecture

`relay/README.md:1` · confidence high · platform all

The product line is "no relay server, no cloud middleman" (SHIO_STATE_OF_THE_UNION.md §1) and away-push shipped as CloudKit-only, yet the repo still carries `relay/shio-relay.py` ("The one consciously-scoped Shio-operated piece… forwards triggers… via APNs", relay/README.md) and `companion/shio-away-watcher.py`. PushService's doc comment still asserts "end-to-end away notifications require the relay deployed + the companion away-watcher running" (PushService.swift:11-14) and keeps live scaffold code (registerWithRelay/post, lines 156-176) that will silently POST the APNs device token to any URL placed in the `shio.relay.baseURL` App-Group default. The iOS manual-pairing copy also still instructs "Run the Shio companion on your machine and paste the pairing payload it prints" (PairingView.swift:99) even though the Mac app is the real companion.

**Suggested fix:** Delete relay/ (or move to docs/attic with an explicit 'superseded by CloudKitSignalService' note), trim the relay scaffold + stale comments from PushService, and update the manual-entry copy to point at ShioMac's pairing QR.


### Cross-platform parity (iPhone / iPad / Mac) (PAR)

**Dimension summary:** Cross-platform parity is genuinely strong on the hero surfaces — Projects IA, git status/PR chips, commit-and-push, the machine switcher, and the takeover toggle all ship coherently on both iPhone and Mac, and the shared-core pattern (CommitSheet, SkillsLibraryView, FilesViewModel) mostly pays off. The two serious holes are routing and auth: on iOS, every connect entry point (away-push tap, widget, Siri shortcut, Handoff) posts a notification nothing observes, so the supervision loop's "tap to jump in" is dead; on Mac, the Files surfaces authenticate with a Shio key the Mac never creates instead of the system ~/.ssh keys the rest of the Mac app uses, so remote file browse/search fails while the terminal beside it works. iPad is exactly what the doc admits — the iPhone layout with no split view, no shortcuts, and dead IPadRootView code — and the cheapest credible fix is a size-class-gated NavigationSplitView reusing the existing iPhone views. The remaining gaps are asymmetries worth scheduling rather than blockers: stale needs-you cards on the iPhone dashboard, Mac-only skills import, skill deletion leaking materialized files, and a handful of self-host filtering and presentation rough edges.


#### PAR-1 · `high` · All connect/deep-link routing on iOS is dead: nothing observes .shioConnectToHost (push tap, widget, App Intent, Handoff all silently no-op)

`Shio/Core/Util/ShioNotifications.swift:8` · confidence high · platform ios

Five entry points post `.shioConnectToHost` expecting the app to open a session: the away-push plain tap (PushService.swift:100-107 `NotificationCenter.default.post(name: .shioConnectToHost, ...)`), CloudKit push routing (CloudKitSignalService.swift:92-98), the widget deep link `shio://connect?host=` (ShioApp.swift:71-75, posted from handleDeepLink; widget links at ShioWidgetsBundle.swift:104,136), Handoff continuation (ShioApp.swift:32-41), and ConnectToHostIntent.swift:18-23. A repo-wide search for observers (`onReceive`, `addObserver`, `publisher(for:`, `notifications(named`) finds only OverlayWindow.swift:27-42, which observes UIApplication willResignActive/didBecomeActive — no one ever subscribes to `.shioConnectToHost`, and git history shows no observer ever existed. So tapping the away-push banner (the hero supervision flow), tapping a widget, running the Siri shortcut, or continuing a Handoff session opens the app and then does nothing. Approve/Deny notification actions still work (they write Action records directly); only the routing tap is dead.

**Suggested fix:** Add one observer (e.g. in RootView or SessionStore) that resolves the hostId string to a Host and calls SessionStore.shared.openOrCreate(host:) + presents TerminalScene; ShioMac should also handle it for parity with the comment in TerminalScene.swift:75-77.


#### PAR-2 · `high` · Mac Files (remote browse + cross-machine search) uses the wrong SSH auth and fails for typical Mac users

`ShioMac/MacFilesPane.swift:118` · confidence high · platform mac

The Mac terminal authenticates with `.systemKeys` ("On Mac, default to the user's existing ~/.ssh keys", MacSSHSession.swift:35-36), as do status probes (ProjectStatusStore.swift:269-274), skills (SkillMaterializer.swift:113-115), and skill import (MacMachinesView.swift:20-22). But both Mac Files paths use `host.makeClientConfiguration()` — RemoteFilesBrowser via FilesViewModel.swift:30 and `runRemoteSearch` at MacFilesPane.swift:118 — and Host.makeClientConfiguration (Host.swift:127-144) only ever picks `.password`/`.shioKey`/`.unconfigured`, never `.systemKeys`. Nothing in the ShioMac target ever generates or installs a Shio key (grep for KeyManager in ShioMac/ returns nothing; PublicKeyView is iOS-only), so on the Mac `KeyManager.hasKey()` is typically false → `.unconfigured` → SSHClient.connect() throws `noAuthenticationConfigured` (SSHClient.swift:119-120). Result: Terminal and Projects status work against a remote, but Files → that same remote shows "Couldn't open files" and cross-machine search shows per-machine failures — with an error message pointing at a Settings → SSH Key screen that doesn't exist on the Mac.

**Suggested fix:** On macOS, have these call sites build the same `.systemKeys` configuration the rest of the Mac uses (e.g. add a platform-aware default in makeClientConfiguration or pass an explicit config into FilesViewModel).


#### PAR-3 · `medium` · iPad ships the unmodified iPhone layout; IPadRootView is dead code; zero keyboard shortcuts in the live iOS app

`Shio/Features/Shared/RootView.swift:38` · confidence high · platform ipad

RootView.swift:38-39: "Used on both iPhone and iPad (the iPadOS tab bar adapts); the old IPadRootView split is retired for now." IPadRootView.swift is never instantiated (only a stale doc-comment reference in KeyManager.swift:207) and it's stale anyway — it's a hosts-only split predating the Projects-first IA. The iOS target has no `horizontalSizeClass`/idiom checks anywhere, project.yml:28 ships device family "1,2", and the only `.keyboardShortcut` in the whole iOS target is inside the dead file (IPadRootView.swift:81). Concretely on iPad today: the three-tab phone UI stretched full-width (project rows ~18pt-padded across a 1024pt+ canvas), the terminal as an edge-to-edge `fullScreenCover` (ProjectsView.swift:92) with no split panes, no find-in-scrollback, no tab strip (all Mac-only: ShioMacApp.swift:54-103), no ⌘K palette, and no hardware-keyboard navigation (⌘1/2/3, ⌘N, ⌘W do nothing) — though raw terminal typing works fine via TerminalInputView.pressesBegan (TerminalInputView.swift:100-114).

**Suggested fix:** Cheapest credible master/detail: in RootView, when horizontalSizeClass == .regular, swap TabView for a NavigationSplitView — sidebar = sections list (Projects/Machines/Files, mirroring MacSection), content = the existing ProjectsView/HostListView/FilesView lists, detail = ProjectOverviewView or TerminalScene (presented in-column instead of fullScreenCover). Reuse the existing views unchanged; add .keyboardShortcut on the existing toolbar buttons and a Commands scene for section switching.


#### PAR-4 · `medium` · iPhone project dashboard never refreshes after first appear — in-app Approve leaves a stale needs-you card with no feedback

`Shio/Features/Projects/ProjectOverviewView.swift:117` · confidence high · platform ios

ProjectOverviewView refreshes status only in `.onAppear` (lines 117-121); its ScrollView has no `.refreshable` and no periodic task. The Mac equivalent keeps fresh with a 20s warmOnly loop (MacProjectsView.swift:47-54). The in-app Approve path depends on a refresh that never comes: `answer(_:_:)` (lines 162-164) fire-and-forgets `sendAction` with the comment "The card clears itself on the next status refresh" — but while the user stares at the dashboard there is no next refresh, the buttons show no progress/disabled state, and the warning card stays up indefinitely (inviting a second Approve tap, i.e. a second 'y' keystroke sent to the agent). The root ProjectsView at least has pull-to-refresh (ProjectsView.swift:65-68) but also no timer.

**Suggested fix:** Add `.refreshable` plus a 20s visible-only refresh task to ProjectOverviewView (mirroring MacProjectsView), and after answer() optimistically mark the card answered/disabled and trigger an immediate status refresh.


#### PAR-5 · `medium` · Deleting a skill via the editor leaves its SKILL.md materialized for agents (both platforms; remote copies never removed from iOS)

`Shio/Features/Skills/SkillsLibraryView.swift:186` · confidence high · platform all

SkillEditor.delete() (SkillsLibraryView.swift:186-189) is just `context.delete(skill); try? context.save()` — unlike the context-menu Remove path (lines 100-105) it never calls `SkillMaterializer.removeGlobalLocally(dirName:)` nor `scheduleGlobalSync()`. Since sync only iterates *existing* records (SkillMaterializer.globalItems, lines 68-71), the deleted skill's `~/.agents/skills/<dir>` + tool symlinks stay on disk forever — agents keep following a rule the user believes is gone. Worse for cross-platform: `removeGlobalLocally` is `#if os(macOS)` only (SkillMaterializer.swift:88-93) and remote removal only happens for disabled-but-existing records during materialize (lines 191-196), so a skill deleted from the iPhone (either path) is never removed from any machine.

**Suggested fix:** In SkillEditor.delete(), capture skill.dirName before context.delete and call removeGlobalLocally + a remote removal pass (or soft-delete by flipping enabled=false first so the existing sync machinery cleans up everywhere, then delete the record).


#### PAR-6 · `medium` · Pairing QR scanned with the iPhone Camera app opens Shio and silently does nothing (shio://pair not routed)

`Shio/ShioApp.swift:66` · confidence high · platform ios

The Mac encodes the pairing QR as a deep link: `return "shio://pair?d=\(b64)"` (MacPairingHost.swift:157-163), and PairingPayload.swift:39-43 explicitly supports the `shio://pair?d=<base64url-json>` form. But ShioApp.handleDeepLink (ShioApp.swift:66-70) guards `url.host == "connect"` and silently returns for everything else. Scanning the Mac's QR with the system Camera app — the natural first move during pairing — opens Shio to the home screen with zero indication of what to do next. Only the in-app PairingScanner path works.

**Suggested fix:** Handle `url.host == "pair"` in handleDeepLink: parse with PairingPayload's link decoder and route into the same flow PairingView uses (or at minimum present PairingView pre-filled).


#### PAR-7 · `medium` · Mac cross-machine file search and command palette SSH into the Mac itself (self-host not filtered)

`ShioMac/MacFilesPane.swift:117` · confidence high · platform mac

MacFilesPane's browse list correctly filters the self record (`machines.filter { !MacSelfHost.isThisMac($0) }`, line 50), but `runRemoteSearch` does not: `let targets = machines.map { (name: $0.name, config: $0.makeClientConfiguration()) }` (lines 117-120) includes this Mac's own synced Host record, so every ⏎ search opens an SSH connection to localhost — duplicating the Spotlight "This Mac" section at best, or showing a confusing "<MyMac>: failed" group when Remote Login is off. The hint at line 98 also overcounts ("search your N machines"). Same root cause in CommandPalette.swift:188-196: "Connect: <machine>" entries are built from the unfiltered `machines` query, offering SSH-to-itself — exactly the dead-blank-tab failure the one-time tab reset cleaned up (MacShell/ShioMacApp restoreTabs comment, ShioMacApp.swift:200-205).

**Suggested fix:** Filter `MacSelfHost.isThisMac` out of runRemoteSearch targets and the palette's Connect entries (route the self entry to model.newLocalTab() instead).


#### PAR-8 · `medium` · iOS file-browser mutations that fail destroy the whole browsing session (failed full-screen + Retry resets to home)

`Shio/Features/Files/FilesViewModel.swift:124` · confidence high · platform ios

FilesViewModel.mutate (lines 124-132) catches any SFTP error with `state = .failed(error.localizedDescription)`, which swaps the entire browser for the full-screen "Couldn't open files" view (FileBrowserView.swift:104-116). A very ordinary action triggers it: swipe-Delete on a non-empty directory — `removeDirectory` (line 84) is a plain SFTP RMDIR, which fails on non-empty dirs — as do permission-denied renames/uploads. Retry then calls `vm.start()` (FileBrowserView.swift:113), which re-resolves the start path (FilesViewModel.swift:43), dropping the user back at the home directory and losing their place. Mac is unaffected only because its remote browser exposes no mutations.

**Suggested fix:** Surface mutation failures as a transient inline error (alert/toast) while keeping state == .browsing and the current listing; reserve .failed for connection-level errors.


#### PAR-9 · `medium` · Skills import into Shio is Mac-only — the phone can't pull existing skills from any machine, breaking the bidirectional arc on iOS

`Shio/Features/Skills/SkillsLibraryView.swift:41` · confidence high · platform ios

The library's import affordance is `#if os(macOS)` only (SkillsLibraryView.swift:41-53), and the per-machine "Import skills" button exists only in MacMachinesView.swift:133-135. On iOS, HostListView rows go straight to a terminal with no detail surface or context action, and Settings has no import entry — yet `SkillImporter.importRemote` (SkillImporter.swift:88-112) is platform-agnostic, compiled into the iOS target, and works over the same SSH layer. A phone-first user (the hero persona) who already has ~/.claude/skills on their Mac can author new skills from the phone but can never pull the existing ones in; the doc's v3 promise ("edit a skill on your phone and it lands on every box") only bootstraps from a Mac.

**Suggested fix:** Add an "Import from <machine>" action on iOS (e.g. a context menu / detail row in HostListView, or a button in SkillsLibraryView listing saved hosts) that calls SkillImporter.importRemote with the host's config.


#### PAR-10 · `medium` · "Run Command" Siri/Shortcuts action is shipped but returns a placeholder

`Shio/Intents/ConnectToHostIntent.swift:44` · confidence high · platform ios

RunCommandIntent.perform() returns `"\(command) — pending implementation"` (ConnectToHostIntent.swift:44-48) yet the intent is published to every user via ShioAppShortcuts.swift:15-22 ("Run a command on … with Shio"). A user building an automation gets a successful-looking result containing placeholder text instead of output — a silent functional no-op in a discoverable, shipped surface. (Combined with the orphaned ConnectToHostIntent above, both advertised shortcuts are currently non-functional.)

**Suggested fix:** Either implement it with the existing SSHClient.exec path (config from host.makeClientConfiguration) or remove it from ShioAppShortcuts until it works.


#### PAR-11 · `low` · Mac dashboard has no in-app Approve/Deny — needs-you rows only offer 'jump'

`ShioMac/MacProjectsView.swift:632` · confidence high · platform mac

iOS's needs-you card offers one-tap Approve/Deny via CloudKit Actions (ProjectOverviewView.swift:221-229). The Mac's AgentRowView (MacProjectsView.swift:632-668) renders the same waiting state but its only affordance is `ShioButton("jump ›")`. For a local agent that's fine (the answer is one keystroke in the tab), but the Mac also surfaces *remote* agents detected via the status fetch (agentSnapshot, lines 237-250), and answering one requires opening a full SSH tab instead of the approve channel the phone already uses (CloudKitSignalService.sendAction is compiled into the Mac target).

**Suggested fix:** When the snapshot is remote (host != self) and waiting, show the same Approve/Deny pair wired to CloudKitSignalService.sendAction(sessionId: "shio-<repo>", key:).


#### PAR-12 · `low` · Mac remote file browser is read-only while iOS has full CRUD + upload + preview

`ShioMac/MacFilesPane.swift:287` · confidence high · platform mac

iOS FileBrowserView offers new-folder, rename, delete, file upload, photo upload, pull-to-refresh and an in-app preview (FileBrowserView.swift:155-174, 138-147, sheet at 31-33). The Mac's RemoteFilesBrowser (MacFilesPane.swift:287-363) reuses the same FilesViewModel — which already implements makeDirectory/delete/rename/upload (FilesViewModel.swift:77-102) — but exposes none of it: browse, filter, go-up, and download-to-temp-and-open only (and `openRemoteFile`'s `try?` at line 359 makes a failed download a silent no-op while the row just stops being busy). No refresh affordance either.

**Suggested fix:** Add context-menu rename/delete/new-folder and a refresh toolbar button to RemoteFilesBrowser (the view-model work is already done), and surface openRemoteFile failures.


#### PAR-13 · `low` · iOS has no skills-sync kill switch (Mac Settings has one), so the phone always writes into remote agent folders

`Shio/Features/Settings/SettingsView.swift:38` · confidence high · platform ios

Mac Settings exposes "Sync skills to your coding agents" bound to SkillMaterializer.syncEnabledKey (MacSettings.swift:39,69-71). iOS SettingsView has no equivalent toggle, yet every project/repo open on iOS runs `SkillMaterializer.shared.materialize(...)` over SSH (ProjectsView.swift:113-115), which writes into `~/.agents/skills` and symlinks `~/.claude`/`.cursor`/`.codex` on the remote machine (SkillMaterializer.writeRemote, lines 180-217). `syncEnabled` defaults to true (line 33), so an iOS-only user cannot opt out of Shio touching agent folders on their machines.

**Suggested fix:** Add the same toggle to iOS Settings (it's an UserDefaults key the shared materializer already honors).


#### PAR-14 · `low` · Machine dedupe only applied in HostListView — Files tab and project add-sheet can show the same Mac twice

`Shio/Features/Files/FilesView.swift:26` · confidence medium · platform ios

HostListView dedupes because "The same Mac can arrive as two records — the stamped self-host plus an older un-stamped pairing/synced copy" (HostListView.swift:10-30). FilesView lists the raw `hosts` query (FilesView.swift:26), and AddProjectSheet's machine picker does too (AddProjectSheet.swift:50-54), so during the window before the Mac-side merge syncs in, the Files tab and the host picker show duplicate rows for one Mac — and picking the doomed duplicate in AddProjectSheet attaches the checkout to a Host record the Mac is about to delete.

**Suggested fix:** Extract HostListView's dedupedHosts into a shared helper and use it in FilesView and AddProjectSheet.


#### PAR-15 · `low` · Opening a project with no usable checkout silently no-ops on iOS and opens a wrong local shell on Mac

`Shio/Features/Terminal/SessionStore.swift:100` · confidence medium · platform all

SessionStore.openOrCreate(repo:) returns nil when `repo.activeCheckout`/`checkout.host` is nil (SessionStore.swift:100-101), and ProjectsView.open just skips presenting (`if sessionStore.openOrCreate(project:) != nil { showingTerminal = true }`, ProjectsView.swift:104-109) — tapping the terminal button does nothing, no message. This state is reachable mid-CloudKit-sync (project records can arrive before their checkout/host records; the model is optional-by-construction). The Mac handles the same state differently: MacTerminalModel.open(repo:) falls through to `MacLocalProjectSession(name:, path: "")` (ShioMacApp.swift:269-272), opening a local shell in $HOME for a repo that may live on another machine.

**Suggested fix:** On iOS, show a small "still syncing this project's machine" notice when openOrCreate returns nil; on Mac, guard the local fallback on a non-empty path.


#### PAR-16 · `polish` · Dead/stale iPad artifacts: IPadRootView and its doc references should be retired or rebuilt

`Shio/Platform/iPad/IPadRootView.swift:7` · confidence high · platform ipad

IPadRootView.swift is compiled into the target but unreachable (no references besides KeyManager.swift:207's doc comment "Read by `HostListView` / `IPadRootView`"). It also reflects a pre-Projects IA (hosts sidebar labeled "Macs", Settings as a pushed link) and deletes hosts by `offsets` over the unsorted `hosts` array inside a `ForEach(hosts)` (lines 58-61) — fine today only because it never runs. Keeping it risks someone re-wiring a stale, subtly buggy layout.

**Suggested fix:** Delete the file (and the KeyManager comment) or rewrite it as the real size-class split described in the iPad finding before re-wiring.


#### PAR-17 · `polish` · SettingsView nests its own NavigationStack inside the NavigationStack call sites wrap it in

`Shio/Features/Settings/SettingsView.swift:24` · confidence medium · platform ios

SettingsView's body opens with its own `NavigationStack { Form ... }` (SettingsView.swift:24), but all three presenters wrap it again: `.sheet { NavigationStack { SettingsView() } }` (ProjectsView.swift:90, HostListView.swift:112-114, FilesView.swift:62-64). Nested stacks generally render, but they're unsupported layering that can produce doubled nav-bar spacing and broken toolbar/title behavior, and it diverges between entry points.

**Suggested fix:** Drop the NavigationStack from the call sites (or from SettingsView's body) so there's exactly one.


#### PAR-18 · `polish` · Fixed minWidth 380 on shared sheets can overflow the smallest iPhones; iPad padding token defined but never used

`Shio/Features/Skills/SkillsLibraryView.swift:164` · confidence medium · platform ios

SkillEditor (SkillsLibraryView.swift:164) and CommitSheet (CommitSheet.swift:67) both set `.frame(minWidth: 380, idealWidth: 460)` — sized for Mac sheets but shared with iOS, where a 375pt-wide iPhone SE-class screen makes the sheet content wider than the display. Separately, `ShioPadding.screenHorizontalIPad = 32` exists (Spacing+Tokens.swift:19) but is referenced nowhere; AboutView hardcodes `ShioPadding.screenHorizontalIPhone` (SettingsView.swift:256), so nothing in the app actually adapts padding for iPad.

**Suggested fix:** Gate the minWidth with #if os(macOS) (or use ShioPadding/size-class–aware sizing), and either use or delete screenHorizontalIPad.


### Design consistency — iOS (#40) (DI)

**Dimension summary:** The iOS design system is in better shape than the handoff doc fears: hero surfaces (Projects/Machines/Files/Settings/Skills) are genuinely on ShioTheme/ShioKit, the global AccentColor asset already encodes the ink↔salt flip, and there are no stray raw hexes in feature code outside the terminal bridge. The debt is concentrated and enumerable: exactly 19 LegacyButton call sites (with two ShioButton kit gaps — destructive and full-width — blocking the swap), a recurring raw .green/.orange/.yellow status-color pattern across ~10 sites that bypasses the deepened-in-light status tokens, and Form-based sheets still wearing stock system chrome. Two findings rise above language-consistency into real rendering bugs: the lock/privacy screens draw theme-ink text on hardcoded black (invisible wordmark in light mode), and the terminal surface is permanently #282C34 because the entire TerminalTheme light/dark pipeline ends in an empty no-op.


#### DI-1 · `high` · Light mode: lock screen and privacy screen render the wordmark invisible (theme text on hardcoded black)

`Shio/Features/Security/AppLockOverlay.swift:16` · confidence high · platform ios

AppLockOverlay.swift:16 hardcodes `Color.black` as the canvas, but the wordmark at :24 and :27 uses `.foregroundStyle(ShioTheme.textPrimary)`. ShioTheme.swift:32 defines `textPrimary = Color(light: ink800, dark: ink100)` where ink800 = #0E0E10 — so in light mode the 塩 kanji and 'shio' wordmark are near-black on black, effectively invisible. Identical bug in PrivacyScreenView.swift:13-21 (`Color.black` + `ShioTheme.textPrimary`), which is the splash shown on EVERY app-switcher snapshot. The app follows the system scheme (ShioApp.swift:12 `.preferredColorScheme(nil)  // follow system`), so light-mode users see a blank black lock/privacy screen with only the unlock button visible. Function survives (unlock button uses LegacyButton .primary which stays readable), but both surfaces look broken/crashed in light mode.

**Suggested fix:** Either make these surfaces theme-aware (`ShioTheme.background` canvas) or, if the privacy screen is intentionally always-dark, pin the text colors to the dark-mode values too (e.g. ink100/bone literals or `.environment(\.colorScheme, .dark)`).


#### DI-2 · `medium` · Terminal surface is hardcoded to #282C34 in both modes; the light/dark theme plumbing is dead code that deviates from the locked terminal tokens

`Shio/Features/Terminal/LibGhostty/LibGhosttyBridge.swift:17` · confidence high · platform ios

LibGhosttyBridge.swift:17 `static let terminalBackgroundHex: UInt32 = 0x282C34` with `foreground = #FFFFFF` (:79) is applied unconditionally to the ghostty config. The design tokens lock the terminal palette to macOS Terminal Basic — Color+Tokens.swift:103 `background = Color(light: .white, dark: .black)` with the comment 'Do not deviate' — and TerminalTheme.swift even builds light/dark themes, but the pipe is severed: LibGhosttyTerminalController.swift:109 `func applyTheme(_ theme: TerminalTheme) {}` is an empty no-op, so TerminalView.swift:27's per-colorScheme theme selection does nothing. Net effect: in light mode the full-screen terminal is a one-dark-ish gray (neither the white light token nor the black dark token), and TerminalScene's `.ultraThinMaterial` top bar / scroll buttons (TerminalScene.swift:167, 318) resolve LIGHT material over the dark canvas. Code-level facts are certain; whether always-dark-terminal is the intended look needs eyes/design decision.

**Suggested fix:** Decide the terminal palette deliberately: either wire applyTheme through to ghostty config (white/black per the locked tokens) or bless #282C34 as a token and delete the dead TerminalTheme/ShioColor.Terminal path so there is one source of truth.


#### DI-3 · `medium` · 19 LegacyButton call sites remain in iOS feature code (the full retire list), and ShioButton lacks the destructive + full-width variants needed to replace them

`Shio/DesignSystem/Components/LegacyButton.swift:10` · confidence high · platform ios

Exact inventory (19, not ~22): OnboardingView.swift:239 (primary → ShioButton .primary), :241 (.text → .ghost); PairingView.swift:109 'Pair', :165 'Done', :183 'Try again' (all primary → .primary); AppLockOverlay.swift:39 (primary → .primary); TerminalScene.swift:356 'Reconnect' (.primary), :359 'Diagnose' (.secondary); DiagnosticsView.swift:193, :197 (.secondary → .secondary); DirectoryPickerView.swift:36 'Use this folder', :75 'Retry' (primary); FileBrowserView.swift:113 'Retry' (primary); AddHostSheet.swift:144, :242 'Save' (primary); PublicKeyView.swift:128, :153 (.secondary), :164 (primary), :177 'Regenerate key' (.destructive). Zero call sites in ShioMac. Two kit gaps block a mechanical swap: (1) ShioKit.swift:173 `enum ShioButtonKind { case primary, secondary, ghost }` has no destructive kind for PublicKeyView:177; (2) LegacyButton is full-width with 44pt min height and a built-in haptic (LegacyButton.swift:25,33-34) while ShioButtonStyle has neither `maxWidth: .infinity` nor `tapTargetMin`, so swapping onboarding/lock-screen CTAs would visibly shrink them. LegacyButton also drags the otherwise-dead ShioColor palette along (LegacyButton.swift:47-65 is the ONLY remaining ShioColor consumer).

**Suggested fix:** Add `.destructive` (ShioTheme.danger fill) and a `fullWidth: Bool` option to ShioButton/ShioButtonStyle, then replace the 19 sites per the mapping above and delete LegacyButton.swift + the ShioColor enum it pins.


#### DI-4 · `medium` · Settings toggles override the brand accent with raw system .green

`Shio/Features/Settings/SettingsView.swift:71` · confidence high · platform ios

SettingsView.swift:71, :93, :106, :124 all apply `.tint(.green)` to toggles on a HERO surface (Settings is one of the migrated four). The asset catalog defines AccentColor as the ink↔salt flip (Assets.xcassets/AccentColor.colorset: #0E0E10 light / #E8DCC4 dark), so without these modifiers the toggles would already render on-brand; the explicit `.green` actively replaces the locked accent with iOS system green, which also doesn't match ShioTheme.success (#1F9A4E light / #3FB868 dark).

**Suggested fix:** Delete the four `.tint(.green)` modifiers (inherit the AccentColor flip), or use `.tint(ShioTheme.success)` if green-means-on is the intent.


#### DI-5 · `medium` · TerminalScene session status hand-rolls a dot with raw .green/.yellow/.red instead of ShioStatusDot + status tokens

`Shio/Features/Terminal/TerminalScene.swift:224` · confidence high · platform ios

TerminalScene.swift:224-233 `statusColor` returns `.green` (connected), `.yellow` (connecting/reconnecting), `.red` (disconnected) — raw SwiftUI system colors, and `.yellow` isn't even close to the warning token (#B9741A/#E0913A). The dot itself is a hand-built `Circle().fill(statusColor).frame(width: 6...)` at :151-153 even though the kit ships exactly this primitive (ShioKit.swift:66 `ShioStatusDot`, 6pt, status-tinted, hollow-when-neutral). The terminal top bar is shipped chrome users stare at constantly.

**Suggested fix:** Map state → ShioStatus (.success/.warning/.danger/.neutral) and render `ShioStatusDot(status:)` in the top bar.


#### DI-6 · `medium` · Raw .green/.orange system colors used for status iconography across five supporting surfaces instead of ShioTheme.success/warning

`Shio/Features/Pairing/PairingView.swift:145` · confidence high · platform ios

All sites: PairingView.swift:145 success checkmark `.foregroundStyle(.green)` and :175 failure triangle `.foregroundStyle(.orange)`; IconPickerView.swift:44 selected checkmark `.foregroundStyle(.green)`; FileBrowserView.swift:108, DirectoryPickerView.swift:70, FilePreviewView.swift:54 — identical error-state `Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)`. ShioTheme deliberately deepens status colors in light mode (ShioTheme.swift:46-49) for contrast on the bone canvas; system .green/.orange are the bright variants that the deepening exists to avoid, and they don't flip with the palette. Related raw tints: HostListView.swift:66 `.tint(.red)` and FileBrowserView.swift:146 `.tint(.gray)` on swipe actions (lower stakes — system swipe rows — but same pattern).

**Suggested fix:** Replace with ShioTheme.success / ShioTheme.warning (and ShioTheme.danger / textTertiary for the swipe tints); the three identical SFTP error states could share one kit-styled error view.


#### DI-7 · `low` · Form-based sheets (AddHostSheet, AddProjectSheet, Settings, IconPicker) keep system-default section headers and field chrome, not the kit's mono uppercase language

`Shio/Features/Hosts/AddHostSheet.swift:215` · confidence high · platform ios

AddHostSheet.swift:136-137/:215 `Section("Machine")`, :227 `Section("Advanced")`; AddProjectSheet.swift:49/:72/:113 and SettingsView.swift:67/:98/:116/:120/:167 likewise use plain Form section headers — system grouped style, not the kit's mono/tracked `ShioSectionHeader` (ShioKit.swift:113, 'the terminal-refined section label'). Backgrounds are reskinned (`.scrollContentBackground(.hidden)` + `ShioTheme.background`) but row surfaces, headers, and footers are stock system grouped styling, so these sheets read as a different dialect next to the migrated heroes. This matches the documented state ('supporting cast only MECHANICALLY migrated') and the author wants the design pass done collaboratively — flagging as inventory, not solo-grind work; final call needs eyes on device.

**Suggested fix:** In the collaborative design pass, either bless Form chrome for input sheets as an accepted dialect or restyle headers via ShioSectionHeader and listRowBackground(ShioTheme.surface).


#### DI-8 · `low` · Legacy design layer is mostly dead weight: ShioColor pinned only by LegacyButton, ShioColor.Terminal/ShioOpacity/TerminalTheme unused, IPadRootView retired but still compiled

`Shio/DesignSystem/Tokens/Color+Tokens.swift:5` · confidence high · platform ios

Audit of the legacy layer: (a) `ShioColor` has zero feature-code references — its only consumer is LegacyButton.swift:47-65; (b) `ShioColor.Terminal` (Color+Tokens.swift:102-125) and `ShioOpacity` (:129) have no references anywhere — TerminalTheme.swift:32-37 duplicates the same ANSI hexes by hand instead of referencing the tokens, and TerminalTheme itself only feeds the no-op applyTheme; (c) ShioNavTitle.swift is legacy-by-location but already token-correct (uses ShioTheme.* + the wordmark face) and is live on all three tab heroes (ProjectsView:72, FilesView:38, HostListView:76); (d) ShioFont/ShioSpace/ShioRadius/ShioMotion remain legitimately load-bearing across ~20 files; (e) Platform/iPad/IPadRootView.swift is referenced by nothing (RootView.swift:39 'the old IPadRootView split is retired for now') yet still ships in the target with pre-kit styling.

**Suggested fix:** When LegacyButton dies, delete ShioColor + ShioOpacity wholesale; delete or token-source TerminalTheme depending on the terminal-theme decision; move ShioNavTitle/Spacing/Typography out of the 'legacy' folder so the remaining live tokens aren't tarred as retired; remove IPadRootView until iPad-proper lands.


#### DI-9 · `low` · SkillEditor uses default .roundedBorder text fields and a 380pt minWidth that can clip on small iPhones

`Shio/Features/Skills/SkillsLibraryView.swift:138` · confidence medium · platform ios

SkillEditor (shared iOS+Mac, presented as a plain `.sheet` from SkillsLibraryView.swift:74-75) styles its name/description fields with `.textFieldStyle(.roundedBorder)` (:138, :141) — stock system bordered fields, while the sibling CommitSheet.swift:34-40 shows the kit treatment (plain field on ShioTheme.surface + ShioTheme.line hairline). It also sets `.frame(minWidth: 380, idealWidth: 460)` (:164), sized for a Mac popover; on a 375pt-wide iPhone (SE/mini class) a 380pt minimum inside a sheet can force content wider than the screen. Needs eyes on a small device to confirm the clip.

**Suggested fix:** Restyle the two TextFields to the CommitSheet pattern and gate the minWidth behind `#if os(macOS)`.


#### DI-10 · `polish` · Hand-rolled status washes where ShioTheme background tokens already exist

`Shio/Features/Hosts/KeyReinstallBanner.swift:48` · confidence high · platform ios

KeyReinstallBanner.swift:48 `.background(ShioTheme.warning.opacity(0.12))` and :51 `strokeBorder(ShioTheme.warning.opacity(0.3))` re-derive what ShioTheme.warningBg (ShioTheme.swift:52) encodes, drifting from the token's per-mode opacities. Same pattern at PublicKeyView.swift:193 `.background(ShioTheme.danger.opacity(0.1))` vs ShioTheme.dangerBg. The banner also fails to clip its fill: the `.background` at :48 is applied before `.clipShape` at :53 — actually clip comes after so it is clipped; the real issue is only the token bypass.

**Suggested fix:** Use ShioTheme.warningBg / ShioTheme.dangerBg (or ShioStatus.warning.wash) for the fills.


#### DI-11 · `polish` · Off-token literals: corner radii (8/11/12), paddings (32, 20-vs-token), and a heavy hardcoded shadow

`Shio/Features/Terminal/TerminalScene.swift:369` · confidence high · platform ios

Radius literals off the ShioRadius scale (4/6/10/14/20): PairingView.swift:108 (10 written literally), :162 (8); SkillsLibraryView.swift:151-152 (8); CommitSheet.swift:39-40, :50 (8); TerminalScene.swift:303 (12); ProjectOverviewView.swift:233-235 (11). Padding literals where tokens exist: FilesView.swift:80 and HostListView.swift:133 `.padding(.horizontal, 32)` (= ShioSpace.xxl); SkillsLibraryView.swift:22/:69 (22, 20). And TerminalScene.swift:369 `.shadow(color: .black.opacity(0.5), radius: 24, y: 8)` on the disconnected card — the only drop shadow in the iOS app, off a language built on hairlines, and a hardcoded dark value with no light variant.

**Suggested fix:** Sweep literals to ShioRadius/ShioSpace tokens; replace the disconnect-card shadow with the ShioCard hairline treatment (or a much quieter elevation token if one is added).


#### DI-12 · `polish` · KeyboardAccessoryView key caps are SF Pro sans on UIKit system fills — the one terminal-adjacent chrome with zero Shio tokens

`Shio/Features/Terminal/KeyboardAccessoryView.swift:174` · confidence medium · platform ios

KeyboardAccessoryView.swift:174 `titleLabel.font = .systemFont(ofSize: 15, weight: .medium)` renders 'esc/tab/ctrl/opt' — literal terminal keys — in sans, where the kit reserves mono for 'anything that is literally code' (ShioKit.swift:58). Colors are all UIKit system dynamics (:186 systemFill, :254-258 label/systemBackground), which adapt to light/dark correctly (no incoherence bug) and approximate the ink↔salt flip for the pending/locked states, but nothing references ShioTheme. Deliberately UIKit for latency (file header), and sitting flush against the system keyboard may justify the system look — needs eyes before changing.

**Suggested fix:** Consider `UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)` for the key caps (cheap, on-language); leave the system fills unless the design pass decides otherwise.


### Design consistency — macOS (#40) (DM)

**Dimension summary:** The Mac design migration is further along than the "8 files on raw system colors" debt suggests: MacProjectsView, MacMachinesView, and the shared sheets (CommitSheet, SkillsLibraryView/SkillEditor) are fully and consistently on ShioTheme/ShioKit, and the legacy MacInk palette has shrunk to one dead file plus two live uses in ShioCompanion. The real remaining gaps cluster in supporting chrome: the Files pane is wholly on system List styling beside tokenized neighbors, the sections sidebar and command-palette selection still speak system-accent blue against the locked ink/bone language, and the empty-terminal mascot's hardcoded bone color is effectively invisible in light mode. Everything found is a clearly-off surface or a judgment call for the planned collaborative pass — no blockers, and several system-color usages (menu-bar extra, Settings form, QR quiet zone) are genuinely correct and should be left native.


#### DM-1 · `medium` · Empty-terminal mascot (ShioCompanion) hardcodes dark-palette MacInk.bone — nearly invisible in light mode

`ShioMac/ShioCompanion.swift:50` · confidence high · platform mac

ShioCompanion.swift:50 renders the mascot face with `.foregroundStyle(MacInk.bone)` and :43 the sparkle with `.foregroundStyle(MacInk.amber)`, where MacInk is the hardcoded dark palette (MacPromptRows.swift:12 `static let bone = Color(red: 0xE8/255, green: 0xDC/255, blue: 0xC4/255)`). This is the live empty-terminal hero state (TerminalWorkspace.swift:171 `ShioCompanion()` inside `EmptyTerminalState`), and EmptyTerminalState (TerminalWorkspace.swift:167-178) applies no themed background, so it sits on the system window background. In light appearance that is bone #E8DCC4 text on a near-white canvas — the mascot all but disappears. Bone is exactly ShioTheme.accent's dark-mode value, i.e. this was authored for dark only.

**Suggested fix:** Map MacInk.bone → ShioTheme.accent (ink in light, bone in dark) and MacInk.amber → ShioTheme.warning in ShioCompanion, and give EmptyTerminalState `.background(ShioTheme.background)` so the at-rest terminal area sits on the bone/ink canvas.


#### DM-2 · `medium` · MacFilesPane is entirely on system List chrome and system colors while its neighbor panes are tokenized

`ShioMac/MacFilesPane.swift:31` · confidence high · platform mac

The Files section is the one main pane not migrated: it wraps everything in `NavigationStack` + system `List` (lines 18, 40, 68, 199, 339) whose opaque NSTableView background paints over the `.background(ShioTheme.background)` set at line 31 — the bone canvas never shows. All text/icons use system roles instead of tokens (`.secondary` at 71, 85, 87, 90, 99, 107, 111, 132, 138, 187, 189, 196, 216, 271, 328, 332, 334, 350, 371; `.tertiary` at 277, 377; `.body`/`.callout` fonts instead of ShioKitFont), and rows are bespoke `MachineFileRow`/`LocalFileRow`/`SFTPRow` (lines 124, 265, 365) rather than `ShioListRow`. Result: a stock white/system-gray list pane sitting between the bone-toned Projects (MacProjectsView, fully on ShioTheme) and Machines panes — the clearest inconsistent-chrome seam in the app. Needs visual confirmation of how jarring it reads, but the code-level mismatch is certain.

**Suggested fix:** Rebuild the Files root and browsers on ShioRail/ShioListRow/ShioSectionHeader with ShioTheme.background, mapping `.secondary`→ShioTheme.textSecondary, `.tertiary`→ShioTheme.textTertiary, mono paths→ShioKitFont.mono; keep NavigationStack push behavior.


#### DM-3 · `medium` · Command palette selection uses Color.accentColor (system blue) + hardcoded white text — off the locked ink/bone language

`ShioMac/CommandPalette.swift:230` · confidence high · platform mac

CommandRow highlights the selected row with `.background(selected ? Color.accentColor : Color.clear)` (CommandPalette.swift:230) and forces `Color.white` text/icons when selected (lines 210, 213, 217, 225). ShioMac/Assets.xcassets has no AccentColor entry (only AppIcon), so accentColor resolves to the user's system accent — default blue, but user-configurable (graphite, yellow, …), neither of which exists in the locked palette (ShioTheme.accent flips ink #0E0E10 ↔ bone #E8DCC4; info blue is #3A66C8/#5B8DEF). The hardcoded white also risks poor contrast on lighter system accents. The palette chrome itself is `.regularMaterial` + `.separator` (lines 59-61) — material is a defensible floating-overlay idiom, but the selection color is the visible tell. ⌘K is a hero interaction, so the mismatch is front and center.

**Suggested fix:** Use ShioTheme.accent fill with ShioTheme.background foreground for the selected row (the same flip ShioButtonStyle.primary uses, ShioKit.swift:199/208), or ShioTheme.accentBg + ShioTheme.accent for a quieter highlight; keep the material if desired but consider ShioTheme.surface + line2 for full coherence.


#### DM-4 · `medium` · Sections sidebar (MacShell) uses the system source-list material and blue selection beside bone ShioRail panes

`ShioMac/MacShell.swift:39` · confidence medium · platform mac

MacShell.swift:38-49 builds the leftmost sidebar as a plain `List(MacSection.allCases, selection:)` in a NavigationSplitView — translucent system sidebar material with the system accent (blue) selection pill — while one column to the right, MacProjectsView:27 / MacMachinesView:36 use `ShioRail` (light #FBF6EA / dark #0A0A0C, ShioTheme.rail) with `ShioTheme.accentBg` ink selection (MacProjectsView.swift:77). Two adjacent rails speak different selection/material languages, and the system vibrancy material fights the warm bone canvas in light mode. This is one of the known per-usage judgment calls: a native sidebar is defensible, but as written the selection colors visibly disagree. Needs visual confirmation on device.

**Suggested fix:** Either restyle the sections list onto ShioRail + ShioListRow with accentBg selection (matching the projects rail), or if keeping the native sidebar, at least align its selection tint with the design language — decide once in the collaborative design pass.


#### DM-5 · `low` · MacPromptRows is dead code carrying the legacy hardcoded MacInk palette and a stale rationale comment

`ShioMac/MacPromptRows.swift:11` · confidence high · platform mac

Repo-wide grep shows zero call sites for `PromptRow`, `PromptSectionHeader`, `MacInk.green`, and `MacInk.info` — the only living consumers of this file are ShioCompanion's `MacInk.bone`/`MacInk.amber` (ShioCompanion.swift:43,50) and PromptRow's own body (MacPromptRows.swift:51). The header comment (lines 7-10) — "inlined here because the ShioMac target doesn't pull in the iOS DesignSystem tokens" — is no longer true: ShioTheme/ShioKit are compiled into ShioMac and used throughout MacProjectsView/MacMachinesView. Leaving a parallel hardcoded palette (bone #E8DCC4, amber #E89D3C, green #30C46D, info #5B8DEF at lines 12-15) invites future drift; the values also don't match ShioTheme's deepened light-mode status colors (e.g. warning light is #B9741A).

**Suggested fix:** Delete MacPromptRows.swift (PromptRow/PromptSectionHeader and the MacInk enum) once ShioCompanion is re-pointed at ShioTheme.accent/ShioTheme.warning; also delete the unused private `placeholder(...)` helper in MacShell.swift:115-122 while in there.


#### DM-6 · `low` · Tab strip background is .windowBackgroundColor (cool system gray) instead of the bone/ink canvas

`ShioMac/TerminalWorkspace.swift:213` · confidence high · platform mac

TabStrip ends with `.background(Color(nsColor: .windowBackgroundColor))` (TerminalWorkspace.swift:213). The comment (lines 209-212) explains this deliberately avoids `.bar` (unified-titlebar tint bleed) — a solid color is the right call, but the chosen color is the system window gray (~#ECECEC light / ~#28282B dark), not a token. In light mode that puts a cool gray strip atop the warm app; `ShioTheme.background` (boneDiluted #F4EEDF / ink800) is equally opaque and avoids the same titlebar glitch. The TabChip selection fills (`Color.primary.opacity(0.10)`/`0.05`, lines 252-253) are appearance-adaptive and close enough to ShioTheme.hover to be acceptable.

**Suggested fix:** Swap `.windowBackgroundColor` for `ShioTheme.background` (or ShioTheme.rail) — keeps the strip solid and contained while joining the canvas; optionally move the chip fills to ShioTheme.accentBg/hover.


#### DM-7 · `low` · Pairing sheet success checkmark uses raw system .green instead of ShioTheme.success

`ShioMac/MacPairingHost.swift:220` · confidence high · platform mac

MacPairingHost.swift:220: `Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)` — system green, while the design system's success token is #1F9A4E light / #3FB868 dark (ShioTheme.swift:46), used everywhere else (e.g. SkillsLibraryView.swift:87, MacProjectsView.swift:492). The rest of the sheet is native `.secondary`/`.tertiary` text in a system sheet, a reasonable fallback for a one-shot utility sheet. Note `Color.white` behind the QR at line 253 is genuinely correct — QR codes need a white quiet zone for reliable scanning; do not tokenize it.

**Suggested fix:** Change `.green` to `ShioTheme.success`; optionally bring the sheet headline/body onto ShioTheme.textPrimary/textSecondary during the design pass.


#### DM-8 · `low` · Split-pane focus ring on Color.accentColor — needs a deliberate choice, since ShioTheme.accent would vanish over a dark terminal in light mode

`ShioMac/TerminalSplit.swift:154` · confidence medium · platform mac

PaneHost draws the focused-pane ring with `.strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)` (TerminalSplit.swift:154) — system blue, off-palette. But this is a case where the naive token swap is wrong: the ring overlays the ghostty surface, whose colors follow the terminal theme (often dark) independent of app appearance, so ShioTheme.accent (ink #0E0E10 in light mode) would be invisible over a dark terminal. A fixed bone or ShioTheme.info would read in both cases. Flagging as a per-usage judgment call per the known debt, not a mechanical replacement.

**Suggested fix:** Pick a ring color that works over arbitrary terminal themes — e.g. the raw bone constant or ShioTheme.info — rather than either system accent or the flipping ShioTheme.accent.


#### DM-9 · `polish` · Terminal find bar and section search field on system materials/fills instead of kit surfaces

`ShioMac/TerminalWorkspace.swift:148` · confidence high · platform mac

TerminalSearchBar: `.background(.regularMaterial, in: Capsule())` + `.overlay(Capsule().strokeBorder(.separator))` (TerminalWorkspace.swift:148-149) — a floating material over terminal content is a native idiom and defensible, but ShioTheme.surface + ShioTheme.line2 would match CommitSheet/the kit. SectionSearchField: `.background(.quaternary, in: RoundedRectangle(cornerRadius: 8, ...))` (MacShell.swift:147) with `.secondary` icons (135, 143) — this one renders inside the Files pane flow, where the kit equivalent is ShioTheme.surface (or hover) + line hairline. Both are small chrome; neither breaks light mode.

**Suggested fix:** During the design pass, restyle both fields on ShioTheme.surface + line/line2 with ShioKitFont sizes; keep the floating shadow.


#### DM-10 · `polish` · Confirm-button language is inconsistent across Mac sheets: system buttons in Add Machine/Add Project vs ShioButton primary in CommitSheet/SkillEditor

`ShioMac/MacAddProjectForm.swift:52` · confidence high · platform mac

The same sheet pattern ships in two dialects. MacAddProjectForm.swift:52-58 and MacAddHostForm (MacShell.swift:182-188) use plain system `Button("Cancel")` / `Button("Add & Open")` with `.formStyle(.grouped)` system forms; the Skills sheet in MacSettings.swift:84 uses a plain `Button("Done")`. Meanwhile the shared sheets rendered on Mac use the kit: CommitSheet.swift:62 `ShioButton("Commit & push", .primary, ...)` and SkillEditor (SkillsLibraryView.swift:159) `ShioButton("Save", .primary)`, both on `.background(ShioTheme.background)` (CommitSheet.swift:68, SkillsLibraryView.swift:165) — while the Add forms keep the system sheet background. Native grouped forms are a legitimate Mac idiom for data entry (arguably genuinely correct), but the mixed confirm-button weight across sheets is visible churn.

**Suggested fix:** Pick one sheet language: either move Add Machine/Add Project confirm rows to ShioButton(.primary) on ShioTheme.background (matching CommitSheet/SkillEditor), or accept native forms everywhere and document it — a one-direction decision for the design pass.


#### DM-11 · `polish` · Inventory of system-color usages that are genuinely correct — do not churn these in the design pass

`ShioMac/MacAppDelegate.swift:45` · confidence high · platform mac

Confirmed-correct native usages found during the sweep: (1) the menu-bar extra (MacAppDelegate.swift:45-62) is a plain NSStatusItem + NSMenu — native menu rendering is correct and the 塩 title needs no tint; (2) the Settings window form (MacSettings.swift:42-79, `.formStyle(.grouped)` with `.secondary` footnotes) — a Mac Settings (⌘,) window reading native is conventional and arguably right; (3) the QR quiet zone `Color.white` (MacPairingHost.swift:253) is functionally required for scanning; (4) the command-palette scrim `Color.black.opacity(0.18)` (CommandPalette.swift:241) is a standard dimming layer fine in both appearances; (5) `.secondary` on the sidebar footer wordmark (MacShell.swift:46) and ShioCompanion's idle line (ShioCompanion.swift:58) are appearance-adaptive and read correctly on their current native backgrounds. None of these is light-mode breakage.

**Suggested fix:** No action — record these as accepted native seams so the #40 design pass doesn't mechanically tokenize them (revisit item 5 only if the sidebar itself moves onto ShioTheme.rail).
