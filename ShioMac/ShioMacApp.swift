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
    /// libghostty's default terminal background (matches LibGhosttyBridge),
    /// used to fill the title strip so it reads as one surface.
    private let terminalBG = Color(red: 0x28/255, green: 0x2C/255, blue: 0x34/255)

    var body: some View {
        // M2: a live local terminal via libghostty (DEFAULT backend). The
        // window is borderless (hidden title bar), so the traffic lights
        // float at top-left; inset the terminal below them so the prompt
        // isn't overlapped. (A proper tinted titlebar lands in M2b.)
        ZStack(alignment: .top) {
            terminalBG.ignoresSafeArea()
            GhosttyMacTerminal()
                .padding(.top, 28)
        }
        .frame(minWidth: 480, minHeight: 320)
        .ignoresSafeArea()
    }
}
