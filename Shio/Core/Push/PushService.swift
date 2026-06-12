import Foundation
import Observation
import UIKit
import UserNotifications
import CloudKit

/// The phone side of away-push. Registers for APNs, captures the device token,
/// and routes incoming "a session needs you" triggers to the right host. The
/// payload is deliberately opaque — it carries which session wants you, never
/// terminal content (see `relay/` and `companion/` for the other half).
///
/// RUNTIME/INFRA NOTE: this compiles and runs on-device, but end-to-end away
/// notifications require the relay deployed + the companion away-watcher
/// running (both scaffolded under `relay/` and `companion/`, flagged there).
/// Without a configured relay URL, token registration is stored locally and
/// the network step is skipped.
@Observable
@MainActor
final class PushService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushService()

    private let appGroup = "group.sh.shio.app"
    private let deviceTokenKey = "shio.push.deviceToken"
    /// Set this (App Group default) to your relay base URL to enable away-push.
    private let relayURLKey = "shio.relay.baseURL"

    private(set) var deviceToken: String?

    private override init() {
        super.init()
        deviceToken = defaults?.string(forKey: deviceTokenKey)
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Ask for notification permission and register with APNs. Safe to call
    /// repeatedly; the system only prompts once.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        configureNotificationActions()
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// On launch: if notifications are already granted, register for remote
    /// notifications (CloudKit/away pushes can't deliver without this) and
    /// install the Approve/Deny actions. Silent — never prompts. (The first-run
    /// permission prompt stays contextual, via requestAuthorizationAndRegister.)
    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        print("[shio] push: registerIfAuthorized authStatus=\(settings.authorizationStatus.rawValue) (0=notDetermined 2=authorized 3=provisional)")
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            print("[shio] push: NOT authorized — skipping registerForRemoteNotifications")
            return
        }
        configureNotificationActions()
        print("[shio] push: calling registerForRemoteNotifications()")
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: Lock-screen Approve / Deny (#33)

    /// Register the Approve / Deny actions on the "agent needs you" category and
    /// become the notification delegate. Tapping a button writes an `Action`
    /// (requires unlock — approving a blocked agent is sensitive).
    func configureNotificationActions() {
        let approve = UNNotificationAction(identifier: "APPROVE", title: "Approve",
                                           options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: "DENY", title: "Deny",
                                        options: [.destructive, .authenticationRequired])
        let category = UNNotificationCategory(identifier: CloudKitSignalService.needsYouCategory,
                                              actions: [approve, deny], intentIdentifiers: [], options: [])
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([category])
        center.delegate = self
    }

    /// Show the banner even while Shio is foregrounded, so you can act on it.
    /// (nonisolated — the notification objects aren't Sendable.)
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions { [.banner, .sound] }

    /// Handle a tapped notification — Approve/Deny write the keystroke back
    /// through iCloud; a plain tap routes to the host like before. Sendable bits
    /// (strings) are extracted before any actor hop.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let sid = Self.parse(userInfo, field: "sessionId")
        let host = Self.parse(userInfo, field: "hostId")
        switch action {
        case "APPROVE":
            if let sid { await CloudKitSignalService.shared.sendAction(sessionId: sid, key: "y") }
        case "DENY":
            if let sid { await CloudKitSignalService.shared.sendAction(sessionId: sid, key: "n") }
        default:
            if let host {
                await MainActor.run {
                    var info: [AnyHashable: Any] = ["hostId": host]
                    if let sid { info["sessionId"] = sid }
                    NotificationCenter.default.post(name: .shioConnectToHost, object: nil,
                                                    userInfo: info)
                }
            }
        }
    }

    /// Pull a field out of the CloudKit push payload (the Signal carried it).
    nonisolated private static func parse(_ userInfo: [AnyHashable: Any], field: String) -> String? {
        if let s = userInfo[field] as? String, !s.isEmpty { return s }
        if let note = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
           let s = note.recordFields?[field] as? String, !s.isEmpty { return s }
        return nil
    }

    // MARK: AppDelegate callbacks

    func didRegister(tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        print("[shio] push: ✅ APNs token registered \(hex.prefix(8))…")
        deviceToken = hex
        defaults?.set(hex, forKey: deviceTokenKey)
        Task { await registerWithRelay(deviceToken: hex) }
    }

    func didFailToRegister(_ error: any Error) {
        print("[shio] APNs registration failed: \(error.localizedDescription)")
    }

    /// Forward a Live Activity push-to-update token to the relay so it can
    /// drive lock-screen updates remotely. Scaffold — no-op without a relay.
    func registerActivityPushToken(_ token: String, sessionID: UUID) async {
        await post(path: "activity-token", body: [
            "deviceToken": deviceToken ?? "",
            "activityToken": token,
            "sessionID": sessionID.uuidString,
        ])
    }

    // MARK: Relay (scaffold — flagged)

    private func registerWithRelay(deviceToken: String) async {
        await post(path: "register", body: ["deviceToken": deviceToken])
    }

    /// POST to the relay if one is configured; otherwise skip quietly. The
    /// relay is the one consciously-scoped Shio-operated piece — opaque E2E,
    /// self-hostable (see `relay/README.md`).
    private func post(path: String, body: [String: String]) async {
        guard let base = defaults?.string(forKey: relayURLKey),
              let url = URL(string: base)?.appendingPathComponent(path) else {
            return  // No relay configured — away-push disabled. Honest no-op.
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        _ = try? await URLSession.shared.data(for: req)
    }
}

/// Minimal app delegate to bridge APNs callbacks (SwiftUI's App lifecycle
/// doesn't surface these) into `PushService`.
final class ShioAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in PushService.shared.didRegister(tokenData: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        Task { @MainActor in PushService.shared.didFailToRegister(error) }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        // Arrival is not intent: routing happens only when the user taps the
        // banner (`userNotificationCenter(_:didReceive:)`). Auto-routing here
        // would yank the terminal open the moment a push lands mid-use.
        return .noData
    }
}
