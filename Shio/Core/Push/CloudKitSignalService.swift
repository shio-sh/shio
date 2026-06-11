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
    /// The reverse channel (#33): the phone writes an `Action` when you
    /// approve/deny from the lock screen; the Mac polls + injects the keystroke.
    static let actionRecordType = "Action"
    private let subscriptionID = "shio-signal-subscription"
    // Bumped to .v2 so existing installs re-register the subscription with the
    // approve/deny notification category (#33).
    private let didSubscribeKey = "shio.cloudkit.subscribed.v2"
    /// Notification category that carries the lock-screen Approve / Deny actions.
    static let needsYouCategory = "AGENT_NEEDS_YOU"

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
        // Drives the lock-screen Approve / Deny buttons (#33).
        info.category = Self.needsYouCategory
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

    /// Fire the away-push for a real "an agent needs you" event — a Shio
    /// companion (the Mac watcher) calls this when a local agent blocks on
    /// input. Best-effort and guarded on iCloud availability, so it's a safe
    /// no-op when offline / not signed in.
    func sendAgentSignal(hostId: String, sessionId: String, title: String, body: String) async {
        guard await iCloudAvailable() else { return }
        let record = CKRecord(recordType: Self.recordType)
        record["hostId"] = hostId
        record["sessionId"] = sessionId
        record["title"] = title
        record["body"] = body
        _ = try? await database.save(record)
    }

    // MARK: Approve-from-anywhere (#33)

    /// The phone writes an `Action` — "answer this blocked agent with <key>".
    /// Travels through the user's own iCloud; the Mac watcher injects it. Only a
    /// tmux session id and a keystroke ("y"/"n") are on the wire. Best-effort.
    func sendAction(sessionId: String, key: String) async {
        guard await iCloudAvailable() else { return }
        let record = CKRecord(recordType: Self.actionRecordType)
        record["sessionId"] = sessionId
        record["key"] = key
        _ = try? await database.save(record)
    }

    /// Mac side: fetch any pending `Action` records, return them, and delete them
    /// so each approval is consumed exactly once. Best-effort (empty on any
    /// failure / no iCloud / schema not deployed).
    func fetchAndClearActions() async -> [(sessionId: String, key: String)] {
        guard await iCloudAvailable() else { return [] }
        let query = CKQuery(recordType: Self.actionRecordType, predicate: NSPredicate(value: true))
        do {
            let (matches, _) = try await database.records(matching: query)
            var actions: [(sessionId: String, key: String)] = []
            var ids: [CKRecord.ID] = []
            for (id, result) in matches {
                if case .success(let rec) = result,
                   let s = rec["sessionId"] as? String, let k = rec["key"] as? String {
                    actions.append((s, k)); ids.append(id)
                }
            }
            if !ids.isEmpty { _ = try? await database.modifyRecords(saving: [], deleting: ids) }
            return actions
        } catch {
            return []
        }
    }

    /// Write a test Signal record. The subscription fires and Apple pushes a
    /// Shio-branded alert back to this (and any same-account) device — the way
    /// to verify delivery + branding on a real device before the Mac companion
    /// exists. Throws so the caller can surface setup problems.
    func sendTestSignal(hostId: String? = nil) async throws {
        let record = CKRecord(recordType: Self.recordType)
        record["hostId"] = hostId ?? ""
        record["sessionId"] = ""
        record["title"] = "Test from Shio"
        record["body"] = "If you see this, CloudKit away-push works."
        _ = try await database.save(record)
    }
}
