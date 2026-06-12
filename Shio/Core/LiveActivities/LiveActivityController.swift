@preconcurrency import ActivityKit
import Foundation

/// Drives the lifecycle of an active session's Live Activity from the
/// main app: starts one when an SSH session connects, updates it on
/// state changes, ends it when the session closes.
///
/// One activity per active session (keyed by SessionStore.Session.id).
/// ActivityKit silently ignores requests if Live Activities aren't
/// enabled for the app or by the user — we don't treat that as an error.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    /// Activity IDs we created, keyed by our session UUID. We look the
    /// actual Activity up via `Activity<…>.activities` each time we
    /// need it; that sidesteps storing a non-Sendable Activity across
    /// the awaits in `update`/`end`.
    nonisolated(unsafe) private var activityIDs: [UUID: String] = [:]

    private init() {}

    /// Default freshness window. If we don't refresh the activity within
    /// this period, iOS marks it as stale (visually dimmed on the lock
    /// screen) — so even if we lose the ability to push updates (suspended
    /// in background, no network), the activity stops claiming to be a
    /// live session.
    private static let defaultStaleSeconds: TimeInterval = 90
    /// Shorter window once we've confirmed a disconnect — keeps the
    /// "Disconnected" state visible for ~30s as a notice, then iOS
    /// grays it out.
    private static let disconnectedStaleSeconds: TimeInterval = 30

    /// Start a Live Activity for a session. Idempotent — re-calls with
    /// the same sessionID are no-ops.
    func start(sessionID: UUID, hostName: String) {
        guard activityIDs[sessionID] == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ShioSessionAttributes(hostName: hostName, startedAt: Date())
        let state = ShioSessionAttributes.ContentState(connectionState: "connected")
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(Self.defaultStaleSeconds)
        )

        do {
            let activity = try Activity<ShioSessionAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            activityIDs[sessionID] = activity.id
            observePushToken(for: activity, sessionID: sessionID)
        } catch {
            print("[shio] LiveActivity start failed: \(error)")
        }
    }

    /// Stream this activity's push-to-update token to the relay so the lock
    /// screen can be refreshed remotely (away-push). Scaffold — `PushService`
    /// no-ops without a configured relay.
    private func observePushToken(for activity: Activity<ShioSessionAttributes>, sessionID: UUID) {
        Task { @MainActor in
            for await tokenData in activity.pushTokenUpdates {
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                await PushService.shared.registerActivityPushToken(hex, sessionID: sessionID)
            }
        }
    }

    /// Look up the live `Activity` for a session ID we created. Activities
    /// can disappear (user ended one from the lock screen, system reaped
    /// it after hours of inactivity, etc.) — returning nil silently
    /// drops the update.
    private func lookupActivity(_ sessionID: UUID) -> Activity<ShioSessionAttributes>? {
        guard let activityID = activityIDs[sessionID] else { return nil }
        return Activity<ShioSessionAttributes>.activities.first { $0.id == activityID }
    }

    /// Update the connection state shown on the Activity (reconnecting,
    /// reconnected, etc.). Refreshes the duration on every call.
    ///
    /// Each update sets a fresh `staleDate` — if the app gets suspended
    /// or the network drops out and we can't push another update before
    /// the window closes, iOS marks the activity as stale so the lock
    /// screen stops claiming "Connected" when we have no idea.
    func update(
        sessionID: UUID,
        connectionState: String,
        agentName: String? = nil,
        agentActivity: String? = nil
    ) async {
        guard let activity = lookupActivity(sessionID) else { return }
        let state = ShioSessionAttributes.ContentState(
            connectionState: connectionState,
            agentName: agentName,
            agentActivity: agentActivity
        )
        let stale: TimeInterval = connectionState == "disconnected"
            ? Self.disconnectedStaleSeconds
            : Self.defaultStaleSeconds
        await activity.update(
            ActivityContent(
                state: state,
                staleDate: Date().addingTimeInterval(stale)
            )
        )
    }

    /// End activities left over from a previous process. After a force-quit
    /// or crash, `activityIDs` is empty — nothing in this run knows about the
    /// old activities, so a stale "Connected to <host>" would sit on the lock
    /// screen indefinitely. Called from the launch/foreground reconcile.
    func endOrphans() async {
        let owned = Set(activityIDs.values)
        for activity in Activity<ShioSessionAttributes>.activities
        where !owned.contains(activity.id) {
            let state = ShioSessionAttributes.ContentState(connectionState: "ended")
            await activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: .immediate)
        }
    }

    /// End the Activity, optionally with a final state shown briefly
    /// (e.g., "disconnected") before it fades.
    func end(sessionID: UUID, finalState: String = "ended") async {
        guard let activity = lookupActivity(sessionID) else {
            activityIDs.removeValue(forKey: sessionID)
            return
        }
        let state = ShioSessionAttributes.ContentState(connectionState: finalState)
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: .after(.now + 4)
        )
        activityIDs.removeValue(forKey: sessionID)
    }
}
