import Foundation
import Observation
import SwiftUI
import SwiftData
import WidgetKit

/// Holds every live `SessionViewModel` across every host the user is
/// connected to. UI consumes the store via `@Bindable` / `@Environment`
/// and can: enumerate sessions, switch between them, spawn an additional
/// session on the same host, or close one.
///
/// The store is a singleton because:
///   - Sessions must outlive the `TerminalScene` that's currently showing
///     them (so backgrounding a session via swipe-down doesn't tear down
///     SSH and force a tmux re-attach).
///   - Multiple entry points (host-tap, App Intent, widget) need to
///     reach the same store.
@Observable
@MainActor
final class SessionStore {
    static let shared = SessionStore()

    /// One live SSH/tmux session. Identity is `id`; we never mutate it.
    /// Equality and hashing are by id so swift collections behave.
    final class Session: Identifiable, Equatable, Hashable {
        let id: UUID = UUID()
        let hostID: PersistentIdentifier
        let displayName: String
        let viewModel: SessionViewModel

        init(hostID: PersistentIdentifier, displayName: String, viewModel: SessionViewModel) {
            self.hostID = hostID
            self.displayName = displayName
            self.viewModel = viewModel
        }

        static func == (lhs: Session, rhs: Session) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// All live sessions, in the order the user created them.
    private(set) var sessions: [Session] = []

    /// The session that is currently being displayed in `TerminalScene`.
    /// nil = no terminal scene is up.
    var activeSession: Session?

    private init() {}

    /// Convenience: sessions for a particular host, in creation order.
    func sessions(for hostID: PersistentIdentifier) -> [Session] {
        sessions.filter { $0.hostID == hostID }
    }

    /// Open the first existing session for this host (if any). If none
    /// exists, create one with tmux session index 0 (the user's
    /// pre-multi-session name, so existing tmux sessions on the Mac are
    /// picked up). Sets it as active.
    @discardableResult
    func openOrCreate(host: Host) -> Session {
        if let existing = sessions.first(where: { $0.hostID == host.persistentModelID }) {
            activeSession = existing
            return existing
        }
        return createNewSession(on: host)
    }

    /// Always create a new session on this host. The tmux session name
    /// picks the lowest unused index for the host, so concurrent tabs
    /// on the same Mac persist independently.
    @discardableResult
    func createNewSession(on host: Host) -> Session {
        // Push to the widget cache so a fresh "recent hosts" surface
        // is available to home-screen widgets without IPC. Reload the
        // widget so the home-screen tile reflects the change.
        WidgetSharedState.recordConnect(
            id: "\(host.persistentModelID)",
            name: host.name
        )
        WidgetCenter.shared.reloadAllTimelines()
        let existing = sessions(for: host.persistentModelID)
        // Choose the next free index: 0 if no sessions yet, otherwise
        // max-existing-index + 1. Reusing zero is intentional — the
        // single-session user's existing `shio-<host>` tmux survives.
        let nextIndex: Int = existing.isEmpty
            ? 0
            : ((existing.compactMap { $0.viewModel.sessionIndex }.max() ?? 0) + 1)

        let vm = SessionViewModel(
            configuration: host.makeClientConfiguration(),
            persistenceMode: host.persistenceMode,
            sessionIndex: nextIndex
        )
        let displayName = nextIndex == 0
            ? host.name
            : "\(host.name) (\(nextIndex + 1))"
        let session = Session(
            hostID: host.persistentModelID,
            displayName: displayName,
            viewModel: vm
        )
        sessions.append(session)
        activeSession = session
        return session
    }

    /// Tear down a session: stop the SSH client, remove from the list,
    /// and pick a sensible next-active. Tmux on the remote keeps the
    /// session itself alive, so the user can reconnect later.
    func close(_ session: Session) async {
        await LiveActivityController.shared.end(sessionID: session.id, finalState: "ended")
        await session.viewModel.stop()
        sessions.removeAll { $0.id == session.id }
        if activeSession?.id == session.id {
            activeSession = sessions.last  // jump to the most recently created remaining
        }
    }

    /// Make a session the active one without creating or destroying.
    func switchTo(_ session: Session) {
        guard sessions.contains(session) else { return }
        activeSession = session
    }

    /// Push fresh state into every live Live Activity. Called on app
    /// foregrounding so the lock screen can't sit on a stale "Connected"
    /// claim after iOS suspended us through a connection failure —
    /// any session whose SSH client is no longer `.connected` gets its
    /// activity ended.
    func reconcileLiveActivities() async {
        for session in sessions {
            let id = session.id
            switch session.viewModel.state {
            case .connected:
                await LiveActivityController.shared.update(
                    sessionID: id,
                    connectionState: "connected"
                )
            case .reconnecting:
                await LiveActivityController.shared.update(
                    sessionID: id,
                    connectionState: "reconnecting"
                )
            case .disconnected, .idle:
                await LiveActivityController.shared.end(
                    sessionID: id,
                    finalState: "disconnected"
                )
            default:
                break
            }
        }
    }
}
