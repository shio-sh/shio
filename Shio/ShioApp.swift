import SwiftUI
import SwiftData

@main
struct ShioApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(nil)  // follow system
                .tint(ShioColor.Text.primary)
                .task {
                    Haptics.prepare()
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
