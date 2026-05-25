import Foundation
import SwiftUI
import Observation

/// Owns the live SSH session and its terminal surface. Bridges:
///
///   SSHClient  ─── onOutput ───→ TerminalWebViewController.write
///   TerminalWebViewController.onInput
///   TerminalInputView.onBytes ─── write ───→ SSHClient.write
///   TerminalWebViewController.onResize ─── resize ───→ SSHClient.resize
///
/// Per the plan, this is also where tmux auto-resume logic will hook in
/// (Brick 5) and where session persistence state lives.
@Observable
@MainActor
final class SessionViewModel {

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case reconnecting
        case disconnected(reason: String?)
    }

    let terminal: TerminalWebViewController
    private(set) var state: ConnectionState = .idle
    private(set) var hostName: String

    private var client: SSHClient?
    private var configuration: SSHClient.Configuration
    private let persistenceMode: Host.PersistenceMode
    private var tmuxFallbackTriggered = false

    init(configuration: SSHClient.Configuration, persistenceMode: Host.PersistenceMode = .tmuxAutoResume) {
        self.configuration = configuration
        self.hostName = configuration.host
        self.persistenceMode = persistenceMode
        self.terminal = TerminalWebViewController()
        wire()
    }

    private func wire() {
        terminal.onInput = { [weak self] data in
            self?.client?.write(data)
        }
        terminal.onResize = { [weak self] cols, rows in
            self?.client?.resize(cols: cols, rows: rows)
        }
    }

    // MARK: - Lifecycle

    func start() async {
        state = .connecting
        tmuxFallbackTriggered = false
        let client = SSHClient(configuration: configuration)
        client.onOutput = { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.terminal.write(data)
                // Detect tmux-missing output and fall back to plain shell.
                if self.persistenceMode == .tmuxAutoResume, !self.tmuxFallbackTriggered,
                   let str = String(data: data, encoding: .utf8),
                   TmuxResume.looksLikeTmuxMissing(str) {
                    self.tmuxFallbackTriggered = true
                    // Show a soft hint inline in the terminal.
                    self.terminal.write("\r\n\u{1B}[33m[shio] tmux not found — running plain shell.\u{1B}[0m\r\n")
                }
            }
        }
        client.onDisconnect = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.state = .disconnected(reason: error?.localizedDescription)
            }
        }
        self.client = client

        do {
            try await client.connect()
            try await client.requestShell()
            state = .connected
            if persistenceMode == .tmuxAutoResume {
                client.write(TmuxResume.resumeCommand(for: hostName))
            }
        } catch {
            state = .disconnected(reason: error.localizedDescription)
        }
    }

    func stop() async {
        await client?.disconnect()
        client = nil
        state = .idle
    }
}
