import Foundation
import Observation
import UIKit
import UserNotifications

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
final class PushService {
    static let shared = PushService()

    private let appGroup = "group.sh.shio.app"
    private let deviceTokenKey = "shio.push.deviceToken"
    /// Set this (App Group default) to your relay base URL to enable away-push.
    private let relayURLKey = "shio.relay.baseURL"

    private(set) var deviceToken: String?

    private init() {
        deviceToken = defaults?.string(forKey: deviceTokenKey)
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Ask for notification permission and register with APNs. Safe to call
    /// repeatedly; the system only prompts once.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: AppDelegate callbacks

    func didRegister(tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        defaults?.set(hex, forKey: deviceTokenKey)
        Task { await registerWithRelay(deviceToken: hex) }
    }

    func didFailToRegister(_ error: any Error) {
        print("[shio] APNs registration failed: \(error.localizedDescription)")
    }

    /// Handle an incoming away-push. The opaque payload may carry the host id
    /// to jump to; we route through the same path the App Intent / Handoff /
    /// deep links use, so behavior stays unified.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        let hostId = (userInfo["hostId"] as? String)
            ?? ((userInfo["aps"] as? [String: Any])?["hostId"] as? String)
        guard let hostId else { return }
        NotificationCenter.default.post(
            name: .shioConnectToHost,
            object: nil,
            userInfo: ["hostId": hostId]
        )
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
        await PushService.shared.handleRemoteNotification(userInfo)
        return .noData
    }
}
