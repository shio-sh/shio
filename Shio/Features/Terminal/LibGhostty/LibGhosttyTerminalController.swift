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
        // Keep a couple of rows of overlap for reading continuity.
        let amount = max(1, currentRows - 2)
        if surfaceView.isAlternateScreenActive {
            // A TUI (less/vim/htop, or tmux with mouse on) owns the buffer;
            // libghostty's own scrollback is suspended. Send a wheel scroll
            // big enough to move ~a page so the program scrolls itself.
            // sendMouseScroll: +deltaY = wheel-up = older content into view.
            let pointsPerRow: CGFloat = 18
            let sign: CGFloat = directionDown ? -1 : 1
            surfaceView.sendMouseScroll(deltaY: sign * CGFloat(amount) * pointsPerRow)
        } else {
            // scrollLines: + = toward live tail, - = into older history.
            surfaceView.scrollLines(directionDown ? amount : -amount)
        }
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

    // The following are kept as no-ops for now so SessionViewModel /
    // TerminalView code paths don't have to change.
    func setFontSize(_ px: CGFloat) {}
    func applyTheme(_ theme: TerminalTheme) {}
    func fit() {}
    func focus() { surfaceView.setFocus(true) }
    func load() { /* libghostty initializes synchronously in init */
        Task { @MainActor in
            // Mimic onReady semantics so SessionViewModel can apply a theme.
            onReady?()
        }
    }
}
