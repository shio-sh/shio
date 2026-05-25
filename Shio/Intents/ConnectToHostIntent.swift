import AppIntents
import Foundation

/// "Connect to <host>" — Siri / Shortcuts entry point that opens Shio and
/// connects to the selected host.
struct ConnectToHostIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect to Mac"
    static let description = IntentDescription("Open Shio and connect to a saved Mac.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Mac")
    var host: HostEntity

    func perform() async throws -> some IntentResult {
        // Brick 11 second pass: post a notification the app picks up to
        // route into the right TerminalScene. For now we just bring Shio to
        // the front; the user lands on the host list with the selection
        // ready.
        await NotificationCenter.default.post(
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
    static let title: LocalizedStringResource = "Run Command on Mac"
    static let description = IntentDescription("Run a command on a saved Mac and return its output.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Mac")
    var host: HostEntity

    @Parameter(title: "Command")
    var command: String

    @Parameter(title: "Return output", default: true)
    var returnsOutput: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Brick 11 second pass implements headless SSH execution. For now
        // we return a placeholder so Shortcuts surfaces the action.
        return .result(value: "\(command) — pending implementation")
    }
}

extension Notification.Name {
    static let shioConnectToHost = Notification.Name("sh.shio.app.connectToHost")
}
