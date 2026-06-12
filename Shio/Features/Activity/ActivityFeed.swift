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
        if let sid = item.sessionID,
           let session = SessionStore.shared.sessions.first(where: { $0.id == sid }) {
            session.viewModel.terminal.onInput?("\(key)\n")
        } else {
            let tmux = "shio-\(TmuxResume.scrubName(item.repoName))"
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
