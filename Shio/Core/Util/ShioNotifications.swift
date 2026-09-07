import Foundation

/// Shared in-process notification names. Lives in Core so it's available to
/// both targets.
extension Notification.Name {
    /// Posted when something (a deep link, an App Intent, Handoff) asks the
    /// app to connect to a specific host. `userInfo["hostId"]` carries the id.
    static let shioConnectToHost = Notification.Name("sh.shio.app.connectToHost")
}
