import AppIntents
import Foundation
import SwiftData

/// "Connect to <host>" — Siri / Shortcuts entry point that opens Shio and
/// connects to the selected host.
struct ConnectToHostIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect to machine"
    static let description = IntentDescription("Open Shio and connect to a saved machine.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Machine")
    var host: HostEntity

    func perform() async throws -> some IntentResult {
        // Brick 11 second pass: post a notification the app picks up to
        // route into the right TerminalScene. For now we just bring Shio to
        // the front; the user lands on the host list with the selection ready.
        NotificationCenter.default.post(
            name: .shioConnectToHost,
            object: nil,
            userInfo: ["hostId": host.id]
        )
        return .result()
    }
}

/// "Run command on <host>" — Siri / Shortcuts entry point that runs a single
/// command on the host and (optionally) returns the output.
struct RunCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run command on machine"
    static let description = IntentDescription("Run a command on a saved machine and return its output.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Machine")
    var host: HostEntity

    @Parameter(title: "Command")
    var command: String

    @Parameter(title: "Return output", default: true)
    var returnsOutput: Bool

    struct HostNotFound: LocalizedError {
        var errorDescription: String? { "That machine isn't saved in Shio anymore." }
    }
    struct CommandFailed: LocalizedError {
        let output: String
        var errorDescription: String? { output }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let context = ModelContext(ShioModelContainer.shared)
        guard let saved = (try? context.fetch(FetchDescriptor<Host>()))?
            .first(where: { $0.hostname == host.id }) else { throw HostNotFound() }
        let client = SSHClient(configuration: saved.makeClientConfiguration())
        defer { Task { await client.disconnect() } }
        try await client.connect()
        let result = try await client.execWithStatus(posixScript: command, timeout: .seconds(30))
        let transcript = [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if result.timedOut {
            throw CommandFailed(output: "Timed out after 30s.\(transcript.isEmpty ? "" : "\n\(transcript)")")
        }
        if let status = result.exitStatus, status != 0 {
            throw CommandFailed(output: transcript.isEmpty ? "Exited with status \(status)." : transcript)
        }
        return .result(value: returnsOutput ? transcript : "")
    }
}
// `.shioConnectToHost` now lives in Core/Util/ShioNotifications.swift (shared
// with the Mac target so the away-push path compiles there too).
