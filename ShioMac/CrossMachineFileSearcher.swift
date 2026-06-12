import Foundation

/// Searches files on the user's remote machines in parallel, each via one
/// SSH `find` (using SSHClient.exec). This Mac is handled separately by
/// FileSpotlightSearcher. Remote search runs on submit (⏎), not per keystroke
/// — each query opens an SSH connection per machine.
@MainActor
@Observable
final class CrossMachineFileSearcher {
    enum MachineState {
        case searching
        case results([FileHit])
        case failed(String)
    }
    struct MachineGroup: Identifiable {
        let id = UUID()
        let name: String
        var state: MachineState
    }

    private(set) var groups: [MachineGroup] = []
    private var tasks: [Task<Void, Never>] = []

    /// Fan out a `find` to each machine. `targets` are pre-resolved on the main
    /// actor (name + SSH config) so we never touch the SwiftData model off-main.
    func search(_ query: String, targets: [(name: String, config: SSHClient.Configuration)]) {
        cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, !targets.isEmpty else { groups = []; return }

        groups = targets.map { MachineGroup(name: $0.name, state: .searching) }
        for (index, target) in targets.enumerated() {
            let task = Task { [weak self] in
                let outcome = await Self.find(q, config: target.config)
                guard !Task.isCancelled else { return }
                self?.apply(outcome, at: index)
            }
            tasks.append(task)
        }
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks = []
        groups = []
    }

    private func apply(_ outcome: Result<[FileHit], any Error>, at index: Int) {
        guard groups.indices.contains(index) else { return }
        switch outcome {
        case .success(let hits): groups[index].state = .results(hits)
        case .failure(let error): groups[index].state = .failed(error.localizedDescription)
        }
    }

    /// One SSH connect → `find` in $HOME (skip hidden, cap results) → disconnect.
    private static func find(_ query: String, config: SSHClient.Configuration) async -> Result<[FileHit], any Error> {
        // Single-quote the needle for the shell; escape embedded quotes.
        let safe = query.replacingOccurrences(of: "'", with: "'\\''")
        let command = "find \"$HOME\" -iname '*\(safe)*' -not -path '*/.*' 2>/dev/null | head -40"
        let client = SSHClient(configuration: config)
        do {
            try await client.connect()
            let output = try await client.exec(posixScript: command)
            await client.disconnect()
            let hits = output
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
                .map { FileHit(path: $0, name: ($0 as NSString).lastPathComponent, isDirectory: false) }
            return .success(hits)
        } catch {
            await client.disconnect()
            return .failure(error)
        }
    }
}
