import Foundation
import SwiftData

/// Centralized SwiftData container.
///
/// We attempt to open the on-disk store first. If that fails (a stale schema
/// from an earlier build, a corrupted store, missing entitlement, etc.) we
/// fall back to an in-memory container so the app still launches and the
/// user can see a clear error in Settings instead of a crash on boot.
///
/// Brick 10 (Widgets) will switch to an App Group container URL once the
/// entitlement is reliably provisioned across all build configurations.
enum ShioModelContainer {
    static let appGroup = "group.sh.shio.app"

    /// Set to a non-nil value if the on-disk container failed to load and we
    /// fell back to in-memory storage. Settings surfaces this.
    nonisolated(unsafe) static var loadFailureReason: String?

    static let shared: ModelContainer = {
        // 1. Try the default on-disk container.
        if let container = try? ModelContainer(for: Host.self) {
            return container
        }

        // 2. Fall back to in-memory. The user's data won't persist, but
        //    they can still use the app, and Settings shows the error.
        let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: Host.self, configurations: inMemoryConfig) {
            loadFailureReason = "Couldn't open the on-disk store. Your hosts won't be saved between launches. Delete and reinstall Shio to reset."
            return container
        }

        // 3. If even in-memory fails, the schema itself is broken — crash
        //    loudly so we catch it in development.
        fatalError("Failed to create any ModelContainer — schema is invalid")
    }()
}
