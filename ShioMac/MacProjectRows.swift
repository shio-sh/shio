import SwiftUI
import SwiftData

/// Builds the live row/glance view-models (`RepoRowVM` / `ProjectGlance` /
/// `MachineSummary`, shared in Core/Status) for a project from THIS Mac's
/// git status store. Pure reads — calling these during a view's `body`
/// registers Observation dependencies, so rows re-render as git status lands.
@MainActor
enum ProjectRows {

    static func rows(for project: Project) -> [RepoRowVM] {
        project.sortedRepos.map { repo in
            RepoRowVM(id: repo.persistentModelID, repo: repo, name: repo.name,
                     machines: machinesText(repo), git: gitProbe(repo),
                     gitStale: gitStale(repo), isPlaced: repo.activeCheckout != nil)
        }
    }

    static func glance(for project: Project, rows: [RepoRowVM]) -> ProjectGlance {
        .make(for: project, rows: rows)
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
            // A repo with no checkout lives on no machine yet — listing it under
            // "This Mac" invented a location and hid the fact it needs placing.
            let checkouts = repo.checkouts ?? []
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
        // Empty means the repo genuinely isn't checked out anywhere. Defaulting
        // to "this mac" here claimed a location that doesn't exist, which read
        // as a broken git probe rather than a repo waiting to be placed.
        return unique.joined(separator: " · ")
    }
}
