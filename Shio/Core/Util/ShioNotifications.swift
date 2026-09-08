import Foundation

/// Shared in-process notification names. Lives in Core so it's available to
/// both targets.
extension Notification.Name {
    /// Posted when something (a deep link, an App Intent, Handoff) asks the
    /// app to connect to a specific host. `userInfo["hostId"]` carries the id.
    static let shioConnectToHost = Notification.Name("sh.shio.app.connectToHost")

    /// Posted by Help ▸ Show Welcome to re-enter the Mac's guided first run.
    /// A notification rather than a flag on the window's model: `@State` in an
    /// `App` and the `.commands` builder do not reliably share one instance, so
    /// the menu was mutating a different object than the window observed.
    static let shioShowWelcome = Notification.Name("sh.shio.app.showWelcome")
}
