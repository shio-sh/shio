import Foundation
import SwiftUI

/// Detects coding agents (Claude Code, Codex, …) running in **local** project
/// terminals — the case Shio otherwise can't see, because ghostty owns the
/// local PTY and we never proxy its bytes.
///
/// Trick: local project sessions run inside `tmux shio-<project>`, so we don't
/// need the live stream — we just `tmux capture-pane` each session on a timer
/// and run it through the shared `AgentDetector`. Cheap, agent-agnostic, and
/// it works even when the terminal isn't on screen. Keyed by tmux session name
/// so a project row can ask "does my agent need me?".
@Observable
@MainActor
final class MacProjectAgentMonitor {
    static let shared = MacProjectAgentMonitor()

    /// Agent snapshot per local tmux session (e.g. "shio-Infer").
    private(set) var byTmux: [String: AgentSnapshot] = [:]

    private var timer: Timer?
    private let tmux: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    private init() {}

    /// Begin polling (idempotent). No-op if tmux isn't installed.
    func start() {
        guard timer == nil, tmux != nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Current agent state for a project by name (maps to its tmux session).
    func snapshot(forProjectNamed name: String) -> AgentSnapshot? {
        byTmux["shio-\(TmuxResume.scrubName(name))"]
    }

    private func poll() {
        guard let tmux else { return }
        Task { @MainActor [weak self] in
            let result = await MacProjectAgentMonitor.scan(tmux: tmux)
            self?.byTmux = result
        }
    }

    /// Off-main: list shio-* sessions, capture each pane, classify.
    nonisolated private static func scan(tmux: String) async -> [String: AgentSnapshot] {
        await Task.detached(priority: .utility) {
            let names = run(tmux, ["list-sessions", "-F", "#{session_name}"])
                .split(separator: "\n").map(String.init).filter { $0.hasPrefix("shio-") }
            var result: [String: AgentSnapshot] = [:]
            for name in names {
                let pane = run(tmux, ["capture-pane", "-p", "-t", name])
                guard !pane.isEmpty else { continue }
                let snap = AgentDetector.classify(cleanTail: AgentDetector.strip(pane))
                if snap.activity != .none { result[name] = snap }
            }
            return result
        }.value
    }

    nonisolated private static func run(_ bin: String, _ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch { return "" }
    }
}
