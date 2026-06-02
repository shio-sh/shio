import Foundation
import GhosttyKit
import os.log

/// Minimal Swift bridge over libghostty's C ABI.
///
/// Shio uses libghostty for terminal rendering and the External IO backend
/// for input/output. We don't need libghostty's app-level clipboard /
/// window-action ferrying — those callbacks are stubbed and clipboard is
/// handled via UIKit elsewhere.
final class LibGhosttyBridge: @unchecked Sendable {
    static let shared = LibGhosttyBridge()

    /// The terminal background color. Both the libghostty surface and
    /// the SwiftUI bleed background read from this single source of truth
    /// so the two layers can never visually drift apart.
    static let terminalBackgroundHex: UInt32 = 0x282C34

    private let logger = Logger(subsystem: "sh.shio.app", category: "libghostty")

    nonisolated(unsafe) private(set) var app: ghostty_app_t?
    nonisolated(unsafe) private var config: ghostty_config_t?

    private let lock = NSLock()
    nonisolated(unsafe) private var initialized = false

    /// Coalesces wakeup→tick scheduling: at most one `ghostty_app_tick` is
    /// queued on main at a time. Without this, several surfaces (e.g. a split)
    /// can each post wakeups faster than main drains them, flooding the queue
    /// and beach-balling the app.
    private let tickLock = NSLock()
    nonisolated(unsafe) private var tickScheduled = false

    private init() {}

    private func scheduleTick() {
        tickLock.lock()
        if tickScheduled { tickLock.unlock(); return }
        tickScheduled = true
        tickLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tickLock.lock()
            self.tickScheduled = false
            self.tickLock.unlock()
            if let app = self.app { ghostty_app_tick(app) }
        }
    }

    func ensureInitialized() {
        lock.lock()
        defer { lock.unlock() }
        guard !initialized else { return }
        initialized = true

        // ghostty_init must be called once per process. We don't have a
        // real argv to pass; libghostty just needs a valid pointer pair.
        let argc = CommandLine.argc
        let argv = CommandLine.unsafeArgv
        if ghostty_init(UInt(argc), argv) != GHOSTTY_SUCCESS {
            logger.critical("ghostty_init failed")
            return
        }

        guard let cfg = ghostty_config_new() else {
            logger.critical("ghostty_config_new failed")
            return
        }

        // Match libghostty's default terminal background so Shio's bleed
        // (drawn under the status bar / home indicator with the same hex)
        // looks seamless against the surface canvas. Defined as a single
        // source of truth so the SwiftUI ZStack background and the libghostty
        // surface can never drift apart.
        let bgHex = String(format: "%06X", LibGhosttyBridge.terminalBackgroundHex)
        var configString = """
        background = #\(bgHex)
        foreground = #FFFFFF
        """
        #if os(macOS)
        // Give the cell grid a gutter so text isn't jammed against the
        // surface edge (the default 2pt looks flush). libghostty fills the
        // padding with the terminal background, so the gutter is seamless.
        // macOS only — iOS manages its own insets / safe-area bleed.
        configString += "\nwindow-padding-x = 12\nwindow-padding-y = 8"
        // Bind scrollback search to a real keypress so ghostty handles ⌘F via
        // its own keybind path (interactive search mode), not our binding_action
        // call (which no-ops). ⌘G / ⇧⌘G step matches.
        configString += "\nkeybind = cmd+f=start_search"
        configString += "\nkeybind = cmd+g=navigate_search:next"
        configString += "\nkeybind = shift+cmd+g=navigate_search:previous"
        #endif
        configString.withCString { cstr in
            ghostty_config_load_string(cfg, cstr, strlen(cstr))
        }

        ghostty_config_finalize(cfg)
        self.config = cfg

        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            // libghostty calls this (off the main thread) when it has work
            // pending — chiefly the local-PTY read loop used by the macOS
            // DEFAULT IO backend. We hop to main and tick the app so it
            // drains IO and re-renders. Harmless for the iOS EXTERNAL path
            // (which drives rendering via write_bytes instead).
            wakeup_cb: { userdata in
                guard let userdata else { return }
                let bridge = Unmanaged<LibGhosttyBridge>.fromOpaque(userdata).takeUnretainedValue()
                bridge.scheduleTick()
            },
            action_cb: { _, _, _ in
                // Default: nothing handled. Returning true tells libghostty
                // we accepted the action so it won't try a fallback path.
                return true
            },
            read_clipboard_cb: { _, _, _ in
                // We don't ferry clipboard through libghostty; the UIKit
                // pasteboard is handled directly by Shio.
                return false
            },
            confirm_read_clipboard_cb: { _, _, _, _ in },
            write_clipboard_cb: { _, _, _, _, _ in },
            close_surface_cb: { _, _ in }
        )

        guard let app = ghostty_app_new(&runtime, cfg) else {
            logger.critical("ghostty_app_new failed")
            return
        }
        self.app = app
        logger.info("libghostty initialized")
    }
}
