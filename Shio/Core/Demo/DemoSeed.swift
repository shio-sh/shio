import Foundation
import SwiftData

/// Fills the in-memory demo store with curated, easter-egg projects, machines,
/// and agents so we can take real App Store screenshots of the actual app — not
/// a mockup. Runs only when ``DemoMode/isActive`` (the Demo schemes), called
/// once from each app's launch task.
///
/// This is screenshot set-dressing, not product data — edit the names, agents,
/// and git states freely. The live refreshers (`ProjectStatusStore.refresh`,
/// `MacProjectAgentMonitor.start`) are no-ops in demo mode, so whatever we set
/// here is exactly what shows.
@MainActor
enum DemoSeed {
    static func run() {
        let ctx = ShioModelContainer.shared.mainContext
        guard (try? ctx.fetchCount(FetchDescriptor<Project>())) == 0 else { return }   // idempotent

        // ── Machines (easter eggs; all warm except the sleepy Pi) ───────────
        let studio      = Host(name: "studio",       hostname: "studio.local",                username: "amrith", kind: .directSSH)
        let deepThought = Host(name: "deep-thought", hostname: "deep-thought.tail9c2e.ts.net", username: "amrith", kind: .tailscale)
        let tardis      = Host(name: "tardis",       hostname: "tardis.fly.dev",               username: "root",   kind: .directSSH)
        let pi          = Host(name: "pi-hole",      hostname: "pihole.tail9c2e.ts.net",       username: "pi",     kind: .tailscale)
        studio.lastConnectedAt      = .now
        deepThought.lastConnectedAt = .now
        tardis.lastConnectedAt      = .now
        pi.lastConnectedAt          = Date(timeIntervalSinceNow: -5 * 24 * 3600)   // asleep → hollow dot
        [studio, deepThought, tardis, pi].forEach(ctx.insert)

        // ── Projects → repos → checkouts (host set, so presence resolves) ───
        let shio = Project(name: "shio", path: "~/shio/shio-app", host: studio); ctx.insert(shio)
        shio.addRepo(name: "shio-app",    path: "~/shio/shio-app",    host: studio, cloneURL: "git@github.com:shio-sh/shio.git", in: ctx)
        shio.addRepo(name: "landing",     path: "~/shio/landing",     host: studio, in: ctx)
        shio.addRepo(name: "beta-worker", path: "~/shio/beta-worker", host: studio, in: ctx)

        let pasture = Project(name: "pasture", path: "~/pasture/app", host: deepThought); ctx.insert(pasture)
        pasture.addRepo(name: "pasture-app", path: "~/pasture/app",    host: deepThought, in: ctx)
        pasture.addRepo(name: "worker",      path: "~/pasture/worker", host: deepThought, in: ctx)

        let saltmine = Project(name: "saltmine", path: "~/saltmine/miner", host: tardis); ctx.insert(saltmine)
        saltmine.addRepo(name: "miner",  path: "~/saltmine/miner",  host: tardis, in: ctx)
        saltmine.addRepo(name: "ledger", path: "~/saltmine/ledger", host: tardis, in: ctx)

        let lighthouse = Project(name: "lighthouse", path: "~/lighthouse/beacon", host: pi); ctx.insert(lighthouse)
        lighthouse.addRepo(name: "beacon", path: "~/lighthouse/beacon", host: pi, in: ctx)

        // Grounding: a couple of project skills for the inspector.
        ctx.insert(Skill(name: "House style", skillDescription: "match the surrounding code",
                         content: "Match the file's existing conventions.", project: shio))
        ctx.insert(Skill(name: "Ship small", skillDescription: "one focused change per commit",
                         content: "Keep diffs reviewable.", project: shio))

        try? ctx.save()

        // Stagger recency so the overview ordering + ages read naturally.
        shio.lastOpenedAt       = .now
        pasture.lastOpenedAt    = Date(timeIntervalSinceNow: -3 * 3600)
        saltmine.lastOpenedAt   = Date(timeIntervalSinceNow: -26 * 3600)
        lighthouse.lastOpenedAt = Date(timeIntervalSinceNow: -5 * 24 * 3600)
        try? ctx.save()

        // ── Git lines + agent presence + PRs (live stores; refresh is a
        //    no-op in demo, so these stick) ───────────────────────────────────
        let s = ProjectStatusStore.shared
        s.demoSetStatus(host: studio,      path: "~/shio/shio-app",       clean())
        s.demoSetStatus(host: studio,      path: "~/shio/landing",        clean())
        s.demoSetStatus(host: studio,      path: "~/shio/beta-worker",    clean())
        s.demoSetStatus(host: deepThought, path: "~/pasture/app",         clean())
        s.demoSetStatus(host: deepThought, path: "~/pasture/worker",      dirty(2))
        s.demoSetStatus(host: tardis,      path: "~/saltmine/miner",      clean())
        s.demoSetStatus(host: tardis,      path: "~/saltmine/ledger",     dirty(3))
        s.demoSetStatus(host: pi,          path: "~/lighthouse/beacon",   clean())

        s.demoSetAgent(host: studio,      repoName: "shio-app",
                       AgentSnapshot(agentName: "Claude Code", activity: .waiting,  detail: "Apply the schema migration?"))
        s.demoSetAgent(host: studio,      repoName: "landing",
                       AgentSnapshot(agentName: "Claude Code", activity: .finished, detail: "committed “tighten the nav title”"))
        s.demoSetAgent(host: deepThought, repoName: "pasture-app",
                       AgentSnapshot(agentName: "Codex",       activity: .running,  detail: "running the test suite…"))
        s.demoSetAgent(host: tardis,      repoName: "ledger",
                       AgentSnapshot(agentName: "Aider",       activity: .waiting,  detail: "Overwrite the prod config?"))
        s.demoSetAgent(host: pi,          repoName: "beacon",
                       AgentSnapshot(agentName: "Claude Code", activity: .finished, detail: "pushed 2 commits"))

        s.demoSetPRs(host: studio, path: "~/shio/shio-app",
                     [PullRequest(number: 5, title: "Projects-first overview", state: "OPEN",
                                  isDraft: false, headRefName: "overview")])
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
