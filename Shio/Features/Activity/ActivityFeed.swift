import SwiftUI
import SwiftData

/// One live agent event — a row in the Activity feed and the home AGENTS group.
struct ActivityItem: Identifiable {
    let id: String
    let activity: AgentActivity
    let agentName: String
    let detail: String?
    let repoName: String
    let projectName: String
    let age: String
    let repo: Repo
    /// The open phone session backing it — direct injection when present.
    let sessionID: UUID?
}

/// Builds the cross-project presence feed from live data: open phone sessions
/// (the output classifier) plus agents detected on remotes during the status
/// fetch. Pure reads — calling these in `body` registers Observation
/// dependencies, so the feed re-renders as agents flip state.
@MainActor
enum ActivityFeed {

    /// Presence for one repo. An open phone session's classifier wins (it's
    /// live); otherwise a remote agent seen by the status fetch. Waiting
    /// outranks running outranks finished.
    static func presence(for repo: Repo) -> (snap: AgentSnapshot, sessionID: UUID?, at: Date?)? {
        var candidates: [(AgentSnapshot, UUID?, Date?)] = []
        for checkout in (repo.checkouts ?? []) {
            for session in SessionStore.shared.sessions(forCheckout: checkout.persistentModelID) {
                if let snap = AgentStateStore.shared.snapshot(for: session.id), snap.activity != .none {
                    candidates.append((snap, session.id, AgentStateStore.shared.updatedAt[session.id]))
                }
            }
            if let host = checkout.host,
               let remote = ProjectStatusStore.shared.remoteAgent(host: host, repoName: repo.name) {
                candidates.append((remote, nil, nil))
            }
        }
        let ranked = candidates.sorted { rank($0.0.activity) < rank($1.0.activity) }
        return ranked.first.map { (snap: $0.0, sessionID: $0.1, at: $0.2) }
    }

    /// The cross-project feed: every repo with live presence, needs-you first.
    static func items(projects: [Project]) -> [ActivityItem] {
        var items: [ActivityItem] = []
        for project in projects {
            for repo in project.sortedRepos {
                guard let p = presence(for: repo) else { continue }
                items.append(ActivityItem(
                    id: "\(project.name)/\(repo.name)",
                    activity: p.snap.activity,
                    agentName: p.snap.agentName ?? "Agent",
                    detail: p.snap.detail,
                    repoName: repo.name,
                    projectName: project.name,
                    age: shioShortAge(p.at),
                    repo: repo,
                    sessionID: p.sessionID))
            }
        }
        return items.sorted { rank($0.activity) < rank($1.activity) }
    }

    /// Answer a blocked agent: straight into the open phone session when there
    /// is one, else the sovereign CloudKit Action the watching Mac injects —
    /// the same path as the lock-screen Approve/Deny buttons.
    static func reply(_ item: ActivityItem, key: String) {
        reply(repoName: item.repoName, sessionID: item.sessionID, key: key)
    }

    /// Same answer path when all you hold is a dashboard row, not a feed item.
    static func reply(repoName: String, sessionID: UUID?, key: String) {
        if let sid = sessionID,
           let session = SessionStore.shared.sessions.first(where: { $0.id == sid }) {
            session.viewModel.terminal.onInput?("\(key)\n")
        } else {
            let tmux = "shio-\(TmuxResume.scrubName(repoName))"
            Task { await CloudKitSignalService.shared.sendAction(sessionId: tmux, key: key) }
        }
    }

    private static func rank(_ a: AgentActivity) -> Int {
        switch a {
        case .waiting:  return 0
        case .running:  return 1
        case .finished: return 2
        case .none:     return 3
        }
    }
}

// MARK: - Dashboard builder (iOS)

/// The iOS twin of the Mac's `ProjectRows` builder — same shapes, no local
/// tmux: agent state comes from `presence(for:)` (open phone sessions + the
/// remotes seen by the status fetch), git/PRs from the shared status store.
extension ActivityFeed {

    static func rows(for project: Project) -> [RepoRowVM] {
        project.sortedRepos.map { repo in
            let p = presence(for: repo)
            return RepoRowVM(id: repo.persistentModelID, repo: repo, name: repo.name,
                             machines: machinesText(repo), git: gitProbe(repo),
                             gitStale: gitStale(repo),
                             agent: p?.snap.activity ?? .none,
                             agentName: p?.snap.agentName,
                             agentDetail: p?.snap.detail,
                             prs: prList(repo))
        }
    }

    static func glance(for project: Project, rows: [RepoRowVM]) -> ProjectGlance {
        .make(for: project, rows: rows)
    }

    /// One row per machine carrying this project. There is no "This Mac" from
    /// a phone — a checkout with no Host record lives somewhere Shio can't
    /// reach from here, so it can't become a row (never reachable-looking).
    static func machines(for project: Project) -> [MachineSummary] {
        var order: [String] = []
        var repoNames: [String: Set<String>] = [:]
        var reachable: [String: Bool] = [:]
        for repo in project.sortedRepos {
            for c in (repo.checkouts ?? []) {
                guard let h = c.host else { continue }
                if repoNames[h.name] == nil {
                    order.append(h.name)
                    repoNames[h.name] = []
                    // Same freshness window as the Mac builder — "seen lately",
                    // not a live probe.
                    reachable[h.name] = (h.lastConnectedAt ?? .distantPast)
                        .timeIntervalSinceNow > -3 * 24 * 3600
                }
                repoNames[h.name]?.insert(repo.name)
            }
        }
        return order.map { name in
            let repos = repoNames[name] ?? []
            return MachineSummary(id: name, name: name,
                                  detail: repos.count == 1 ? (repos.first ?? "")
                                      : "\(repos.count) repo\(repos.count == 1 ? "" : "s")",
                                  reachable: reachable[name] ?? false)
        }
    }

    /// "mini · pi" — where the repo lives. Hosts only; a checkout with no
    /// Host record is unreachable from here (same fallback as the Home cards).
    private static func machinesText(_ repo: Repo) -> String {
        let names = (repo.checkouts ?? []).compactMap { $0.host?.name }
        var seen = Set<String>(); var unique: [String] = []
        for n in names where !seen.contains(n) { seen.insert(n); unique.append(n) }
        return unique.isEmpty ? "no machine" : unique.joined(separator: " · ")
    }

    private static func gitProbe(_ repo: Repo) -> GitProbe? {
        guard let c = repo.activeCheckout else { return nil }
        return ProjectStatusStore.shared.status(forHost: c.host, path: c.path)?.probe
    }

    private static func gitStale(_ repo: Repo) -> Bool {
        guard let c = repo.activeCheckout else { return false }
        return ProjectStatusStore.shared.isStale(forHost: c.host, path: c.path)
    }

    private static func prList(_ repo: Repo) -> [PullRequest] {
        guard let c = repo.activeCheckout else { return [] }
        return ProjectStatusStore.shared.prList(forHost: c.host, path: c.path)
    }
}
