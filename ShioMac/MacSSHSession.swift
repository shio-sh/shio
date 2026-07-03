import SwiftUI
import AppKit

/// A live SSH terminal session on the Mac: bridges the proven SSHClient to a
/// `.external` ghostty surface, and attaches the same `tmux shio-<host>`
/// session iOS uses — so a session is continuous across devices.
///
/// Reconnect mirrors the iOS `SessionViewModel` machine on the shared
/// `ReconnectPolicy` table: exponential backoff with a fresh client per
/// attempt, permanent failures surfaced instead of retried, and
/// `MacNetworkMonitor` feeding network-return / interface-switch / wake
/// events so a sleeping Mac's dead sockets recover in place (tmux reattach
/// makes it lossless).
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

    enum State: Equatable {
        case connecting, connected, reconnecting(attempt: Int), failed(String), closed
    }
    private(set) var state: State = .connecting

    private let configuration: SSHClient.Configuration
    private var client: SSHClient

    // MARK: Reconnect state (the iOS machine's shape)

    /// True once the user (or the hibernation sweep) explicitly closed the
    /// session — suppresses auto-reconnect so we don't fight a closing tab.
    private var userInitiatedStop = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?

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
        self.configuration = config
        self.client = SSHClient(configuration: config)
        self.surface = GhosttyMacSurface(backend: .external)
        wireSurface()
        wire(client)
        MacNetworkMonitor.shared.register(self)
    }

    /// Surface hooks are set once — they always forward to the *current*
    /// client, so a reconnect's fresh client picks them up for free.
    private func wireSurface() {
        // Terminal → SSH (keystrokes, resize).
        surface.onOutput = { [weak self] data in self?.client.write(data) }
        surface.onResize = { [weak self] cols, rows in
            self?.client.resize(cols: Int(cols), rows: Int(rows))
        }
    }

    /// Client hooks are re-wired onto every fresh client.
    private func wire(_ client: SSHClient) {
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
        client.onDisconnect = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                AgentStateStore.shared.clear(self.id)
                guard !self.userInitiatedStop else {
                    self.state = .closed
                    return
                }
                self.handleUnexpectedDisconnect(reason: error?.localizedDescription)
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
        userInitiatedStop = false
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        await connectOnce(isReconnect: false)
    }

    /// One connect attempt. A fresh client per attempt, with the stale one
    /// retired for real (callbacks detached first so its teardown can't echo
    /// into this attempt, and its parent SSH/TCP connection can't leak).
    private func connectOnce(isReconnect: Bool) async {
        state = isReconnect ? .reconnecting(attempt: reconnectAttempt) : .connecting
        let stale = client
        stale.onOutput = nil
        stale.onDisconnect = nil
        Task { await stale.disconnect() }
        let fresh = SSHClient(configuration: configuration)
        client = fresh
        wire(fresh)

        do {
            // May prompt for (and cache) a key passphrase; false = user cancelled,
            // with a clean failure state already set. Reconnects never prompt —
            // the passphrase is Keychain-cached by then, so a prompt mid-backoff
            // means something the user must look at (treated permanent below).
            guard try await establishConnection(isReconnect: isReconnect) else { return }
            try await fresh.requestShell()
            // The user may have closed the tab while the connect was in
            // flight — don't resurrect the session under them.
            if userInitiatedStop {
                fresh.onOutput = nil
                fresh.onDisconnect = nil
                Task { await fresh.disconnect() }
                state = .closed
                return
            }
            state = .connected
            reconnectAttempt = 0
            // Attach the same tmux session name the phone computes — this is
            // what makes the session follow you across devices (and what makes
            // a reconnect land exactly where the user left off).
            fresh.write(resumeCommand)
        } catch {
            if userInitiatedStop {
                state = .closed
            } else if ReconnectPolicy.isPermanentFailure(error) {
                fail(with: error)
            } else {
                handleUnexpectedDisconnect(reason: ConnectErrorTranslator.translate(
                    error, host: hostName, port: port), fromFailedRetry: true)
            }
        }
    }

    /// Permanent failure: render it on the terminal (a silent blank cursor is
    /// the worst outcome) and — for a refused host-key change — offer the
    /// in-place review instead of a dead end.
    private func fail(with error: any Error) {
        let msg = ConnectErrorTranslator.translate(error, host: hostName, port: port)
        state = .failed(msg)
        surface.writeBytes(Data("\r\n\u{1b}[31m⚠  \(msg)\u{1b}[0m\r\n".utf8))
        if case SSHClient.SSHError.hostKeyChanged = error, reviewHostKeyChange() {
            ShioKnownHosts.forget("\(hostName):\(port)")
            Task { await connect() }
        }
    }

    private func handleUnexpectedDisconnect(reason: String?, fromFailedRetry: Bool = false) {
        // A live shell dropping while a retry is already scheduled must not
        // pile on a duplicate task — but a *failed retry itself* (state is
        // .reconnecting by definition then) has to continue the chain, or
        // the loop dies after one attempt with a permanent spinner.
        if !fromFailedRetry, case .reconnecting = state { return }
        guard reconnectAttempt < ReconnectPolicy.maxAttempts else {
            state = .failed(reason ?? "Connection lost.")
            surface.writeBytes(Data("\r\n\u{1b}[31m⚠  \(reason ?? "Connection lost.")\u{1b}[0m\r\n".utf8))
            return
        }
        state = .reconnecting(attempt: reconnectAttempt)
        kickReconnect(immediate: false)
    }

    private func kickReconnect(immediate: Bool) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                let delayMs = ReconnectPolicy.delayMilliseconds(forAttempt: self.reconnectAttempt)
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
            if Task.isCancelled { return }
            self.reconnectAttempt += 1
            await self.connectOnce(isReconnect: true)
        }
    }

    /// Tear down the current (now-dead) client and reconnect immediately,
    /// surfaced as a reconnect so the pane stays put and tmux reattaches.
    private func forceReconnect() {
        guard !userInitiatedStop else { return }
        reconnectAttempt = 0
        reconnectTask?.cancel()
        state = .reconnecting(attempt: 0)
        kickReconnect(immediate: true)
    }

    // MARK: MacNetworkMonitor hooks

    /// The network just came back: if we're mid-backoff, jump the queue.
    func networkReturned() {
        guard !userInitiatedStop else { return }
        if case .reconnecting = state {
            reconnectTask?.cancel()
            kickReconnect(immediate: true)
        }
    }

    /// The primary interface flipped (Wi-Fi ↔ wired) while we think we're
    /// connected — the old socket is dead even though it hasn't timed out.
    func interfaceSwitched() {
        guard case .connected = state else { return }
        forceReconnect()
    }

    /// Wake-from-sleep / app-activation recovery: sleep kills sockets while
    /// the state still says `.connected` — verify the transport and recover.
    func recoverIfNeeded() {
        guard !userInitiatedStop else { return }
        switch state {
        case .connected where !client.isTransportActive:
            forceReconnect()
        case .reconnecting:
            reconnectTask?.cancel()
            reconnectAttempt = 0
            kickReconnect(immediate: true)
        default:
            break
        }
    }

    /// Connect, transparently unlocking a passphrase-protected `~/.ssh` key when
    /// that's the only identity available: prompt, validate, cache to Keychain,
    /// retry. Returns false if the user dismisses the prompt (state already set
    /// to a clean failure); throws for ordinary connection errors.
    private func establishConnection(isReconnect: Bool) async throws -> Bool {
        do {
            try await client.connect()
            return true
        } catch SSHClient.SSHError.passphraseRequired(let names) {
            // Never modal-prompt from a background retry loop.
            guard !isReconnect else { throw SSHClient.SSHError.passphraseRequired(names) }
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

    func stop() async {
        userInitiatedStop = true
        reconnectTask?.cancel()
        reconnectTask = nil
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
