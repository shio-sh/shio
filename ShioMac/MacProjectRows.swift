import SwiftUI
import SwiftData

/// Display data for one repo row — shared by the rail (REPOS/AGENTS groups)
/// and the dashboard's conversations card.
struct RepoRowVM: Identifiable {
    let id: PersistentIdentifier
    let repo: Repo
    let name: String
    let machines: String
    let git: GitProbe?
    let agent: AgentActivity
    var agentName: String? = nil
    var agentDetail: String? = nil
    var prs: [PullRequest] = []
}

/// The aggregate one-liner shown on the dashboard's glance strip.
struct ProjectGlance {
    var changes: Int
    var working: Int
    var needsYou: Int
    var prs: Int
    var repoCount: Int
    var age: String
}

/// Builds the live row/glance view-models for a project from the shared
/// singletons (local tmux agent monitor + git status store). Pure reads —
/// calling these during a view's `body` registers Observation dependencies,
/// so rows re-render as agents flip state or git status lands.
@MainActor
enum ProjectRows {

    static func rows(for project: Project) -> [RepoRowVM] {
        project.sortedRepos.map { repo in
            let snap = agentSnapshot(repo)
            return RepoRowVM(id: repo.persistentModelID, repo: repo, name: repo.name,
                             machines: machinesText(repo), git: gitProbe(repo),
                             agent: snap?.activity ?? .none,
                             agentName: snap?.agentName,
                             agentDetail: snap?.detail,
                             prs: prList(repo))
        }
    }

    static func glance(for project: Project, rows: [RepoRowVM]) -> ProjectGlance {
        let changes = rows.reduce(0) { $0 + (GitLineFormatter.make($1.git).dirty) }
        let working = rows.filter { $0.agent == .running }.count
        let needs   = rows.filter { $0.agent == .waiting }.count
        let prCount = rows.reduce(0) { $0 + $1.prs.filter { $0.state == "OPEN" }.count }
        return ProjectGlance(changes: changes, working: working, needsYou: needs,
                             prs: prCount, repoCount: rows.count, age: shioShortAge(project.lastOpenedAt))
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
