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
        try? context.save()
        try? await Task.sleep(for: .milliseconds(700))
    }
}
