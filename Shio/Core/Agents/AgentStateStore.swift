import Foundation
import Observation

/// Live, in-memory map of per-session agent state, fed by output-watching in
/// each `SessionViewModel`. The Agents tab and per-project badges observe it.
///
/// Ephemeral by design — agent state is meaningless once a session is gone,
/// so it never touches SwiftData. (Phase 6 mirrors a minimal slice to the
/// App Group so the away-watcher / widgets can read it cross-process.)
@Observable
@MainActor
final class AgentStateStore {
    static let shared = AgentStateStore()

    /// Keyed by `SessionStore.Session.id`.
    private(set) var snapshots: [UUID: AgentSnapshot] = [:]
    /// When each snapshot last changed — drives "waiting for 3m" style copy
    /// and ordering (most-recently-blocked first).
    private(set) var updatedAt: [UUID: Date] = [:]

    private init() {}

    /// Merge a freshly classified snapshot for a session. The agent name is
    /// sticky: once we've identified the tool, we keep it even if its banner
    /// scrolls out of the tail.
    func update(sessionID: UUID, _ incoming: AgentSnapshot) {
        var merged = incoming
        if merged.agentName == nil {
            merged.agentName = snapshots[sessionID]?.agentName
        }
        let previous = snapshots[sessionID]
        if previous != merged {
            snapshots[sessionID] = merged
            updatedAt[sessionID] = Date()
        }
    }

    func snapshot(for id: UUID) -> AgentSnapshot? { snapshots[id] }

    func clear(_ id: UUID) {
        snapshots[id] = nil
        updatedAt[id] = nil
    }

    /// Sessions with a live agent (anything but `.none`), most-recently
    /// changed first, with `.waiting` floated to the top.
    var liveSessionIDs: [UUID] {
        snapshots
            .filter { $0.value.activity != .none }
            .sorted { lhs, rhs in
                let lw = lhs.value.activity == .waiting
                let rw = rhs.value.activity == .waiting
                if lw != rw { return lw }
                return (updatedAt[lhs.key] ?? .distantPast) > (updatedAt[rhs.key] ?? .distantPast)
            }
            .map(\.key)
    }

    /// Count of agents currently blocked on the user — drives the tab badge.
    var waitingCount: Int {
        snapshots.values.filter { $0.activity == .waiting }.count
    }
}
