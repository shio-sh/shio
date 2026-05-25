import UIKit

/// Detects whether Tailscale is installed on this iPhone via URL scheme probe.
/// We can't enumerate the user's tailnet without their consent (Tailscale's
/// iOS app doesn't expose a public API), but we can tell whether the app
/// exists so onboarding can branch.
enum TailscaleDetector {

    /// Tailscale's documented URL scheme. Present on installed devices since
    /// the iOS app gained universal links.
    private static let scheme = "tailscale"

    @MainActor
    static var isInstalled: Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Open Tailscale (or trigger the install path via App Store).
    @MainActor
    static func openTailscaleOrAppStore() {
        if let url = URL(string: "\(scheme)://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let appStore = URL(string: "https://apps.apple.com/app/tailscale/id1470499037") {
            UIApplication.shared.open(appStore)
        }
    }
}
