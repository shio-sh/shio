import SwiftUI
import AppKit

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// Quit when the last window closes, like a normal Mac app.
    ///
    /// Except this one is not quite normal: quitting releases the sleep
    /// assertion PowerKeeper holds, which is what keeps this Mac awake and
    /// reachable from a phone. Closing a window is therefore also the act that
    /// lets your other devices lose this machine, and nothing used to say so.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Ask before quitting while this Mac is holding a session open for
    /// another device — but only when a person chose to quit.
    ///
    /// The first version ran a blocking modal for EVERY termination. macOS
    /// gives an app a short window to answer the quit event on logout,
    /// restart or a system update, so blocking there makes the system report
    /// that Shio prevented the shutdown and cancels it. It also fired when the
    /// last window was closed, since this app terminates with its last window,
    /// which meant clicking the red button raised a dialog nobody asked for.
    ///
    /// So: only for an explicit ⌘Q or Quit menu item, and non-blocking, using
    /// `.terminateLater` with a sheet rather than freezing the main thread.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard PowerKeeper.shared.isHolding, isUserInitiatedQuit() else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Quit Shio and let this Mac sleep?"
        alert.informativeText =
            "Shio is keeping this Mac awake so your other devices can reach it. "
            + "Quitting releases that, and the Mac may sleep and drop off your phone.\n\n"
            + "Anything you have running keeps running, and will still be "
            + "there when the Mac is awake again."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if let window = sender.keyWindow ?? sender.windows.first(where: \.isVisible) {
            alert.beginSheetModal(for: window) { response in
                sender.reply(toApplicationShouldTerminate: response == .alertFirstButtonReturn)
            }
            return .terminateLater
        }
        // No window to hang a sheet on (the app is already windowless), so
        // there is nothing to interrupt: let it go.
        return .terminateNow
    }

    /// True when the quit came from the keyboard or the menu rather than from
    /// the system. A logout or restart arrives with no current event.
    private func isUserInitiatedQuit() -> Bool {
        guard let event = NSApp.currentEvent else { return false }
        switch event.type {
        case .keyDown where event.modifierFlags.contains(.command):
            return true
        case .leftMouseUp, .leftMouseDown, .otherMouseUp, .applicationDefined:
            return true
        default:
            return false
        }
    }

    /// Re-open the main window when the dock asks (after the window was closed).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        true   // WindowGroup recreates the window on this
    }
}
