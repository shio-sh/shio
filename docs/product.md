# Shio — product north star

Internal reference. The what and the why we build against. Public copy lives on shio.sh; visual rules live in [`design-tokens.md`](design-tokens.md); voice lives in [`brand.md`](brand.md).

Rewritten September 2026, when the scope was cut. The version this replaces is in [`archive/`](archive/).

## What Shio is

Shio is a terminal you can use as your only terminal, that also happens to be on your phone.

Two claims, in that order. The first is the hard one and everything depends on it: if Shio is not good enough to be someone's daily driver on a Mac, the phone is a novelty. The second is what nothing else does well.

## What it is not

Cut deliberately, and written down so it stays cut.

- **Not an agent supervisor.** Away-push when an agent stops, lock-screen approve and deny, a supervision console. Built, then removed. It made Shio a worse terminal and a mediocre dashboard simultaneously, and every agent vendor now ships their own. Agents are a thing that runs *in* Shio, like any other program.
- **Not a hosted service.** No Shio server, no account, no relay. This is a constraint on the product, not a feature to advertise. It means some things are harder (reaching a machine behind NAT needs Tailscale) and we accept that.
- **Not a file manager, note app, or IDE.** Adjacent surfaces are how a terminal turns into a worse version of four apps.

## Who it is for

People who live in a terminal on a Mac and own the machines they work on. The phone is not a replacement for the desk. It is for the twenty minutes between places, when a build is running or an agent is halfway through something and you want to see it without opening a laptop.

## The wedge

Cross-platform terminals exist. Mobile SSH clients exist. What none of them do is make the *same work* present on all three devices, because they all model a connection rather than a project.

1. **Projects, not hosts.** A project holds its repos, the machines they sit on, and the shells opened for them. You reach for the thing you're doing, not the box it runs on. This is the only structural idea in the product and it should be the last thing cut.
2. **The session outlives the device.** tmux holds it open on the machine. Close the lid, open the phone, the output that arrived while you were gone is there.
3. **A real terminal on a phone.** libghostty compiled natively, so vim and htop and lazygit render rather than degrade. Most mobile SSH clients fail here, and it is immediately obvious when they do.
4. **Yours.** Your machines, your keys, your iCloud. Nothing routes through us because there is no us to route through.

## What "good enough to be the daily driver" means

The bar, concretely. Failing any of these makes the rest irrelevant:

- Cold start to a usable prompt faster than the terminal it replaces.
- No perceptible input latency, locally or over SSH on a decent link.
- Escape sequences, colors, ligatures and mouse reporting correct enough that TUIs do not notice they are being hosted.
- Copy, paste, selection, scrollback and every keyboard chord behave the way a desktop terminal does.
- It does not lose your session, and when the network drops it comes back on its own.

## Open questions

- **Panes.** tmux windows and panes are server-side, so they exist on every device by construction. Shio's own splits live in the Mac's view tree and cannot. Control mode is the path to collapsing the two; the UI restructure is not done.
- **Saved commands per project.** The two or three things you actually run in a repo. Needs a CloudKit entity, which means a schema deploy, which is irreversible in production. Not started.
- **What the phone is really for.** Peek by default, or full interaction? Currently full, which may be more than anyone wants at a bus stop.
