import SwiftUI

/// The iPhone dock — three nouns: Home (the command center: every project),
/// Machines, Files. Settings lives behind the gear on Home. Native Liquid
/// Glass dock.
struct MainTabsView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeTabView()
            }
            // Machines + Files own their title/toolbar/links, so each tab
            // carries its own NavigationStack.
            Tab("Machines", systemImage: "desktopcomputer") {
                NavigationStack { HostListView() }
            }
            Tab("Files", systemImage: "folder") {
                NavigationStack { FilesView() }
            }
        }
        .tint(ShioTheme.textPrimary)
    }
}
