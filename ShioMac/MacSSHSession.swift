import SwiftUI
import AppKit

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
            // May prompt for (and cache) a key passphrase; false = user cancelled,
            // with a clean failure state already set.
            guard try await establishConnection() else { return }
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
            // A refused host-key change is reviewable: show what changed and
            // offer to trust the new key (drop the pin, TOFU re-pins).
            if case SSHClient.SSHError.hostKeyChanged = error, reviewHostKeyChange() {
                ShioKnownHosts.forget("\(hostName):\(port)")
                await connect()
            }
        }
    }

    /// Modal review of a refused key change (same pattern as the passphrase
    /// prompt). Returns true if the user chose to trust the new key.
    private func reviewHostKeyChange() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(hostName)’s key changed"
        var detail = "If this machine was reinstalled or upgraded, trusting the new key is safe. If you didn’t expect a change, keep refusing — the connection could be intercepted."
        if let m = ShioKnownHosts.mismatch(for: "\(hostName):\(port)") {
            let offered = m.offered.map(ShioKnownHosts.shortFingerprint) ?? "unreadable"
            detail = "Pinned \(ShioKnownHosts.shortFingerprint(m.pinned)) → offered \(offered).\n\n" + detail
        }
        alert.informativeText = detail
        alert.addButton(withTitle: "Trust New Key & Reconnect")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Connect, transparently unlocking a passphrase-protected `~/.ssh` key when
    /// that's the only identity available: prompt, validate, cache to Keychain,
    /// retry. Returns false if the user dismisses the prompt (state already set
    /// to a clean failure); throws for ordinary connection errors.
    private func establishConnection() async throws -> Bool {
        do {
            try await client.connect()
            return true
        } catch SSHClient.SSHError.passphraseRequired(let names) {
            guard let name = names.first else { throw SSHClient.SSHError.passphraseRequired(names) }
            var incorrect = false
            while true {
                guard let passphrase = promptForPassphrase(keyName: name, retry: incorrect) else {
                    let msg = "Unlock cancelled — \(name) is passphrase-protected."
                    state = .failed(msg)
                    surface.writeBytes(Data("\r\n\u{1b}[33m⚠  \(msg)\u{1b}[0m\r\n".utf8))
                    return false
                }
                if SystemSSHKeys.unlock(keyNamed: name, passphrase: passphrase) {
                    // resolveSystemKeys now finds the saved passphrase and loads the key.
                    try await client.connect()
                    return true
                }
                incorrect = true
            }
        }
    }

    /// Modal secure-entry prompt for an SSH key passphrase. nil = the user
    /// cancelled. Runs on the main actor (this type is `@MainActor`).
    private func promptForPassphrase(keyName: String, retry: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = retry ? "Incorrect passphrase — try again" : "Unlock SSH key"
        alert.informativeText = "Enter the passphrase for ~/.ssh/\(keyName). It’s saved to your Keychain so you won’t be asked again."
        alert.addButton(withTitle: "Unlock")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Passphrase"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
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
