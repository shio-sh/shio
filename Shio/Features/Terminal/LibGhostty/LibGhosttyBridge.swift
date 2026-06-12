import Foundation
import GhosttyKit
import os.log
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Minimal Swift bridge over libghostty's C ABI.
///
/// Shio uses libghostty for terminal rendering and the External IO backend
/// for input/output. We don't need libghostty's app-level clipboard /
/// window-action ferrying — those callbacks are stubbed and clipboard is
/// handled via UIKit elsewhere.
final class LibGhosttyBridge: @unchecked Sendable {
    static let shared = LibGhosttyBridge()

    /// Terminal canvas per appearance — the SAME tokens the app chrome uses
    /// (light = the bone canvas, dark = ink-800), so surface and chrome are
    /// seamless in both modes. Resolved ONCE at libghostty init: the config
    /// is process-global, so an appearance flip mid-run applies on the next
    /// launch. The SwiftUI bleed reads `terminalBackgroundHex` (what the
    /// surfaces actually got), so the two layers can never drift apart.
    static let terminalBackgroundDarkHex: UInt32 = 0x0E0E10
    static let terminalBackgroundLightHex: UInt32 = 0xF4EEDF
    static let terminalForegroundDarkHex: UInt32 = 0xF2F2F4
    static let terminalForegroundLightHex: UInt32 = 0x0E0E10
    nonisolated(unsafe) private(set) static var terminalBackgroundHex: UInt32 = 0x0E0E10

    /// The system appearance at init time. Surfaces are created on main.
    private static func systemPrefersDark() -> Bool {
        #if canImport(UIKit)
        return UITraitCollection.current.userInterfaceStyle != .light
        #else
        return MainActor.assumeIsolated {
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
        }
        #endif
    }

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

        // Resolve the terminal canvas from the system appearance (see the
        // token comment above) and record it as the bleed's source of truth.
        let dark = Self.systemPrefersDark()
        let bg = dark ? Self.terminalBackgroundDarkHex : Self.terminalBackgroundLightHex
        let fg = dark ? Self.terminalForegroundDarkHex : Self.terminalForegroundLightHex
        Self.terminalBackgroundHex = bg
        var configString = """
        background = #\(String(format: "%06X", bg))
        foreground = #\(String(format: "%06X", fg))
        """
        #if os(macOS)
        // Give the cell grid a gutter so text isn't jammed against the
        // surface edge (the default 2pt looks flush). libghostty fills the
        // padding with the terminal background, so the gutter is seamless.
        // macOS only — iOS manages its own insets / safe-area bleed.
        configString += "\nwindow-padding-x = 12\nwindow-padding-y = 8"
        // User preferences (Settings ⌘,). Applied at app launch; new surfaces
        // also set font_size per-surface. MacSettings is in the ShioMac target,
        // visible only inside this os(macOS) block.
        configString += "\nfont-size = \(Int(MacSettings.fontSize))"
        configString += "\ncursor-style = \(MacSettings.cursorStyle)"
        if !MacSettings.theme.isEmpty { configString += "\ntheme = \(MacSettings.theme)" }
        // NOTE: scrollback search (⌘F) is NOT bound. This libghostty binary
        // exposes search only as one-way notification actions (START_SEARCH /
        // SEARCH_TOTAL) with no C function to start search / set a needle / step
        // matches, and start_search no-ops in practice. Binding ⌘F here would
        // just swallow the key into a dead action. Revisit when GhosttyKit is
        // updated to a build with a complete embedded-search API.
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
