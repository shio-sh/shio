import UIKit
import Foundation

/// Mirrors `TerminalWebViewController`'s interface but is backed by
/// libghostty (External IO backend) instead of xterm.js in a WKWebView.
/// `SessionViewModel` can swap one for the other without changing its
/// SSH wiring.
@MainActor
final class LibGhosttyTerminalController {

    /// Called when the terminal generates bytes that should be written
    /// upstream (to the SSH channel). Matches xterm controller for parity.
    var onInput: ((String) -> Void)?

    /// Called when the terminal grid is resized.
    var onResize: ((Int, Int) -> Void)?

    /// No-op for libghostty (parity with WKWebView controller which
    /// surfaces this to clear an init banner). Kept to match the
    /// original protocol shape.
    var onReady: (() -> Void)?

    /// Reported when libghostty initialization fails (extremely unlikely
    /// post-bring-up but kept symmetrical with the WebView path).
    var onLoadFailure: ((String) -> Void)?

    let surfaceView: LibGhosttySurfaceView

    init() {
        self.surfaceView = LibGhosttySurfaceView(frame: .zero)
        self.surfaceView.onOutput = { [weak self] data in
            guard let self else { return }
            if let s = String(data: data, encoding: .utf8) {
                self.onInput?(s)
            } else {
                // Pass raw bytes through unchanged if not valid UTF-8;
                // callers downstream send Data → SSH.
                self.onInput?(String(decoding: data, as: UTF8.self))
            }
        }
        self.surfaceView.onResize = { [weak self] cols, rows in
            guard let self else { return }
            self.currentRows = Int(rows)
            self.onResize?(Int(cols), Int(rows))
        }
    }

    /// Latest grid height in rows, tracked from libghostty's resize
    /// callback. Drives a page's worth of scroll for the Page Up/Down
    /// buttons. Defaults to a sane value before the first resize lands.
    private(set) var currentRows: Int = 24

    /// Page the scrollback up (older content) by roughly one screen.
    func pageUp()   { page(directionDown: false) }
    /// Page the scrollback down (toward the live tail) by roughly one screen.
    func pageDown() { page(directionDown: true) }

    private func page(directionDown: Bool) {
        if surfaceView.isAlternateScreenActive {
            // A full-screen TUI (Claude Code, vim, htop) under tmux owns the
            // screen — ghostty's OWN scrollback is empty there, so scrolling it
            // does nothing (the bug). Instead synthesize SGR mouse-wheel events
            // and send them straight upstream; tmux (`set mouse on`) routes them
            // to the program, which scrolls its own buffer. This bypasses
            // ghostty's mouse-mode tracking, which mis-detects over SSH.
            wheelScroll(up: !directionDown, notches: max(3, (currentRows - 2) / 3))
        } else {
            // Normal screen: shift libghostty's real scrollback.
            let amount = max(1, currentRows - 2)
            surfaceView.scrollLines(directionDown ? amount : -amount)
        }
    }

    /// Send `notches` synthetic SGR (1006) mouse-wheel reports upstream. Wheel
    /// up = button 64, down = 65; the cell position just needs to land inside
    /// the pane so tmux routes it to the right place. Used by the Page buttons
    /// and the alt-screen pan gesture.
    func wheelScroll(up: Bool, notches: Int) {
        guard notches > 0 else { return }
        let button = up ? 64 : 65
        let row = max(1, currentRows / 2)
        let col = 4
        let one = "\u{1B}[<\(button);\(col);\(row)M"
        onInput?(String(repeating: one, count: notches))
    }

    // MARK: - Outgoing (SSH → terminal display)

    func write(_ data: String) {
        surfaceView.writeBytes(Data(data.utf8))
    }

    func write(_ data: Data) {
        surfaceView.writeBytes(data)
    }

    func reset() {
        // ANSI "RIS" — reset terminal to initial state.
        surfaceView.writeBytes(Data("\u{1B}c".utf8))
    }

    /// Free the libghostty surface and release its self-retain — call when the
    /// session is torn down so the surface doesn't leak (see shutdown()).
    func shutdown() { surfaceView.shutdown() }

    // The following are kept as no-ops for now so SessionViewModel /
    // TerminalView code paths don't have to change.
    func setFontSize(_ px: CGFloat) {}
    func fit() {}
    func focus() { surfaceView.setFocus(true) }
    func load() { /* libghostty initializes synchronously in init */
        Task { @MainActor in
            // Mimic onReady semantics so SessionViewModel can apply a theme.
            onReady?()
        }
    }
}
