import SwiftUI
import SwiftData

/// Root scene router.
///
/// - First launch (no hosts): show OnboardingView full-screen.
/// - Otherwise: show the two-tab interface (Hosts + Settings).
///
/// Brick 8 will swap the iPad layer for a bespoke NavigationSplitView.
struct RootView: View {

    @Query private var hosts: [Host]

    var body: some View {
        contentBody
            .onAppear {
                // Install the elevated overlay window so the privacy
                // splash and FaceID lock sit above every SwiftUI
                // surface, including `.fullScreenCover` modals like
                // TerminalScene.
                OverlayWindow.shared.install()
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
        } else {
            // The four-tab Liquid Glass dock. Projects is home; Settings
            // moves behind the profile button on the Projects tab. Used on
            // both iPhone and iPad (the iPadOS tab bar adapts); the old
            // IPadRootView split is retired for now.
            TabView {
                Tab("Projects", systemImage: "folder.fill") {
                    ProjectsView()
                }
                Tab("Machines", systemImage: "desktopcomputer") {
                    HostListView()
                }
                Tab("Agents", systemImage: "sparkles") {
                    AgentsView()
                }
                Tab("Files", systemImage: "tray.full.fill") {
                    FilesView()
                }
            }
            .tint(ShioColor.Text.primary)
            .transition(.opacity)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(ShioModelContainer.shared)
}
