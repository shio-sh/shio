import Foundation
import CloudKit

/// The sovereign away-push path. A Shio companion writes a small "Signal"
/// record into the user's *own* iCloud (private CloudKit database); a
/// subscription registered here turns that write into a **Shio-branded alert**
/// delivered by Apple — no Shio server, no APNs key to distribute, and no
/// terminal content on the wire (only a host/session id travels, for routing).
///
/// Delivery: the subscription uses a visible `alertBody`, so iOS shows the
/// banner even when Shio is closed (no app code runs to display it). This is
/// the *non-throttled* CloudKit push path (silent/content-available pushes are
/// the throttled kind — we don't use those).
///
/// ONE-TIME SETUP (Apple Developer account — required before this works):
///   1. Enable the **CloudKit** capability on the `sh.shio.app` App ID.
///   2. Create the container **iCloud.sh.shio.app**.
///   3. In CloudKit Dashboard, add record type **Signal** with String fields
///      `hostId`, `sessionId`, `title`, `body`, and make the record type
///      queryable (index `recordName`). Deploy the schema to Production.
/// Until that exists, every call here is a safe no-op (guarded on iCloud
/// account availability), so the build and app run fine without it.
@MainActor
final class CloudKitSignalService {
    static let shared = CloudKitSignalService()

    static let containerID = "iCloud.sh.shio.app"
    static let recordType = "Signal"
    private let subscriptionID = "shio-signal-subscription"
    private let didSubscribeKey = "shio.cloudkit.subscribed"

    private var container: CKContainer { CKContainer(identifier: Self.containerID) }
    private var database: CKDatabase { container.privateCloudDatabase }

    private init() {}

    /// True only when the user is signed into iCloud and the container is
    /// reachable. Everything else short-circuits to a no-op.
    private func iCloudAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    /// Register the alerting subscription once. Safe to call on every launch.
    func ensureSubscription() async {
        guard !UserDefaults.standard.bool(forKey: didSubscribeKey) else { return }
        guard await iCloudAvailable() else { return }

        let subscription = CKQuerySubscription(
            recordType: Self.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "A session needs you. Tap to jump back in."
        info.soundName = "default"
        info.shouldSendContentAvailable = false
        // Carry routing fields in the push payload so a tap can deep-link
        // without a follow-up fetch.
        info.desiredKeys = ["hostId", "sessionId", "title", "body"]
        subscription.notificationInfo = info

        do {
            _ = try await database.save(subscription)
            UserDefaults.standard.set(true, forKey: didSubscribeKey)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Subscription already exists — treat as success.
            UserDefaults.standard.set(true, forKey: didSubscribeKey)
        } catch {
            print("[shio] CloudKit subscribe failed: \(error.localizedDescription)")
        }
    }

    /// Parse an incoming CloudKit push and route to the right host. Returns
    /// true if this was a CloudKit notification (so the caller doesn't also
    /// run the relay path on it).
    @discardableResult
    func handleNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return false
        }
        guard let query = notification as? CKQueryNotification else { return false }
        if let hostId = query.recordFields?["hostId"] as? String, !hostId.isEmpty {
            NotificationCenter.default.post(
                name: .shioConnectToHost,
                object: nil,
                userInfo: ["hostId": hostId]
            )
        }
        return true
    }

    // MARK: Verification

    /// Write a test Signal record. The subscription fires and Apple pushes a
    /// Shio-branded alert back to this (and any same-account) device — the way
    /// to verify delivery + branding on a real device before the Mac companion
    /// exists. Throws so the caller can surface setup problems.
    func sendTestSignal(hostId: String? = nil) async throws {
        let record = CKRecord(recordType: Self.recordType)
        record["hostId"] = (hostId ?? "") as CKRecordValue
        record["sessionId"] = "" as CKRecordValue
        record["title"] = "Test from Shio" as CKRecordValue
        record["body"] = "If you see this, CloudKit away-push works." as CKRecordValue
        _ = try await database.save(record)
    }
}
