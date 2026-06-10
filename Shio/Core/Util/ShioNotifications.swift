import Foundation

/// Shared in-process notification names. Lives in Core (both targets) so the
/// away-push path (`CloudKitSignalService`) compiles on macOS too, not just iOS.
extension Notification.Name {
    /// Posted when something (a push tap, an App Intent, a CloudKit signal) asks
    /// the app to connect to a specific host. `userInfo["hostId"]` carries the id.
    static let shioConnectToHost = Notification.Name("sh.shio.app.connectToHost")
}
