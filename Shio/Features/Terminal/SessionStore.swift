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
        /// The project (repo) this session belongs to, or nil for a
        /// host-level raw shell opened from the Hosts tab.
        let projectID: PersistentIdentifier?
        /// The specific machine checkout this session runs on. Distinguishes the
        /// same project open on two machines; nil for a host-level shell.
        let checkoutID: PersistentIdentifier?
        let displayName: String
        let viewModel: SessionViewModel

        init(hostID: PersistentIdentifier, projectID: PersistentIdentifier? = nil, checkoutID: PersistentIdentifier? = nil, displayName: String, viewModel: SessionViewModel) {
            self.hostID = hostID
            self.projectID = projectID
            self.checkoutID = checkoutID
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

    /// True while a `TerminalScene` is on screen (it flips this from
    /// onAppear/onDisappear). Lets `ConnectRouter` know whether routing needs
    /// to present a terminal or just switch `activeSession`.
    var isTerminalPresented = false

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
        if let existing = sessions.first(where: { $0.hostID == host.persistentModelID && $0.projectID == nil }) {
            activeSession = existing
            return existing
        }
        return createNewSession(on: host)
    }

    /// Sessions belonging to a particular project (across all its checkouts),
    /// in creation order. Drives the project-wide agent badge.
    func sessions(forProject projectID: PersistentIdentifier) -> [Session] {
        sessions.filter { $0.projectID == projectID }
    }

    /// Sessions on one specific machine checkout — the bucket that scopes tmux
    /// session indices, so the same project open on two machines stays distinct.
    func sessions(forCheckout checkoutID: PersistentIdentifier) -> [Session] {
        sessions.filter { $0.checkoutID == checkoutID }
    }

    /// Open the first existing session for this project (its active repo's active
    /// checkout), or create one. Returns nil if there's no usable checkout yet.
    @discardableResult
    func openOrCreate(project: Project) -> Session? {
        if let repo = project.activeRepo { return openOrCreate(repo: repo) }
        guard let checkout = project.activeCheckout else { return nil }
        return openOrCreate(project: project, checkout: checkout)
    }

    /// Open or create a session for a specific repo (the project-first path), on
    /// its active checkout. The tmux session is named per-repo.
    @discardableResult
    func openOrCreate(repo: Repo) -> Session? {
        guard let checkout = repo.activeCheckout, let host = checkout.host else { return nil }
        if let existing = sessions.first(where: { $0.checkoutID == checkout.persistentModelID }) {
            activeSession = existing
            return existing
        }
        return createNewSession(on: host, project: repo.project, checkout: checkout, repoName: repo.name)
    }

    /// Open or create a session for a specific checkout of a project — the path
    /// the machine switcher uses to reach a project on a chosen machine.
    @discardableResult
    func openOrCreate(project: Project, checkout: ProjectCheckout) -> Session? {
        guard let host = checkout.host else { return nil }
        if let existing = sessions.first(where: { $0.checkoutID == checkout.persistentModelID }) {
            activeSession = existing
            return existing
        }
        return createNewSession(on: host, project: project, checkout: checkout)
    }

    /// Always create a new session on this host. The tmux session name
    /// picks the lowest unused index for the host, so concurrent tabs
    /// on the same Mac persist independently.
    /// Create a new session on this host. If `project` is given, the tmux
    /// session is named `shio-<project>` and opened in the repo directory;
    /// otherwise it is a host-level shell (`shio-<host>`). Indices are scoped
    /// to the (host[, project]) bucket so concurrent sessions persist
    /// independently. Reusing index 0 is intentional — the single-session
    /// user's existing tmux session survives.
    @discardableResult
    func createNewSession(on host: Host, project: Project? = nil, checkout: ProjectCheckout? = nil, repoName: String? = nil) -> Session {
        // Contextual notification opt-in: away-push is *for* sessions, so this
        // is the moment to ask — not at first launch. The system prompts only
        // once; subsequent calls are no-ops.
        Task {
            await PushService.shared.requestAuthorizationAndRegister()
            await CloudKitSignalService.shared.ensureSubscription()
        }

        // Prefer the synced per-device id when the host has one — it survives
        // a store rebuild (CloudKit re-mirror), which regenerates every
        // persistentModelID and would strand the widget's links.
        WidgetSharedState.recordConnect(
            id: host.deviceID ?? "\(host.persistentModelID)",
            name: host.name
        )
        WidgetCenter.shared.reloadAllTimelines()

        // Index bucket is scoped to the specific checkout (host + path), so the
        // same project open on two machines keeps independent tmux indices.
        let bucket: [Session]
        if let checkout {
            bucket = sessions(forCheckout: checkout.persistentModelID)
        } else {
            bucket = sessions.filter { $0.hostID == host.persistentModelID && $0.projectID == nil }
        }
        let nextIndex: Int = bucket.isEmpty
            ? 0
            : ((bucket.compactMap { $0.viewModel.sessionIndex }.max() ?? 0) + 1)

        let tmuxName: String?
        let startDir: String?
        let cloneURL: String?
        let baseName: String
        if let project {
            // Name tmux per-repo so different repos in one project are independent.
            let base = repoName ?? project.name
            let scrubbed = TmuxResume.scrubName(base)
            tmuxName = nextIndex == 0 ? "shio-\(scrubbed)" : "shio-\(scrubbed)-\(nextIndex)"
            // Read the working dir from the active checkout; fall back to the
            // legacy project.path for safety during the migration window.
            startDir = checkout?.path ?? project.path
            cloneURL = checkout?.repo?.cloneURL ?? project.effectiveCloneURL
            baseName = base
            project.lastOpenedAt = .now
            checkout?.repo?.lastOpenedAt = .now
            checkout?.lastOpenedAt = .now
        } else {
            tmuxName = nil      // SessionViewModel derives `shio-<host>`
            startDir = nil
            cloneURL = nil
            baseName = host.name
        }

        let vm = SessionViewModel(
            configuration: host.makeClientConfiguration(),
            persistenceMode: checkout?.persistenceModeOverride ?? project?.persistenceModeOverride ?? host.persistenceMode,
            sessionIndex: nextIndex,
            tmuxSessionName: tmuxName,
            startDirectory: startDir,
            cloneURL: cloneURL
        )
        let displayName = nextIndex == 0 ? baseName : "\(baseName) (\(nextIndex + 1))"
        let session = Session(
            hostID: host.persistentModelID,
            projectID: project?.persistentModelID,
            checkoutID: checkout?.persistentModelID,
            displayName: displayName,
            viewModel: vm
        )
        vm.ownerSessionID = session.id   // lets output-watching key AgentStateStore
        sessions.append(session)
        activeSession = session
        return session
    }

    /// Tear down a session: stop the SSH client, remove from the list,
    /// and pick a sensible next-active. Tmux on the remote keeps the
    /// session itself alive, so the user can reconnect later.
    func close(_ session: Session) async {
        await LiveActivityController.shared.end(sessionID: session.id, finalState: "ended")
        AgentStateStore.shared.clear(session.id)
        await session.viewModel.stop()
        sessions.removeAll { $0.id == session.id }
        if activeSession?.id == session.id {
            activeSession = sessions.last  // jump to the most recently created remaining
        }
    }

    /// On app foreground, nudge the visible session back to life if it
    /// dropped while we were suspended. tmux re-attach makes this seamless.
    func reconnectActiveOnForeground() {
        activeSession?.viewModel.reconnectIfNeeded()
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
