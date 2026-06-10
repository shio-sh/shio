import Foundation

/// Display-ready git line for a project card, derived from a `GitProbe`. Pure
/// (no SwiftUI/colors) so it's shared across iOS and Mac, which render it in
/// their own dialects. `nil` probe = not fetched yet.
struct GitLineModel: Equatable {
    enum State: Equatable { case clean, dirty, noRepo, gitMissing, loading, unreachable }
    var branch: String
    var ahead: Int
    var behind: Int
    var dirty: Int
    var state: State

    /// True when there's a real branch + counts worth showing chips for.
    var hasTracking: Bool { state == .clean || state == .dirty }
}

enum GitLineFormatter {
    static func make(_ probe: GitProbe?) -> GitLineModel {
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
                                dirty: s.dirtyCount, state: s.isClean ? .clean : .dirty)
        case .notARepo:
            return GitLineModel(branch: "not a repo", ahead: 0, behind: 0, dirty: 0, state: .noRepo)
        case .gitMissing:
            return GitLineModel(branch: "git not found", ahead: 0, behind: 0, dirty: 0, state: .gitMissing)
        case .timedOut, .unreachable, .failed:
            return GitLineModel(branch: "—", ahead: 0, behind: 0, dirty: 0, state: .unreachable)
        }
    }
}
