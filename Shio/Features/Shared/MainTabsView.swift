import SwiftUI
import SwiftData

/// The iPhone dock — three nouns: Home (the command center: every project,
/// supervision-first, badged while an agent is blocked), Machines, Files.
/// Settings lives behind the gear on Home. Native Liquid Glass dock.
///
/// Supervision is Home's job, not a separate place — a blocked agent floats
/// its project to the top of Home with the question answerable inline, so a
/// dedicated feed tab would just be the same rows one level flatter.
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
