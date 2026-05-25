import Foundation
import SwiftData

/// Centralized SwiftData container.
///
/// For Brick 7 we use the default app-local container. Brick 10 (Widgets)
/// will switch to an App Group container URL so the widget can read the
/// same hosts — but that needs the App Group entitlement actually
/// provisioned on the build, which isn't the case for unsigned simulator
/// builds. Doing the App Group dance now would just crash with
/// loadIssueModelContainer.
enum ShioModelContainer {
    static let appGroup = "group.sh.shio.app"

    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: Host.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
