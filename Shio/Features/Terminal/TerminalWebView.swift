import SwiftUI
import WebKit

/// Hosts the xterm.js terminal in a WKWebView. Acts as the rendering surface;
/// SSH I/O is piped through `write(_:)` and user input arrives via the
/// `onInput` callback. Hardware/soft keyboard input is intercepted by UIKit
/// at the `TerminalInputView` layer and forwarded here as raw bytes —
/// xterm.js itself doesn't see raw key events.
@MainActor
final class TerminalWebViewController {

    /// Called whenever the terminal generates output (paste, IME). UIKit
    /// keyboard input bypasses this and is delivered directly to the session.
    var onInput:  ((String) -> Void)?
    /// Called whenever the terminal geometry changes (cols × rows).
    var onResize: ((Int, Int) -> Void)?
    /// Called when xterm.js finishes initializing.
    var onReady:  (() -> Void)?

    let webView: WKWebView

    private let bridge = ScriptBridge()
    private var hasLoaded = false

    init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.suppressesIncrementalRendering = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let userContent = WKUserContentController()
        config.userContentController = userContent

        webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        bridge.controller = self
        userContent.add(bridge, name: "shioInput")
        userContent.add(bridge, name: "shioResize")
        userContent.add(bridge, name: "shioReady")
    }

    func load() {
        guard let url = Bundle.main.url(
            forResource: "terminal",
            withExtension: "html",
            subdirectory: "terminal"
        ) else {
            assertionFailure("terminal.html not bundled — check Brick 1 resources")
            return
        }
        let dir = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: dir)
    }

    // MARK: - Swift → JS

    func write(_ data: String) {
        let escaped = jsString(data)
        evaluate("window.shioWrite(\(escaped));")
    }

    func write(_ data: Data) {
        guard let str = String(data: data, encoding: .utf8) else { return }
        write(str)
    }

    func reset() {
        evaluate("window.shioReset();")
    }

    func setFontSize(_ px: CGFloat) {
        evaluate("window.shioSetFontSize(\(Int(px)));")
    }

    func applyTheme(_ theme: TerminalTheme) {
        let js = theme.cssVariableAssignmentJS() + "window.shioApplyTheme();"
        evaluate(js)
    }

    func fit() {
        evaluate("window.shioFit();")
    }

    func focus() {
        evaluate("window.shioFocus();")
    }

    // MARK: -

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                #if DEBUG
                print("[Shio] JS eval error:", error.localizedDescription)
                #endif
            }
        }
    }

    private func jsString(_ s: String) -> String {
        // JSON-encode to safely escape for JS.
        let data = (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    // MARK: - Bridge callbacks

    fileprivate func didReceiveInput(_ data: String) {
        onInput?(data)
    }

    fileprivate func didResize(cols: Int, rows: Int) {
        onResize?(cols, rows)
    }

    fileprivate func didBecomeReady() {
        hasLoaded = true
        onReady?()
    }
}

// MARK: - WKScriptMessageHandler bridge

@MainActor
private final class ScriptBridge: NSObject, WKScriptMessageHandler {
    weak var controller: TerminalWebViewController?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // WKScriptMessageHandler is @MainActor in iOS 17+, so this method
        // already runs on MainActor and we can read message properties
        // directly.
        guard let controller = self.controller else { return }
        switch message.name {
        case "shioInput":
            if let str = message.body as? String { controller.didReceiveInput(str) }
        case "shioResize":
            if let dict = message.body as? [String: Any],
               let cols = dict["cols"] as? Int,
               let rows = dict["rows"] as? Int {
                controller.didResize(cols: cols, rows: rows)
            }
        case "shioReady":
            controller.didBecomeReady()
        default:
            break
        }
    }
}
