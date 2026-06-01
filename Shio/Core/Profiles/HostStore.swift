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
        // 0. Pre-create `Library/Application Support` inside the App Group
        //    container if it doesn't exist. iOS doesn't pre-populate the
        //    subdirectory tree of a freshly-provisioned App Group, so the
        //    first time SwiftData touches it the directory is missing and
        //    SwiftData logs an exhaustive `errno 2 / No such file or
        //    directory` diagnostic dump (several hundred lines of noise)
        //    before recovering and creating it itself. We just create it
        //    up-front to keep first-launch logs clean.
        prepareAppGroupApplicationSupport()

        // 1. Try the on-disk container. CloudKit mirroring is explicitly
        //    OFF: Shio uses CloudKit only as a raw push-signal channel
        //    (CloudKitSignalService), never to sync SwiftData. Without this,
        //    the CloudKit *entitlement* flips SwiftData's default
        //    (`cloudKitDatabase: .automatic`) into iCloud-mirroring mode,
        //    which then rejects our schema (CloudKit requires every attribute
        //    optional-or-defaulted and forbids .cascade) — and the container
        //    fails to build at all.
        let onDiskConfig = ModelConfiguration(cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: Host.self, Project.self, configurations: onDiskConfig) {
            return container
        }

        // 2. Fall back to in-memory. The user's data won't persist, but
        //    they can still use the app, and Settings shows the error.
        let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: Host.self, Project.self, configurations: inMemoryConfig) {
            loadFailureReason = "Couldn't open the on-disk store. Your machines won't be saved between launches. Delete and reinstall Shio to reset."
            return container
        }

        // 3. If even in-memory fails, the schema itself is broken — crash
        //    loudly so we catch it in development.
        fatalError("Failed to create any ModelContainer — schema is invalid")
    }()

    /// Ensure the `Library/Application Support` directory exists inside
    /// the App Group container. No-op if the directory is already there
    /// or the App Group isn't reachable.
    private static func prepareAppGroupApplicationSupport() {
        let fm = FileManager.default
        guard let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return
        }
        let appSupport = groupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        if !fm.fileExists(atPath: appSupport.path) {
            try? fm.createDirectory(
                at: appSupport,
                withIntermediateDirectories: true
            )
        }
    }
}
