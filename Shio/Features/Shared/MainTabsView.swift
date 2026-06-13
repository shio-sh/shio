import SwiftUI
import SwiftData

/// The iPhone dock — the old noun dock, restored, with the supervision inbox
/// promoted to a peer: Home (this team's conversations), Agents (the
/// cross-project needs-you feed, badged while something's blocked), Machines,
/// Files. Settings lives behind the gear on Home. Native Liquid Glass dock.
struct MainTabsView: View {
    @Query private var projects: [Project]

    private var needsYou: Int {
        ActivityFeed.items(projects: projects).filter { $0.activity == .waiting }.count
    }

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeTabView()
            }
            Tab("Agents", systemImage: "wand.and.sparkles.inverse") {
                ActivityTabView()
            }
            .badge(needsYou)
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
