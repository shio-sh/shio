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
    // Stored so a tab can be persisted + reopened on relaunch (restoration).
    let port: Int
    let username: String
    let resumeCommand: String
    let surface: GhosttyMacSurface

    enum State: Equatable { case connecting, connected, failed(String), closed }
    private(set) var state: State = .connecting

    private let client: SSHClient

    init(host: String, port: Int, username: String, password: String?, resumeCommand: String? = nil) {
        self.hostName = host
        self.port = port
        self.username = username
        self.resumeCommand = resumeCommand ?? TmuxResume.resumeCommand(for: host, index: 0)
        // On Mac, default to the user's existing ~/.ssh keys (then the Shio key)
        // so Shio connects with the keys their servers already trust — like
        // Terminal. A one-shot password (first connect / no key yet) still wins.
        let auth: SSHClient.Authentication =
            (password?.isEmpty == false) ? .password(password!) : .systemKeys
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
        // to main to be consistent with AppKit. `DispatchQueue.main.async` is
        // strictly FIFO so chunks render in order; the rolling tail also
        // classifies agent activity (running / waiting / finished).
        client.onOutput = { [weak self] data in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.surface.writeBytes(data)
                    self?.observeForAgent(data)
                }
            }
        }
        client.onDisconnect = { [weak self] _ in
            Task { @MainActor in
                self?.state = .closed
                if let self { AgentStateStore.shared.clear(self.id) }
            }
        }
    }

    /// Rolling ANSI-stripped tail → AgentDetector → shared store (keyed by id).
    private var tail = ""
    private func observeForAgent(_ data: Data) {
        tail += String(decoding: data, as: UTF8.self)
        if tail.count > 8000 { tail = String(tail.suffix(8000)) }
        let clean = AgentDetector.strip(tail)
        AgentStateStore.shared.update(sessionID: id, AgentDetector.classify(cleanTail: clean))
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
            // Render the failure on the terminal — a silent blank cursor is the
            // worst outcome. ConnectErrorTranslator turns NIO/auth/DNS errors
            // into something a human can act on.
            let msg = ConnectErrorTranslator.translate(error, host: hostName, port: port)
            state = .failed(msg)
            let line = "\r\n\u{1b}[31m⚠  \(msg)\u{1b}[0m\r\n"
            surface.writeBytes(Data(line.utf8))
        }
    }

    func stop() async {
        AgentStateStore.shared.clear(id)
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
