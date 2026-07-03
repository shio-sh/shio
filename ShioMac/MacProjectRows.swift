import SwiftUI
import SwiftData

/// Builds the live row/glance view-models (`RepoRowVM` / `ProjectGlance` /
/// `MachineSummary`, shared in Core/Status) for a project from THIS Mac's
/// singletons — the local tmux agent monitor + git status store. Pure reads —
/// calling these during a view's `body` registers Observation dependencies,
/// so rows re-render as agents flip state or git status lands.
@MainActor
enum ProjectRows {

    static func rows(for project: Project) -> [RepoRowVM] {
        project.sortedRepos.map { repo in
            let snap = agentSnapshot(repo)
            return RepoRowVM(id: repo.persistentModelID, repo: repo, name: repo.name,
                             machines: machinesText(repo), git: gitProbe(repo),
                             gitStale: gitStale(repo),
                             agent: snap?.activity ?? .none,
                             agentName: snap?.agentName,
                             agentDetail: snap?.detail,
                             prs: prList(repo))
        }
    }

    static func glance(for project: Project, rows: [RepoRowVM]) -> ProjectGlance {
        .make(for: project, rows: rows)
    }

    /// The project's loudest agent state — ⚑ wins over ⠋ wins over ✓.
    static func activity(_ project: Project) -> AgentActivity {
        let acts = project.sortedRepos.map { agentSnapshot($0)?.activity ?? .none }
        if acts.contains(.waiting) { return .waiting }
        if acts.contains(.running) { return .running }
        if acts.contains(.finished) { return .finished }
        return .none
    }

    /// Local agents (this Mac's tmux) win; otherwise a remote agent detected
    /// during the status fetch on any of the repo's machines.
    static func agentSnapshot(_ repo: Repo) -> AgentSnapshot? {
        let checkouts = repo.checkouts ?? []
        let hasLocal = checkouts.isEmpty || checkouts.contains { $0.host.map(MacSelfHost.isThisMac) ?? true }
        if hasLocal, let local = MacProjectAgentMonitor.shared.snapshot(forProjectNamed: repo.name) {
            return local
        }
        for c in checkouts {
            if let h = c.host, !MacSelfHost.isThisMac(h),
               let remote = ProjectStatusStore.shared.remoteAgent(host: h, repoName: repo.name) {
                return remote
            }
        }
        return nil
    }

    static func prList(_ repo: Repo) -> [PullRequest] {
        guard let c = repo.activeCheckout else { return [] }
        return ProjectStatusStore.shared.prList(forHost: c.host, path: c.path)
    }

    static func gitProbe(_ repo: Repo) -> GitProbe? {
        guard let c = repo.activeCheckout else { return nil }
        return ProjectStatusStore.shared.status(forHost: c.host, path: c.path)?.probe
    }

    static func gitStale(_ repo: Repo) -> Bool {
        guard let c = repo.activeCheckout else { return false }
        return ProjectStatusStore.shared.isStale(forHost: c.host, path: c.path)
    }

    /// One row per machine carrying this project (the dashboard's machines
    /// card): This Mac first, each with its repo spread.
    static func machines(for project: Project) -> [MachineSummary] {
        var order: [String] = []
        var repoNames: [String: Set<String>] = [:]
        var reachable: [String: Bool] = [:]
        func add(_ name: String, repo: String, fresh: Bool) {
            if repoNames[name] == nil { order.append(name); repoNames[name] = []; reachable[name] = fresh }
            repoNames[name]?.insert(repo)
        }
        for repo in project.sortedRepos {
            let checkouts = repo.checkouts ?? []
            if checkouts.isEmpty { add("This Mac", repo: repo.name, fresh: true) }
            for c in checkouts {
                if let h = c.host, !MacSelfHost.isThisMac(h) {
                    let fresh = (h.lastConnectedAt ?? .distantPast).timeIntervalSinceNow > -3 * 24 * 3600
                    add(h.name, repo: repo.name, fresh: fresh)
                } else {
                    add("This Mac", repo: repo.name, fresh: true)
                }
            }
        }
        // This Mac leads; everything else keeps first-seen order.
        let sorted = order.sorted { a, _ in a == "This Mac" }
        return sorted.map { name in
            let repos = repoNames[name] ?? []
            return MachineSummary(id: name, name: name,
                                  detail: repos.count == 1 ? (repos.first ?? "")
                                      : "\(repos.count) repo\(repos.count == 1 ? "" : "s")",
                                  reachable: reachable[name] ?? false)
        }
    }

    static func machinesText(_ repo: Repo) -> String {
        let names = (repo.checkouts ?? []).map { c -> String in
            guard let h = c.host else { return "this mac" }
            return MacSelfHost.isThisMac(h) ? "this mac" : h.name
        }
        var seen = Set<String>(); var unique: [String] = []
        for n in names where !seen.contains(n) { seen.insert(n); unique.append(n) }
        return unique.isEmpty ? "this mac" : unique.joined(separator: " · ")
    }
}
