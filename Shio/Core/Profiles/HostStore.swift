import Foundation
import SwiftData
import os.log

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

        // 1. Try the on-disk container with CloudKit mirroring to the shared
        //    private DB — this is what syncs Host/Project across the user's
        //    devices (Mac ↔ iPhone). The schema is CloudKit-valid (every
        //    attribute optional-or-defaulted, `.nullify` not `.cascade`).
        //    SwiftData still persists locally and works offline / when not
        //    signed into iCloud; it just mirrors when iCloud is available.
        //    (CloudKit is ALSO used as a raw push-signal channel for the
        //    away-watcher via CloudKitSignalService — separate from this.)
        let log = Logger(subsystem: "sh.shio.app", category: "modelcontainer")
        let cloudConfig: ModelConfiguration
        #if os(macOS)
        // EXPLICIT store URL on the Mac. ShioMac is unsandboxed, and
        // SwiftData's default for unsandboxed apps is the SHARED
        // `~/Library/Application Support/default.store` — every other
        // unsandboxed SwiftData app that also skips an explicit URL opens
        // the SAME file, and whichever launches next "migrates" it to its
        // own model, DROPPING the other app's tables. That destroyed this
        // Mac's local data once (CloudKit re-imported it). Never share
        // default.store.
        cloudConfig = ModelConfiguration(url: macStoreURL(), cloudKitDatabase: .private("iCloud.sh.shio.app"))
        #else
        // iOS is sandboxed — the default location is private to the app,
        // and moving it would orphan existing installs' data.
        cloudConfig = ModelConfiguration(cloudKitDatabase: .private("iCloud.sh.shio.app"))
        #endif
        do {
            let container = try ModelContainer(for: Host.self, Project.self, ProjectCheckout.self, Repo.self, Skill.self, configurations: cloudConfig)
            log.info("ModelContainer: CloudKit sync ACTIVE (iCloud.sh.shio.app)")
            return container
        } catch {
            // Don't hide why sync didn't come up — this is almost always a
            // signing/entitlement/container-id mismatch or no iCloud account.
            log.error("ModelContainer: CloudKit init FAILED, falling back to local. error=\(String(describing: error))")
            loadFailureReason = "iCloud sync is off — \(error.localizedDescription). Check that this build is signed with the iCloud capability and you're signed into iCloud. Data is saved locally meanwhile."
        }

        // 2. Local persistent store (no sync). Keeps the app fully usable even
        //    if CloudKit is misconfigured — far better than in-memory.
        #if os(macOS)
        let localConfig = ModelConfiguration(url: macStoreURL(), cloudKitDatabase: .none)
        #else
        let localConfig = ModelConfiguration(cloudKitDatabase: .none)
        #endif
        if let container = try? ModelContainer(for: Host.self, Project.self, ProjectCheckout.self, Repo.self, Skill.self, configurations: localConfig) {
            log.info("ModelContainer: local-only store (no CloudKit)")
            return container
        }

        // 3. Fall back to in-memory. The user's data won't persist, but
        //    they can still use the app, and Settings shows the error.
        let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: Host.self, Project.self, ProjectCheckout.self, Repo.self, Skill.self, configurations: inMemoryConfig) {
            loadFailureReason = "Couldn't open the on-disk store. Your machines won't be saved between launches. Delete and reinstall Shio to reset."
            return container
        }

        // 3. If even in-memory fails, the schema itself is broken — crash
        //    loudly so we catch it in development.
        fatalError("Failed to create any ModelContainer — schema is invalid")
    }()

    #if os(macOS)
    /// Shio's own store location: `~/Library/Application Support/Shio/Shio.store`.
    /// See the cloudConfig comment — the unsandboxed default would be the
    /// machine-wide shared `default.store`.
    private static func macStoreURL() -> URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Shio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Shio.store")
    }
    #endif

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
