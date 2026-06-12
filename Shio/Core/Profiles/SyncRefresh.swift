import Foundation
import SwiftData

/// Manual "refresh" for the iCloud-synced lists — backs pull-to-refresh on iOS
/// and ⌘R on Mac.
///
/// SwiftData's `@Query` already updates live as CloudKit imports arrive, and
/// there is no public "pull remote changes now" hook on the CloudKit-mirrored
/// store. So a refresh does the one genuinely useful thing it can: flush local
/// pending writes (`save`) so they export to CloudKit promptly, then hold the
/// spinner briefly so the gesture reads as deliberate. Incoming changes from
/// other devices still land on their own via CloudKit's push/poll.
enum SyncRefresh {
    @MainActor
    static func run(_ context: ModelContext) async {
        do {
            try context.save()
        } catch {
            // The flush IS this gesture's one job — at least say so in the
            // log instead of spinning and pretending it worked.
            print("[shio] sync refresh: save failed: \(error.localizedDescription)")
        }
        try? await Task.sleep(for: .milliseconds(700))
    }
}
