import SwiftUI
import SwiftData
import Combine

/// Root scene router.
///
/// - First launch (no hosts): show OnboardingView full-screen.
/// - Otherwise: show the two-tab interface (Hosts + Settings).
///
/// Brick 8 will swap the iPad layer for a bespoke NavigationSplitView.
struct RootView: View {

    @Query private var hosts: [Host]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize
    @Bindable private var router = ConnectRouter.shared

    var body: some View {
        contentBody
            .onAppear {
                // Install the elevated overlay window so the privacy
                // splash and FaceID lock sit above every SwiftUI
                // surface, including `.fullScreenCover` modals like
                // TerminalScene.
                OverlayWindow.shared.install()
            }
            // The single observer behind every "jump in" entry point: an
            // away-push tap, a widget link, the Siri intent, Handoff, and
            // `shio://connect` URLs all post `.shioConnectToHost`; the router
            // resolves the host (and the tmux session, if the away-signal
            // named one) and opens the session.
            .onReceive(NotificationCenter.default.publisher(for: .shioConnectToHost)) { note in
                router.handle(userInfo: note.userInfo ?? [:], context: modelContext)
            }
            .fullScreenCover(isPresented: $router.showTerminal) { TerminalScene() }
            // A shio://pair link (the Mac's QR scanned with the Camera app,
            // or tapped as a link) opens the pairing flow directly.
            .sheet(item: $router.pendingPairing) { pending in
                PairingView(prescanned: pending.scanned)
            }
    }

    @ViewBuilder
    private var contentBody: some View {
        normalBody
    }

    @ViewBuilder
    private var normalBody: some View {
        if hosts.isEmpty {
            OnboardingView()
                .transition(.opacity)
        } else if hSize == .regular {
            // iPad (and any regular width) = the Mac layout, touch-sized:
            // rail · center canvas · inspector.
            PadRootView()
                .tint(ShioTheme.textPrimary)
                .transition(.opacity)
        } else {
            // The Slack frame, mobile grammar: 塩 Home / ⚑ Activity / ⋯ More
            // on Shio's own mono tab bar.
            MainTabsView()
                .tint(ShioTheme.textPrimary)
                .transition(.opacity)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(ShioModelContainer.shared)
}
