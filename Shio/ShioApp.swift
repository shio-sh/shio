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
                    // Do NOT ask for notifications at launch — a first-run
                    // permission prompt is hostile, and the SSH key survives
                    // reinstalls so `hasKey()` isn't a reliable "onboarded"
                    // signal. We ask contextually, when the user starts a
                    // session (away-push is *for* sessions). The CloudKit
                    // away-push subscription is silent (no prompt) and only
                    // matters once a key + the iCloud container exist.
                    if KeyManager.hasKey() {
                        await CloudKitSignalService.shared.ensureSubscription()
                    }
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

    /// Routes incoming URLs (currently just `shio://connect?host=<id>`).
    /// The connect handler delegates to the same notification path the
    /// App Intent uses, so behavior stays unified.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "shio",
              url.host == "connect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let hostID = components.queryItems?.first(where: { $0.name == "host" })?.value
        else { return }
        NotificationCenter.default.post(
            name: .shioConnectToHost,
            object: nil,
            userInfo: ["hostId": hostID]
        )
    }
}
