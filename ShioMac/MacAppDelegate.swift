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

    /// Ask before quitting while this Mac is the thing holding a session open
    /// for another device. Silent on every other occasion, because a warning
    /// that always fires is one people learn to dismiss without reading.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard PowerKeeper.shared.isHolding else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Quit Shio and let this Mac sleep?"
        alert.informativeText =
            "Shio is keeping this Mac awake so your other devices can reach it. "
            + "Quitting releases that, and the Mac may sleep and drop off your phone.\n\n"
            + "Anything running in a tmux session keeps running, and will still be "
            + "there when the Mac is awake again."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// Re-open the main window when the dock asks (after the window was closed).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        true   // WindowGroup recreates the window on this
    }
}
