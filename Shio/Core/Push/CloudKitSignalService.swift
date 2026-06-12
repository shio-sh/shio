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
    // The latch is scoped to the CloudKit environment: a Debug build talks to
    // Development, TestFlight/Release to Production. One shared boolean would
    // mark "subscribed" during Dev testing and then silently skip creating
    // the Production subscription on the very device used to verify the flow.
    // (.v3 also re-registers existing installs with the per-agent banner.)
    #if DEBUG
    private let didSubscribeKey = "shio.cloudkit.subscribed.v3.dev"
    #else
    private let didSubscribeKey = "shio.cloudkit.subscribed.v3.prod"
    #endif
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
        // Show the Mac's per-agent copy ("Claude Code needs you" / "shio is
        // waiting on you.") instead of a blind static line — the localization
        // key doubles as the format string and CloudKit substitutes the
        // record's fields in. The static alertBody stays as the fallback.
        info.titleLocalizationKey = "%1$@"
        info.titleLocalizationArgs = ["title"]
        info.alertLocalizationKey = "%1$@"
        info.alertLocalizationArgs = ["body"]
        info.alertBody = "An agent needs you. Tap to jump back in."
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

    /// Mac side: fetch pending `Action` records and consume them at-most-once.
    /// Best-effort (empty on any failure / no iCloud / schema not deployed).
    ///
    /// Two safety properties an approve channel needs:
    /// - **Delete before inject.** Only actions whose delete the server
    ///   confirmed are returned — a failed delete would be re-fetched next
    ///   poll, and injecting it now too would answer the prompt twice. A
    ///   re-tap is cheap; a double-"y" into the *next* prompt is not.
    /// - **TTL.** An action older than `maxAge` is a leftover (written while
    ///   the Mac was off or the agent already moved on) — it's consumed but
    ///   never injected into whatever happens to be blocking *now*.
    func fetchAndClearActions(maxAge: TimeInterval = 120) async -> [(sessionId: String, key: String)] {
        guard await iCloudAvailable() else { return [] }
        // Filter on the queryable `sessionId` field rather than a true predicate,
        // which would need the system `recordName` index marked Queryable (the
        // Console won't always let you edit that). Every Action has a non-empty
        // sessionId, so `> ""` matches them all.
        let query = CKQuery(recordType: Self.actionRecordType,
                            predicate: NSPredicate(format: "sessionId > %@", ""))
        do {
            let (matches, _) = try await database.records(matching: query)
            let cutoff = Date().addingTimeInterval(-maxAge)
            var fresh: [CKRecord.ID: (sessionId: String, key: String)] = [:]
            var allIDs: [CKRecord.ID] = []
            for (id, result) in matches {
                guard case .success(let rec) = result,
                      let s = rec["sessionId"] as? String,
                      let k = rec["key"] as? String else { continue }
                allIDs.append(id)
                if (rec.creationDate ?? .distantPast) > cutoff {
                    fresh[id] = (s, k)
                }
            }
            guard !allIDs.isEmpty else { return [] }
            let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: allIDs)
            var consumed: [(sessionId: String, key: String)] = []
            for (id, result) in deleteResults {
                if case .success = result, let action = fresh[id] {
                    consumed.append(action)
                }
            }
            return consumed
        } catch {
            return []
        }
    }

    enum SubscriptionCheck {
        case active            // confirmed on the server
        case created           // was missing; created just now
        case unavailable(String)
    }

    /// Server-side truth about the alerting subscription. The local latch can
    /// lie (reinstall, environment switch, iCloud account change) — this asks
    /// CloudKit directly and repairs if it's missing.
    func verifySubscription() async -> SubscriptionCheck {
        guard await iCloudAvailable() else {
            return .unavailable("Not signed into iCloud (or the container is unreachable).")
        }
        if (try? await database.subscription(for: subscriptionID)) != nil {
            UserDefaults.standard.set(true, forKey: didSubscribeKey)
            return .active
        }
        UserDefaults.standard.set(false, forKey: didSubscribeKey)
        await ensureSubscription()
        if (try? await database.subscription(for: subscriptionID)) != nil {
            return .created
        }
        return .unavailable("The subscription couldn't be created — check the Signal record type exists in this CloudKit environment.")
    }

    /// Best-effort housekeeping: delete Signal records older than a day. The
    /// banner has long been delivered (or never will be) — without this the
    /// user's private database accumulates one record per needs-you forever.
    /// The Mac watcher calls it once per app run.
    func sweepOldSignals(olderThan age: TimeInterval = 24 * 3600) async {
        guard await iCloudAvailable() else { return }
        let query = CKQuery(recordType: Self.recordType,
                            predicate: NSPredicate(format: "sessionId > %@", ""))
        guard let (matches, _) = try? await database.records(matching: query) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        let stale = matches.compactMap { id, result -> CKRecord.ID? in
            guard case .success(let rec) = result,
                  (rec.creationDate ?? .distantFuture) < cutoff else { return nil }
            return id
        }
        if !stale.isEmpty {
            _ = try? await database.modifyRecords(saving: [], deleting: stale)
        }
    }

    /// Write a test Signal record. IMPORTANT delivery semantics: CloudKit
    /// never pushes a subscription notification back to the device that
    /// *wrote* the record — so the device calling this will not banner from
    /// its own test. Every OTHER subscribed device on the account will.
    /// (This is why the Mac's "ping iPhone" is the real end-to-end test.)
    /// Throws so the caller can surface setup problems.
    func sendTestSignal(hostId: String? = nil,
                        sessionId: String = "shio-test",
                        title: String = "Test from Shio",
                        body: String = "If you see this, CloudKit away-push works.") async throws {
        let record = CKRecord(recordType: Self.recordType)
        record["hostId"] = hostId ?? ""
        record["sessionId"] = sessionId
        record["title"] = title
        record["body"] = body
        _ = try await database.save(record)
    }
}
