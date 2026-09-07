import Foundation

/// Display-ready git line for a project card, derived from a `GitProbe`. Pure
/// (no SwiftUI/colors) so it's shared across iOS and Mac, which render it in
/// their own dialects. `nil` probe = not fetched yet.
struct GitLineModel: Equatable {
    /// `notPlaced` = the repo exists but has no checkout on any machine, so
    /// there is nothing to probe. Distinct from `loading` (a probe is coming)
    /// and `unreachable` (a machine we can't reach right now) — those two both
    /// resolve on their own, this one only resolves when the user places it.
    enum State: Equatable { case clean, dirty, noRepo, gitMissing, loading, unreachable, notPlaced }
    var branch: String
    var ahead: Int
    var behind: Int
    var dirty: Int
    var state: State
    /// True when this is a last-known cache older than the stale window —
    /// surfaces dim the line ("·· branch", lowered opacity) so old numbers
    /// never masquerade as live ones.
    var stale: Bool = false

    /// True when there's a real branch + counts worth showing chips for.
    var hasTracking: Bool { state == .clean || state == .dirty }

    /// The branch label with the staleness prefix applied.
    var branchLabel: String { stale ? "·· \(branch)" : branch }
}

enum GitLineFormatter {
    /// `placed` is false when the repo has no checkout anywhere. Without it an
    /// unplaced repo sits on "—" forever, reading as a probe that never lands
    /// rather than as a repo that was never given a location.
    static func make(_ probe: GitProbe?, stale: Bool = false, placed: Bool = true) -> GitLineModel {
        guard placed else {
            return GitLineModel(branch: "not on any machine", ahead: 0, behind: 0,
                                dirty: 0, state: .notPlaced)
        }
        guard let probe else {
            return GitLineModel(branch: "—", ahead: 0, behind: 0, dirty: 0, state: .loading)
        }
        switch probe {
        case .ok(let s):
            let branch: String
            switch s.head {
            case .branch(let n):    branch = n
            case .detached(let oid): branch = oid.isEmpty ? "detached" : "@\(oid)"
            case .unborn:           branch = "no commits"
            }
            return GitLineModel(branch: branch, ahead: s.ahead, behind: s.behind,
                                dirty: s.dirtyCount, state: s.isClean ? .clean : .dirty,
                                stale: stale)
        case .notARepo:
            return GitLineModel(branch: "not a repo", ahead: 0, behind: 0, dirty: 0, state: .noRepo)
        case .gitMissing:
            return GitLineModel(branch: "git not found", ahead: 0, behind: 0, dirty: 0, state: .gitMissing)
        case .timedOut, .unreachable, .failed:
            return GitLineModel(branch: "—", ahead: 0, behind: 0, dirty: 0, state: .unreachable)
        }
    }
}
