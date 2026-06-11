import SwiftUI
import AppKit

/// RC3 — the always-on away-watcher. The agent monitor already pushes your phone
/// when a local agent blocks (RC2), but only while ShioMac is running. This keeps
/// ShioMac alive in the **menu bar** (opt-in, default off) so the watch — and the
/// away-signal — survive closing the window. Off by default, so it never changes
/// the app's behavior unless you ask for it in Settings → Remote control.
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run the monitor at APP scope (not tied to a window) so it keeps
        // watching — and signalling — even when every window is closed.
        MacProjectAgentMonitor.shared.start()
        applyWatcherSetting()
        settingObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyWatcherSetting() }
        }
    }

    /// Stay resident (in the menu bar) when the watcher is on; quit normally otherwise.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !watcherEnabled
    }

    /// Re-open the main window when the dock/menu-bar asks (after the window was closed).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        true   // WindowGroup recreates the window on this
    }

    private var watcherEnabled: Bool {
        UserDefaults.standard.bool(forKey: MacSettings.menubarWatcherKey)
    }

    private func applyWatcherSetting() {
        if watcherEnabled, statusItem == nil { installStatusItem() }
        else if !watcherEnabled, statusItem != nil { removeStatusItem() }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "塩"
        item.button?.toolTip = "Shio — watching for agents that need you"

        let menu = NSMenu()
        let header = NSMenuItem(title: "Shio is watching", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Shio", action: #selector(openShio), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let quit = NSMenuItem(title: "Quit Shio", action: #selector(quitShio), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func removeStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func openShio() {
        NSApp.activate(ignoringOtherApps: true)
        // If a window exists, surface it; WindowGroup recreates one otherwise via reopen.
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitShio() { NSApp.terminate(nil) }
}
