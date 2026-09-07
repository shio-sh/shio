import SwiftUI
import SwiftData

/// The iOS twin of the Mac's `ProjectRows` builder — same shapes, no local
/// tmux: git state comes from the shared status store.
@MainActor
enum ActivityFeed {

    static func rows(for project: Project) -> [RepoRowVM] {
        project.sortedRepos.map { repo in
            RepoRowVM(id: repo.persistentModelID, repo: repo, name: repo.name,
                     machines: machinesText(repo), git: gitProbe(repo),
                     gitStale: gitStale(repo))
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
}
