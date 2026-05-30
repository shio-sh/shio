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
            self.onResize?(Int(cols), Int(rows))
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
