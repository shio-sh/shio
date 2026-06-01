import SwiftUI

/// Shio for Mac — a native AppKit/SwiftUI app hosting libghostty (NOT Mac
/// Catalyst). This is the macOS member of the Shio family; it shares the
/// platform-agnostic core (SSH, profiles, keys, agents, design tokens) with
/// the iOS app via target membership in project.yml.
///
/// M1 scaffold: an empty window that builds. The native terminal surface,
/// the Projects/Hosts/Agents/Files organization, iCloud org sync, continuity,
/// QR pairing, and the away-watcher land in subsequent milestones.
@main
struct ShioMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacRootView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)
    }
}

/// Placeholder root. Replaced by the NavigationSplitView shell (Projects /
/// Hosts / Agents / Files) + terminal in a later milestone.
private struct MacRootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("塩")
                .font(.system(size: 72))
            Text("Shio for Mac")
                .font(.system(.title2, design: .monospaced))
            Text("a native terminal, coming together")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
