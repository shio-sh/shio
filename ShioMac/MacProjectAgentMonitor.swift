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
            // Timer callbacks are nonisolated; hop to the main actor explicitly.
            Task { @MainActor in self?.poll() }
        }
    }

    /// Current agent state for a project by name (maps to its tmux session).
    func snapshot(forProjectNamed name: String) -> AgentSnapshot? {
        byTmux["shio-\(TmuxResume.scrubName(name))"]
    }

    /// tmux sessions we've already pushed an away-signal for while they're
    /// blocked — so the phone buzzes once per "needs you", not every poll.
    private var signaledWaiting: Set<String> = []

    private func poll() {
        guard let tmux else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await MacProjectAgentMonitor.scan(tmux: tmux)
            self.fireAwaySignals(for: result)
            self.byTmux = result
        }
    }

    /// On a session newly transitioning to `.waiting`, push the phone via the
    /// sovereign CloudKit away-path. Re-armed once it stops waiting.
    private func fireAwaySignals(for snapshots: [String: AgentSnapshot]) {
        for (name, snap) in snapshots where snap.activity == .waiting {
            guard !signaledWaiting.contains(name) else { continue }
            signaledWaiting.insert(name)
            let project = name.hasPrefix("shio-") ? String(name.dropFirst(5)) : name
            let title = "\(snap.agentName ?? "An agent") needs you"
            let body = snap.detail ?? "\(project) is waiting on you."
            Task {
                await CloudKitSignalService.shared.sendAgentSignal(
                    hostId: "", sessionId: name, title: title, body: body)
            }
        }
        // Re-arm sessions that are no longer waiting (or vanished).
        signaledWaiting = signaledWaiting.filter { snapshots[$0]?.activity == .waiting }
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
