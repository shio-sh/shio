import SwiftUI
import SwiftData

@main
struct ShioApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(ShioAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(nil)  // follow system
                .tint(ShioTheme.textPrimary)
                .task {
                    Haptics.prepare()
                    // Project-first migration: backfill a ProjectCheckout for each
                    // legacy single-host project. Idempotent + safe every launch.
                    ProjectMigration.run(in: ShioModelContainer.shared.mainContext)
                    // The PERMISSION prompt stays contextual (hostile at first
                    // run), but registering for remote notifications and the
                    // CloudKit away-push subscription are both SILENT — and must
                    // happen on every launch or the push has nowhere to land.
                    // (Previously gated on hasKey(), which silently broke away-
                    // push for anyone who hadn't generated a key yet — e.g. when
                    // testing the notification before connecting.)
                    await PushService.shared.registerIfAuthorized()
                    await CloudKitSignalService.shared.ensureSubscription()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onContinueUserActivity(SessionHandoff.activityType) { activity in
                    // Receiving end of Handoff: the other device handed
                    // us an active session — connect to the same host.
                    guard let (hostID, _) = SessionHandoff.decode(activity) else { return }
                    NotificationCenter.default.post(
                        name: .shioConnectToHost,
                        object: nil,
                        userInfo: ["hostId": hostID]
                    )
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Reconcile Live Activity state whenever the app
                    // comes back to active. If a session silently died
                    // while we were suspended (network drop while
                    // backgrounded, etc.) the activity was sitting on
                    // the lock screen lying about being connected; this
                    // pushes the real state and ends activities for
                    // sessions that aren't recoverable.
                    if newPhase == .active {
                        // Nudge the visible session back to life — iOS killed
                        // our sockets while suspended — then reconcile the
                        // Live Activity state.
                        SessionStore.shared.reconnectActiveOnForeground()
                        Task { await SessionStore.shared.reconcileLiveActivities() }
                    }
                }
        }
        .modelContainer(ShioModelContainer.shared)
    }

    /// Routes incoming URLs: `shio://connect?host=<id>` (widget taps) and
    /// `shio://pair?d=<base64url>` (the Mac's QR scanned with the Camera app,
    /// or tapped as a link). Connect delegates to the same notification path
    /// the App Intent uses, so behavior stays unified.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "shio" else { return }
        switch url.host {
        case "connect":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let hostID = components.queryItems?.first(where: { $0.name == "host" })?.value
            else { return }
            NotificationCenter.default.post(
                name: .shioConnectToHost,
                object: nil,
                userInfo: ["hostId": hostID]
            )
        case "pair":
            ConnectRouter.shared.pendingPairing = .init(scanned: url.absoluteString)
        default:
            break
        }
    }
}
