import UIKit
import SwiftUI

/// A second `UIWindow` at an elevated window level that hosts the
/// privacy splash and FaceID lock overlay. Sits above every SwiftUI
/// surface — including `.fullScreenCover` modals like `TerminalScene`.
///
/// Architecture: the window itself is hidden (`isHidden = true`)
/// whenever there is nothing to display, which lets iOS route touches
/// to the main window naturally without any custom hit-testing.
/// State is driven by `UIApplication` lifecycle notifications — not
/// `@Environment(\.scenePhase)`, which is unreliable inside secondary
/// UIWindows because they're never the key window.
@MainActor
final class OverlayWindow {
    static let shared = OverlayWindow()

    private var window: UIWindow?
    private var hosting: UIHostingController<OverlayRootView>?
    /// True if the user has crossed the locked threshold and hasn't
    /// re-authenticated yet. Survives background/foreground cycles
    /// until the biometric prompt succeeds.
    private var pendingLock: Bool = false

    private init() {
        let nc = NotificationCenter.default
        nc.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWillResignActive()
            }
        }
        nc.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDidBecomeActive()
            }
        }
    }

    /// Attach the window to the first available UIWindowScene. Safe to
    /// call multiple times — re-entries no-op. Retries on a short delay
    /// if no scene is connected yet (first-frame race).
    func install() {
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached })
        else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.install()
            }
            return
        }

        let host = UIHostingController(rootView: OverlayRootView(mode: .privacy, onUnlock: {}))
        host.view.backgroundColor = .clear

        let w = UIWindow(windowScene: scene)
        w.windowLevel = UIWindow.Level.alert - 1
        w.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = true   // hidden by default; touches go to main window
        self.window = w
        self.hosting = host
    }

    // MARK: - Lifecycle handlers

    private func handleWillResignActive() {
        print("[shio] OverlayWindow willResignActive (lockEnabled=\(appLockEnabled))")
        if appLockEnabled {
            pendingLock = true
        }
        show(.privacy)
    }

    private func handleDidBecomeActive() {
        print("[shio] OverlayWindow didBecomeActive (pendingLock=\(pendingLock))")
        if pendingLock {
            show(.locked)
        } else {
            hide()
        }
    }

    // MARK: - Visibility

    private enum Mode { case privacy, locked }

    private func show(_ mode: Mode) {
        guard let window, let hosting else { return }
        let unlock: () -> Void = { [weak self] in
            self?.pendingLock = false
            self?.hide()
        }
        switch mode {
        case .privacy:
            hosting.rootView = OverlayRootView(mode: .privacy, onUnlock: {})
        case .locked:
            hosting.rootView = OverlayRootView(mode: .locked, onUnlock: unlock)
        }
        window.isHidden = false
    }

    private func hide() {
        window?.isHidden = true
    }

    // MARK: - Preference lookup

    private var appLockEnabled: Bool {
        UserDefaults(suiteName: ShioModelContainer.appGroup)?
            .bool(forKey: AppLock.defaultsKey) ?? false
    }
}

/// SwiftUI tree hosted inside the overlay window. Renders either the
/// privacy splash or the lock overlay — never "nothing", because the
/// window itself is hidden when there's nothing to show.
private struct OverlayRootView: View {
    enum Mode { case privacy, locked }
    let mode: Mode
    let onUnlock: () -> Void

    var body: some View {
        switch mode {
        case .privacy:
            PrivacyScreenView()
        case .locked:
            AppLockOverlay(onUnlocked: onUnlock)
        }
    }
}
