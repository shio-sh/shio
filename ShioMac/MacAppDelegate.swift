import SwiftUI
import AppKit

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// Quit when the last window closes, like a normal Mac app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Re-open the main window when the dock asks (after the window was closed).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        true   // WindowGroup recreates the window on this
    }
}
