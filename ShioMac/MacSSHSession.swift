import SwiftUI

/// A live SSH terminal session on the Mac: bridges the proven SSHClient to a
/// `.external` ghostty surface, and attaches the same `tmux shio-<host>`
/// session iOS uses — so a session is continuous across devices.
///
/// Minimal for now (no reconnect state machine / agent detection yet — those
/// are brought over from the iOS SessionViewModel in a later slice). Enough to
/// prove SSH parity end to end on the Mac.
@MainActor
@Observable
final class MacSSHSession: Identifiable {
    let id = UUID()
    let hostName: String
    let surface: GhosttyMacSurface

    enum State: Equatable { case connecting, connected, failed(String), closed }
    private(set) var state: State = .connecting

    private let client: SSHClient
    /// What to send once the shell is open. Defaults to attaching the host's
    /// `shio-<host>` tmux; a Project supplies its own `shio-<project>` resume
    /// (with start dir / clone) so a remote project is continuous too.
    private let resumeCommand: String

    init(host: String, port: Int, username: String, password: String?, resumeCommand: String? = nil) {
        self.hostName = host
        self.resumeCommand = resumeCommand ?? TmuxResume.resumeCommand(for: host, index: 0)
        let auth: SSHClient.Authentication =
            (password?.isEmpty == false) ? .password(password!) : .shioKey
        let config = SSHClient.Configuration(
            host: host, port: port, username: username, authentication: auth
        )
        self.client = SSHClient(configuration: config)
        self.surface = GhosttyMacSurface(backend: .external)
        wire()
    }

    private func wire() {
        // Terminal → SSH (keystrokes, resize).
        surface.onOutput = { [weak self] data in self?.client.write(data) }
        surface.onResize = { [weak self] cols, rows in
            self?.client.resize(cols: Int(cols), rows: Int(rows))
        }
        // SSH → terminal. ghostty_surface_write_bytes is thread-safe, but hop
        // to main to be consistent with AppKit.
        client.onOutput = { [weak self] data in
            Task { @MainActor in self?.surface.writeBytes(data) }
        }
        client.onDisconnect = { [weak self] _ in
            Task { @MainActor in self?.state = .closed }
        }
    }

    func connect() async {
        state = .connecting
        do {
            try await client.connect()
            try await client.requestShell()
            state = .connected
            // Attach the same tmux session name the phone computes — this is
            // what makes the session follow you across devices.
            client.write(resumeCommand)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        await client.disconnect()
        state = .closed
    }
}

/// Hosts an already-created `GhosttyMacSurface` in SwiftUI. Focus is NOT taken
/// here — the owning `PaneHost` drives first-responder from the tab's
/// `focusedPaneID`, so a split never has two surfaces fighting for the keyboard.
struct GhosttySurfaceHost: NSViewRepresentable {
    let surface: GhosttyMacSurface
    func makeNSView(context: Context) -> GhosttyMacSurface { surface }
    func updateNSView(_ nsView: GhosttyMacSurface, context: Context) {}
}
