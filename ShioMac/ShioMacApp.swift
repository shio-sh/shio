import SwiftUI

/// Shio for Mac — a native AppKit/SwiftUI app hosting libghostty (NOT Mac
/// Catalyst). Shares the platform-agnostic core (SSH, profiles, keys, agents,
/// design tokens) with the iOS app via target membership in project.yml.
///
/// Current state: a working native local terminal, plus a minimal SSH session
/// path that attaches the same tmux session the phone uses (continuity). The
/// full Projects/Hosts/Agents/Files org + iCloud sync + the proper chrome land
/// in the next milestones.
@main
struct ShioMacApp: App {
    @State private var model = MacTerminalModel()

    var body: some Scene {
        WindowGroup {
            MacShell(model: model)
                .modelContainer(ShioModelContainer.shared)
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            // Copy/Paste come from SwiftUI's default Edit menu — those route
            // copy:/paste: to the focused GhosttyMacSurface via the responder
            // chain, so no custom Edit items are needed.
            CommandMenu("Session") {
                Button("Add Host…") { model.showingAddHost = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                if model.active != nil {
                    Button("Close Session") { model.closeActive() }
                        .keyboardShortcut("w", modifiers: [.command, .shift])
                }
            }
            CommandMenu("Terminal") {
                Button("Clear") { Self.send(#selector(GhosttyMacSurface.terminalClearScreen(_:))) }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Bigger Text") { Self.send(#selector(GhosttyMacSurface.terminalIncreaseFontSize(_:))) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Smaller Text") { Self.send(#selector(GhosttyMacSurface.terminalDecreaseFontSize(_:))) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { Self.send(#selector(GhosttyMacSurface.terminalResetFontSize(_:))) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("Scroll Up") { Self.send(#selector(GhosttyMacSurface.terminalScrollPageUp(_:))) }
                    .keyboardShortcut(.upArrow, modifiers: [.command])
                Button("Scroll Down") { Self.send(#selector(GhosttyMacSurface.terminalScrollPageDown(_:))) }
                    .keyboardShortcut(.downArrow, modifiers: [.command])
                Button("Scroll to Top") { Self.send(#selector(GhosttyMacSurface.terminalScrollToTop(_:))) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("Scroll to Bottom") { Self.send(#selector(GhosttyMacSurface.terminalScrollToBottom(_:))) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            }
        }
    }

    /// Dispatch a terminal action to whichever GhosttyMacSurface is the first
    /// responder (the focused terminal — plain, session, or future split).
    private static func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}

/// App-level state shared between the window and the menu commands.
@Observable
@MainActor
final class MacTerminalModel {
    /// The session occupying the detail pane: a live SSH session or a local
    /// Project terminal. (Tabs/splits hold several of these later.)
    enum Active: Identifiable {
        case ssh(MacSSHSession)
        case project(MacLocalProjectSession)

        var id: UUID {
            switch self {
            case .ssh(let s): return s.id
            case .project(let p): return p.id
            }
        }
        var surface: GhosttyMacSurface {
            switch self {
            case .ssh(let s): return s.surface
            case .project(let p): return p.surface
            }
        }
    }

    var active: Active?
    var showingAddHost = false

    /// Open a live SSH session to a saved host (key auth), or with a one-shot
    /// password for the first connect before the host has authorized the key.
    func connect(to host: Host, password: String? = nil) {
        let session = MacSSHSession(host: host.hostname, port: host.port,
                                    username: host.username, password: password)
        active = .ssh(session)
        Task { await session.connect() }
    }

    func closeActive() {
        let current = active
        active = nil
        Task {
            switch current {
            case .ssh(let s): await s.stop()
            case .project(let p): await p.stop()
            case .none: break
            }
        }
    }
}

