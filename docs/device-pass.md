# The device pass (M3) — what only Amrith + real hardware can verify

> Written 2026-07-04. This is the checklist for the one sitting that proves the
> wedge end-to-end. Delete this file once everything's checked and the results
> are folded into the release notes. Setup: iPhone + this Mac on the SAME
> iCloud account; Debug builds talk to CloudKit **Development** + sandbox APNs,
> TestFlight/Release to **Production** — the full pass runs twice, once per
> environment. Remember: CloudKit never delivers a push to the device that
> wrote the record — every push test is cross-device by construction.

## 1. The loop, watched in one sitting (the wedge)

The on-demand trigger is `scripts/agent-drill.sh` — a fake agent that walks
running → y/n-prompt on cue and REPORTS what keystrokes land (including
duplicates). Run it inside any Shio repo terminal on the Mac; each bullet is
one drill round. Finish with one real Claude Code run as the final proof.

- [ ] Drill round: ⚑ appears on the Mac dashboard/rail within ~4s of the prompt; iPhone banners "Claude Code needs you".
- [ ] **From the lock screen**, long-press → Approve → the drill prints `received: 'y'` and `✓ no duplicate keystroke`.
- [ ] Fresh round, tap the banner instead → the app opens INTO the right project/terminal (ConnectRouter, deviceID route).
- [ ] Fresh round with the app force-quit before the banner — approve must still land (delegate set in didFinishLaunching).
- [ ] Two devices answering the same prompt in the same window → the drill must NOT print `⚠ DUPLICATE INJECTION`.
- [ ] Answer at the Mac keyboard, then immediately tap Approve on the phone → still no duplicate (the still-waiting guard).
- [ ] `--tease` round: the phone stays silent for the whole round (false-ping bias).
- [ ] The real thing once: Claude Code blocks on y/n → push → lock-screen Approve → it proceeds.

## 2. Reconnect truth (new since June — the Mac state machine)

- [ ] Mac: SSH tab open → drop Wi-Fi 10s → watch "reconnecting…" in the header → restore → lands back in tmux, scrollback intact.
- [ ] Mac: close the lid 2 min with an SSH tab open → wake → tab recovers without a click (didWake sweep).
- [ ] iPhone: mid-session, flip Wi-Fi→cellular → reconnects on the interface switch without waiting for a timeout.
- [ ] Kill sshd on a test box (or firewall it) → 6 backoff attempts → honest disconnected overlay, Reconnect works after restoring.

## 3. Trust-new-key flow (new)

- [ ] On a throwaway VM/container: connect once (pin), regenerate host keys (`sudo ssh-keygen -A` + restart sshd), reconnect → refusal with **Review key change** → fingerprints shown → Trust → reconnects and re-pins. Cancel path keeps refusing.

## 4. Two-device data bake

- [ ] Fresh install on one device, existing data on the other, same iCloud → projects/repos/checkouts converge with **no duplicate repos/hosts** after both run a few minutes.
- [ ] Delete a host on the iPhone → its checkouts/widget entries clean up on both.
- [ ] Rename a repo on the Mac → the iPhone shows it (and its tmux session still resolves — the session name keeps the OLD scrub until reopened; expected, not a bug).

## 5. The odds and ends the Simulator can't do

- [ ] Secure Enclave key (Settings → SSH key): generate on device, add to a real host, connect; invalidate it → Ed25519 fallback still connects.
- [ ] App lock: enable → force-quit → relaunch demands Face ID; a <10s app switch does NOT re-prompt (grace window).
- [ ] Live Activity: session open → lock screen shows it; force-quit → relaunch ends the stale activity.
- [ ] Skills: edit a skill on the iPhone → it lands in `~/.claude/skills` + `~/.agents/skills` on the Mac and any SSH-reachable box; a failed host shows the quiet ⚑ row in Settings → Skills.
- [ ] Repo repair: sync a repo from another device without placing it → tap it → the repair sheet places + opens it.

## 6. Then the Apple batch (one pass, per the standing checklist)

See memory/`project_apple_batch_checklist` — TestFlight external group + beta
review submission, CloudKit **Production** schema check (`Signal`, `Action`,
`CD_*` types), Sparkle release signing, screenshots from the demo-mode build.
