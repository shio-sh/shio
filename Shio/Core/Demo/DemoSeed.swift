import Foundation
import SwiftData

/// Fills the in-memory demo store with curated data so we can take real App
/// Store screenshots of the actual app — not a mockup. Runs only when
/// ``DemoMode/isActive`` (the Demo schemes), called once from each app's launch
/// task.
///
/// The set-dressing is Amrith's own world (Ekpani Labs): the projects are his
/// real tools/spaces and the machines are personal easter eggs — `brahmi` (the
/// Centella plant Ekpani is named for), `sando` (his shiba), and the literal
/// "Pi in the closet" from Shio's own tagline. Edit freely; the live refreshers
/// no-op in demo, so whatever's set here is exactly what shows.
@MainActor
enum DemoSeed {
    static func run() {
        let ctx = ShioModelContainer.shared.mainContext
        guard (try? ctx.fetchCount(FetchDescriptor<Project>())) == 0 else { return }   // idempotent

        // ── Machines (easter eggs; all warm except the sleepy closet Pi) ────
        let studio   = Host(name: "studio",    hostname: "studio.local",               username: "amrith", kind: .directSSH)
        let brahmi   = Host(name: "brahmi",    hostname: "brahmi.tail9c2e.ts.net",      username: "amrith", kind: .tailscale)
        let sando    = Host(name: "sando",     hostname: "sando.fly.dev",              username: "root",   kind: .directSSH)
        let closetPi = Host(name: "closet-pi", hostname: "closet-pi.tail9c2e.ts.net",   username: "pi",     kind: .tailscale)
        studio.lastConnectedAt   = .now
        brahmi.lastConnectedAt   = .now
        sando.lastConnectedAt    = .now
        closetPi.lastConnectedAt = Date(timeIntervalSinceNow: -5 * 24 * 3600)   // asleep → hollow dot
        [studio, brahmi, sando, closetPi].forEach(ctx.insert)

        // ── Projects = the Ekpani tools/spaces → repos → checkouts ──────────
        let shio = Project(name: "shio", path: "~/shio/shio-app", host: studio); ctx.insert(shio)
        shio.addRepo(name: "shio-app",    path: "~/shio/shio-app",    host: studio, cloneURL: "git@github.com:ekpani/shio.git", in: ctx)
        shio.addRepo(name: "landing",     path: "~/shio/landing",     host: studio, in: ctx)
        shio.addRepo(name: "beta-worker", path: "~/shio/beta-worker", host: studio, in: ctx)

        let timebase = Project(name: "timebase", path: "~/timebase/app", host: brahmi); ctx.insert(timebase)
        timebase.addRepo(name: "timebase-app", path: "~/timebase/app", host: brahmi, in: ctx)
        timebase.addRepo(name: "api",          path: "~/timebase/api", host: brahmi, in: ctx)

        // dhuni + biriyani live under samooh (both are "by Samooh").
        let samooh = Project(name: "samooh", path: "~/samooh/web", host: sando); ctx.insert(samooh)
        samooh.addRepo(name: "samooh-web", path: "~/samooh/web",      host: sando, in: ctx)
        samooh.addRepo(name: "dhuni",      path: "~/samooh/dhuni",    host: sando, in: ctx)
        samooh.addRepo(name: "biriyani",   path: "~/samooh/biriyani", host: sando, in: ctx)

        let stem = Project(name: "stem", path: "~/stem/app", host: brahmi); ctx.insert(stem)
        stem.addRepo(name: "stem-app", path: "~/stem/app",     host: brahmi, in: ctx)
        stem.addRepo(name: "crawler",  path: "~/stem/crawler", host: brahmi, in: ctx)

        let medivalent = Project(name: "medivalent", path: "~/medivalent/app", host: sando); ctx.insert(medivalent)
        medivalent.addRepo(name: "medivalent", path: "~/medivalent/app", host: sando, in: ctx)

        // pasture, the predecessor, resting on the closet Pi.
        let pasture = Project(name: "pasture", path: "~/pasture/app", host: closetPi); ctx.insert(pasture)
        pasture.addRepo(name: "pasture-app", path: "~/pasture/app",    host: closetPi, in: ctx)
        pasture.addRepo(name: "worker",      path: "~/pasture/worker", host: closetPi, in: ctx)

        // Grounding: a couple of project skills for the inspector.
        ctx.insert(Skill(name: "House style", skillDescription: "match the surrounding code",
                         content: "Match the file's existing conventions.", project: shio))
        ctx.insert(Skill(name: "Ship small", skillDescription: "one focused change per commit",
                         content: "Keep diffs reviewable.", project: shio))

        try? ctx.save()

        // Recency so the overview ordering + ages read naturally (needs-you
        // sorts first regardless; this just breaks ties + sets the age labels).
        shio.lastOpenedAt       = .now
        samooh.lastOpenedAt     = Date(timeIntervalSinceNow: -1 * 3600)
        timebase.lastOpenedAt   = Date(timeIntervalSinceNow: -3 * 3600)
        stem.lastOpenedAt       = Date(timeIntervalSinceNow: -6 * 3600)
        medivalent.lastOpenedAt = Date(timeIntervalSinceNow: -2 * 24 * 3600)
        pasture.lastOpenedAt    = Date(timeIntervalSinceNow: -6 * 24 * 3600)
        try? ctx.save()

        // ── Git lines + agent presence + PRs (seeded; refresh no-ops in demo) ─
        let s = ProjectStatusStore.shared
        s.demoSetStatus(host: studio,   path: "~/shio/shio-app",    clean())
        s.demoSetStatus(host: studio,   path: "~/shio/landing",     clean())
        s.demoSetStatus(host: studio,   path: "~/shio/beta-worker", clean())
        s.demoSetStatus(host: brahmi,   path: "~/timebase/app",     clean())
        s.demoSetStatus(host: brahmi,   path: "~/timebase/api",     dirty(2))
        s.demoSetStatus(host: sando,    path: "~/samooh/web",       clean())
        s.demoSetStatus(host: sando,    path: "~/samooh/dhuni",     clean())
        s.demoSetStatus(host: sando,    path: "~/samooh/biriyani",  clean())
        s.demoSetStatus(host: brahmi,   path: "~/stem/app",         clean())
        s.demoSetStatus(host: brahmi,   path: "~/stem/crawler",     dirty(3))
        s.demoSetStatus(host: sando,    path: "~/medivalent/app",   clean())
        s.demoSetStatus(host: closetPi, path: "~/pasture/app",      clean())
        s.demoSetStatus(host: closetPi, path: "~/pasture/worker",   dirty(1))

        s.demoSetAgent(host: studio, repoName: "shio-app",
                       AgentSnapshot(agentName: "Claude Code", activity: .waiting,  detail: "Apply the schema migration?"))
        s.demoSetAgent(host: studio, repoName: "landing",
                       AgentSnapshot(agentName: "Claude Code", activity: .finished, detail: "committed “tighten the nav title”"))
        s.demoSetAgent(host: brahmi, repoName: "timebase-app",
                       AgentSnapshot(agentName: "Codex",       activity: .running,  detail: "running the test suite…"))
        s.demoSetAgent(host: sando,  repoName: "dhuni",
                       AgentSnapshot(agentName: "Aider",       activity: .waiting,  detail: "Restart the stream encoder?"))
        s.demoSetAgent(host: sando,  repoName: "biriyani",
                       AgentSnapshot(agentName: "Claude Code", activity: .finished, detail: "pushed 2 commits"))
        s.demoSetAgent(host: brahmi, repoName: "crawler",
                       AgentSnapshot(agentName: "Codex",       activity: .running,  detail: "indexing new trails…"))

        s.demoSetPRs(host: studio, path: "~/shio/shio-app",
                     [PullRequest(number: 5, title: "Projects-first overview", state: "OPEN", isDraft: false, headRefName: "overview")])
        s.demoSetPRs(host: brahmi, path: "~/timebase/app",
                     [PullRequest(number: 12, title: "Calendar countdowns", state: "OPEN", isDraft: false, headRefName: "countdowns")])
    }

    // MARK: Git probe helpers
    private static func clean(_ branch: String = "main") -> GitProbe {
        .ok(GitStatus(head: .branch(branch), upstream: "origin/\(branch)", ahead: 0, behind: 0,
                      staged: [], unstaged: [], untracked: [], conflicted: []))
    }
    private static func dirty(_ n: Int, _ branch: String = "main") -> GitProbe {
        let edits = (0..<n).map { GitStatus.Entry(path: "src/file\($0).swift", origPath: nil, change: .modified) }
        return .ok(GitStatus(head: .branch(branch), upstream: "origin/\(branch)", ahead: 0, behind: 0,
                             staged: [], unstaged: edits, untracked: [], conflicted: []))
    }
}
