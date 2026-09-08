# The device pass — what only real hardware can prove

> Rewritten 2026-09-08, after the v1 terminal cut and the first integration
> tests. Delete this file once it's all checked and the results are in the
> release notes.

**Setup.** iPhone + this Mac on the same iCloud account. Both apps now start
empty: local data and the CloudKit *development* environment were wiped on
2026-09-08, so the Mac opens on an empty dashboard and the iPhone opens on
onboarding. Your previous setup is written down in `~/shio-setup-before-reset.txt`
if you want to recreate it exactly.

**What already has automated coverage** (`ShioKitTests/SSHIntegrationTests.swift`,
44 tests, run with `xcodebuild -scheme ShioMac test`): the SSH handshake and auth,
exec channels, host-key pinning including refusing a *changed* key, a tmux session
outliving its connection, attach-or-create not duplicating, and the git probe
against a real repo. You are testing the app on top of that, not the transport
itself. If something fails below, it is almost certainly UI or state, not SSH.

---

## 1. First run

- [ ] iPhone: onboarding reads "Your machines, in your pocket." Walk the QR path end to end and get a machine added.
- [ ] iPhone: walk the Tailscale path instead on a second run. (Tailscale is currently **stopped** on this Mac — start it first or this step is meaningless.)
- [ ] The SSH key screen: copy the install command, run it, connect. Does it work without you already knowing how SSH works?
- [ ] Mac: empty dashboard says "No projects yet" with a working "Add a project".

## 2. The core loop (the actual product)

- [ ] Create a project with **a logo** and a repo with **a clone URL**. Required before shipping — see §7.
- [ ] Open a repo on the Mac → terminal attaches, prompt lands in the right directory.
- [ ] Same repo from the iPhone → **the same live session**, same scrollback. This is the whole promise; if only one thing gets tested, test this.
- [ ] Type on the phone, watch it appear on the Mac, and the reverse.
- [ ] Force-quit the phone app mid-session → reopen → back in the session.
- [ ] iPhone keyboard accessory row: esc, tab, ctrl, arrows, and the sticky modifier long-press all reach the remote.
- [ ] iPad: three-column frame, rail + canvas + inspector, with a hardware keyboard if you have one.

## 3. Reconnect truth

- [ ] Mac: SSH tab open → drop Wi-Fi 10s → "reconnecting…" in the header → restore → back in tmux, scrollback intact.
- [ ] Mac: close the lid 2 min with an SSH tab open → wake → recovers without a click.
- [ ] iPhone: mid-session, flip Wi-Fi → cellular → reconnects on the interface switch, not after a timeout.
- [ ] Kill sshd on a test box → backoff attempts → honest disconnected overlay → Reconnect works once restored.

## 4. Trust-new-key (UI only; the mechanism is now automated)

- [ ] On a throwaway box: connect once, regenerate host keys, reconnect → refusal with **Review key change**, fingerprints shown, Trust → reconnects. Cancel keeps refusing.

## 5. Two-device bake

- [ ] Fresh install on one device, data on the other, same iCloud → projects/repos/checkouts converge with **no duplicates** after a few minutes.
- [ ] Delete a host on the iPhone → checkouts and widget entries clean up on both.
- [ ] Rename a repo on the Mac → the iPhone shows the new name. **Known bug:** the tmux session name is derived from the repo name, so a rename orphans the running session on next reconnect. Confirm the scope; the fix is scheduled and needs a migration.

## 6. Changed on 2026-09-08 — needs your eyes

- [ ] **Machine picker**: "Add a repo" → the Machine dropdown lists this Mac **once**, as "This Mac". It used to appear twice.
- [ ] **Unplaced repo**: a repo with no checkout reads "not on any machine", names no machine, and the glance counts it. Tapping it opens the repair sheet — **new on the Mac**, previously iPhone/iPad only. Place a repo this way and confirm it opens.
- [ ] **Glance strip** shows the project's shape ("3 repos · 1 machine"), not a permanent "all quiet".
- [ ] **Home cards** name the machines a project lives on again.
- [ ] Copy no longer mentions agents anywhere: onboarding, About, both create forms.
- [ ] Mac app still launches and runs a **local** shell (macOS floor moved to 15, arm64 only, all packages bumped including swift-nio-ssh).

## 7. CloudKit schema — required before any TestFlight build

Production is missing `CD_imageData`, `CD_cloneURL`, `CD_notes`,
`CD_skillDescription` and `CD_persistenceModeOverrideRaw`. CloudKit only
auto-creates fields in **development**, on first write from a Debug build.

- [ ] With a Debug build, create a project **with a logo** and a repo **with a clone URL** (§2). That generates the field types in development.
- [ ] Then ask Claude to export development and import to production with `cktool`. Scripted; the management token is already saved.
- [ ] Do NOT hand-write the production schema. Production is append-only and a wrong field type is permanent.

## 8. Only-on-device odds and ends

- [ ] Secure Enclave key: generate on device, add to a real host, connect; invalidate → Ed25519 fallback still connects.
- [ ] App lock: enable → force-quit → relaunch demands Face ID; a <10s app switch does not re-prompt.
- [ ] Live Activity: session open → lock screen shows it; force-quit → relaunch ends the stale activity.
- [ ] Widget: tap-to-connect reaches the right host.
- [ ] Files: browse a remote host, preview a file.

## 9. Then ship

TestFlight build (the current one expires ~2026-09-11), Mac DMG via the
**Release Mac** action so Sparkle auto-update finally reaches people, and the
App Store submission. External beta review already passed in June, so the
TestFlight path is open. Screenshots need `archive/demo-mode` reseeded first —
it still seeds agents, skills and PRs, which no longer exist.
