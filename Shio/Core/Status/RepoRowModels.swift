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

/// One project as it appears in the zoomed-out overview.
///
/// Built from the same rows and glance the dashboard already computes, so the
/// overview cannot drift from the project view or from the iPhone's Home — all
/// three read one model. Platform-agnostic on purpose: the Mac and iPad render
/// this, and the iPhone's Home card shows the same facts.
struct ProjectOverviewItem: Identifiable {
    let id: PersistentIdentifier
    let project: Project
    let glance: ProjectGlance
    /// "⎇ main · 5 uncommitted" — the first repo's state, which is the whole
    /// story for the single-repo projects most people have.
    let headline: String
    /// "3 repos · this mac" — shape and where it lives.
    let detail: String

    @MainActor
    static func make(project: Project, rows: [RepoRowVM]) -> ProjectOverviewItem {
        let glance = ProjectGlance.make(for: project, rows: rows)

        let headline: String
        if rows.isEmpty {
            headline = "no repos yet"
        } else if let first = rows.first, !first.isPlaced {
            headline = "not on any machine"
        } else {
            let line = GitLineFormatter.make(rows.first?.git, stale: rows.first?.gitStale ?? false)
            if glance.changes > 0 {
                headline = "⎇ \(line.branch) · \(glance.changes) uncommitted"
            } else if line.hasTracking {
                headline = "⎇ \(line.branch) · clean"
            } else {
                headline = "⎇ \(line.branch)"
            }
        }

        // Machines, deduplicated, in first-seen order — the same names the
        // repo rows use, so nothing reads differently between surfaces.
        var seen = Set<String>()
        var machines: [String] = []
        for row in rows where !row.machines.isEmpty {
            for name in row.machines.components(separatedBy: " · ")
            where !name.isEmpty && !seen.contains(name) {
                seen.insert(name)
                machines.append(name)
            }
        }
        let repoPart = rows.count == 1 ? "1 repo" : "\(rows.count) repos"
        let detail = machines.isEmpty ? repoPart
                                      : "\(repoPart) · \(machines.joined(separator: " · "))"

        return ProjectOverviewItem(id: project.persistentModelID, project: project,
                                   glance: glance, headline: headline, detail: detail)
    }
}
