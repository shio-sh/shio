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

    init(host: String, port: Int, username: String, password: String?) {
        self.hostName = host
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
            // Attach the same tmux session name the phone computes for this
            // host — this is what makes the session follow you across devices.
            client.write(TmuxResume.resumeCommand(for: hostName, index: 0))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        await client.disconnect()
        state = .closed
    }
}

/// Hosts an already-created `GhosttyMacSurface` in SwiftUI and focuses it.
struct GhosttySurfaceHost: NSViewRepresentable {
    let surface: GhosttyMacSurface
    func makeNSView(context: Context) -> GhosttyMacSurface {
        DispatchQueue.main.async { surface.window?.makeFirstResponder(surface) }
        return surface
    }
    func updateNSView(_ nsView: GhosttyMacSurface, context: Context) {}
}
