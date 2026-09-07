import Foundation
import SwiftData

/// Display data for one repo row — shared by the Mac's rail/dashboard and the
/// iPad's dashboard. Built per-platform (`ProjectRows` on the Mac, the
/// `ActivityFeed` builder on iOS) from the same shared stores, so both
/// platforms render one repo the same way.
struct RepoRowVM: Identifiable {
    let id: PersistentIdentifier
    let repo: Repo
    let name: String
    let machines: String
    let git: GitProbe?
    /// True when `git` is a last-known cache past the stale window — the row
    /// dims its git segs so old numbers never read as live.
    var gitStale: Bool = false
    /// False when the repo has no checkout on any machine. Such a repo can't be
    /// probed or opened, so the row says so and offers to place it instead of
    /// showing an empty git line next to a machine name it doesn't actually have.
    var isPlaced: Bool = true
}

/// The aggregate one-liner shown on the dashboard's glance strip.
struct ProjectGlance {
    var changes: Int
    var repoCount: Int
    var age: String
}

extension ProjectGlance {
    /// Aggregates the glance strip from built rows — the same math on every
    /// platform, so it lives with the models, not in a per-platform builder.
    @MainActor
    static func make(for project: Project, rows: [RepoRowVM]) -> ProjectGlance {
        let changes = rows.reduce(0) { $0 + (GitLineFormatter.make($1.git).dirty) }
        return ProjectGlance(changes: changes, repoCount: rows.count, age: shioShortAge(project.lastOpenedAt))
    }
}

/// One row per machine carrying this project (the dashboard's machines card),
/// each with its repo spread.
struct MachineSummary: Identifiable {
    let id: String
    let name: String
    let detail: String      // "3 repos" or the lone repo's name
    let reachable: Bool
}
