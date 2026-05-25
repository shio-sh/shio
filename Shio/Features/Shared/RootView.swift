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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if hosts.isEmpty {
            OnboardingView()
                .transition(.opacity)
        } else if horizontalSizeClass == .regular {
            IPadRootView()
                .tint(ShioColor.Text.primary)
                .transition(.opacity)
        } else {
            TabView {
                HostListView()
                    .tabItem {
                        Label("Hosts", systemImage: "desktopcomputer")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "slider.horizontal.3")
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
