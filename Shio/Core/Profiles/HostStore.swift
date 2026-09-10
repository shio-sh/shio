import Foundation
import SwiftData
#if os(macOS)
import Security
#endif
import os.log

/// Centralized SwiftData container.
///
/// We attempt to open the on-disk store first. If that fails (a stale schema
/// from an earlier build, a corrupted store, missing entitlement, etc.) we
/// fall back to an in-memory container so the app still launches and the
/// user can see a clear error in Settings instead of a crash on boot.
///
/// The store stays at SwiftData's default sandboxed location on iOS (moving
/// it would orphan existing installs); widgets share state via
/// WidgetSharedState in the App Group instead of reading this store.
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
        // Ask whether this process may use CloudKit at all before trying.
        //
        // The `catch` below cannot answer that question. `ModelContainer(...)`
        // with a CloudKit database does NOT throw when the entitlement is
        // missing — it initialises perfectly happily, logs "sync ACTIVE", and
        // then CloudKit terminates the process the moment it is actually used.
        // So the graceful fallback documented here never ran in the one case it
        // was written for; the app just died. Checking first makes the fallback
        // real, and makes the log say the true thing.
        if hasCloudKitEntitlement {
            do {
                let container = try ModelContainer(
                    for: Host.self, Project.self, ProjectCheckout.self, Repo.self,
                    configurations: cloudConfig)
                log.info("ModelContainer: CloudKit sync ACTIVE (iCloud.sh.shio.app)")
                return container
            } catch {
                // Don't hide why sync didn't come up — this is almost always a
                // signing/entitlement/container-id mismatch or no iCloud account.
                log.error("ModelContainer: CloudKit init FAILED, falling back to local. error=\(String(describing: error))")
                // The old text asked the user to check that the build was signed
                // with the iCloud capability, which is a developer instruction
                // nobody using the app can act on. The detail is in the log above.
                loadFailureReason = "iCloud sync is off, so your machines and projects are only saved on this device. Check you're signed into iCloud, then reopen Shio."
            }
        } else {
            log.info("ModelContainer: no CloudKit entitlement — local store only")
        }

        // 2. Local persistent store (no sync). Keeps the app fully usable even
        //    if CloudKit is misconfigured — far better than in-memory.
        #if os(macOS)
        let localConfig = ModelConfiguration(url: macStoreURL(), cloudKitDatabase: .none)
        #else
        let localConfig = ModelConfiguration(cloudKitDatabase: .none)
        #endif
        if let container = try? ModelContainer(for: Host.self, Project.self, ProjectCheckout.self, Repo.self, configurations: localConfig) {
            log.info("ModelContainer: local-only store (no CloudKit)")
            return container
        }

        // 3. Fall back to in-memory. The user's data won't persist, but
        //    they can still use the app, and Settings shows the error.
        let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: Host.self, Project.self, ProjectCheckout.self, Repo.self, configurations: inMemoryConfig) {
            loadFailureReason = "Couldn't open the on-disk store. Your machines won't be saved between launches. Delete and reinstall Shio to reset."
            return container
        }

        // 3. If even in-memory fails, the schema itself is broken — crash
        //    loudly so we catch it in development.
        fatalError("Failed to create any ModelContainer — schema is invalid")
    }()

    /// Does this process actually carry the CloudKit entitlement?
    ///
    /// Signed release builds always do. Builds that do not are the interesting
    /// case: an ad-hoc signed CI build, or a Developer ID build whose App ID
    /// lost the capability. Those used to reach CloudKit and be killed by it.
    ///
    /// macOS only, because `SecTask` is. There is no public way for an iOS
    /// process to read its own entitlements, and it does not need one: an iOS
    /// build cannot be installed on a device at all unless its entitlements
    /// match a provisioning profile, so the question the Mac has to ask cannot
    /// arise there.
    static var hasCloudKitEntitlement: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-services" as CFString, nil)
        else { return false }
        guard let services = value as? [String] else { return false }
        return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
        #else
        return true
        #endif
    }

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
