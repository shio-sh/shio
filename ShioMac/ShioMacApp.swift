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
            CommandMenu("Session") {
                Button("Connect to Host…") { model.showingConnect = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                if model.active != nil {
                    Button("Close Session") { model.closeActive() }
                        .keyboardShortcut("w", modifiers: [.command, .shift])
                }
            }
        }
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
    var showingConnect = false

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

/// Minimal connect form. The full Hosts org / QR pairing replaces this; for
/// now it's enough to open a live SSH session (password, or Shio key if the
/// host has it authorized).
struct ConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConnect: (_ host: String, _ port: Int, _ user: String, _ password: String?) -> Void

    @State private var host = ""
    @State private var user = NSUserName()
    @State private var port = "22"
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to a host")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
            Form {
                TextField("Host", text: $host, prompt: Text("hostname or IP"))
                TextField("User", text: $user)
                TextField("Port", text: $port)
                SecureField("Password", text: $password, prompt: Text("leave empty to use your Shio key"))
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Connect") {
                    onConnect(host.trimmingCharacters(in: .whitespaces),
                              Int(port) ?? 22, user,
                              password.isEmpty ? nil : password)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || user.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
