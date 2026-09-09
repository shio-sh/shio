import Foundation
import SwiftData
import OSLog

/// Pull-to-refresh, and the Mac's ⌘R.
///
/// Flushes pending writes so they export to CloudKit promptly, then holds the
/// spinner briefly so the gesture reads as deliberate. Incoming changes from
/// other devices still land on their own.
///
/// The failure is **returned**, not stored. An earlier version kept it in a
/// static on this enum and bound SwiftUI alerts to it, which cannot work:
/// nothing observes a plain static, so no body ever re-evaluated and the alert
/// never appeared. It was also process-wide, so a failure raised on one screen
/// could surface on an unrelated one later, or get stuck with no view able to
/// clear it. Returning it makes the failure belong to the refresh that caused
/// it and to the view that asked for it.
enum SyncRefresh {
    private static let log = Logger(subsystem: "sh.shio.app", category: "sync")

    /// Returns a message when the flush failed, nil when it worked.
    @MainActor
    @discardableResult
    static func run(_ context: ModelContext) async -> String? {
        var failure: String?
        do {
            try context.save()
        } catch {
            failure = error.localizedDescription
            // Logged as well as returned. Not every caller has somewhere to
            // put an alert — the Mac's ⌘R is a menu command — and a failure
            // that reaches neither the screen nor the log is invisible.
            log.error("refresh: save failed: \(error.localizedDescription, privacy: .public)")
        }
        try? await Task.sleep(for: .milliseconds(700))
        return failure
    }
}
