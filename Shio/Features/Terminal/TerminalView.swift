import SwiftUI
import WebKit
import UIKit

/// SwiftUI view that hosts the xterm.js terminal.
/// Owns the `TerminalWebViewController` and a `TerminalInputView` (UIKit) that
/// captures hardware and soft keyboard input before WebKit ever sees it.
struct TerminalView: UIViewRepresentable {

    /// Bidirectional pipe owner. Swift writes into the terminal via
    /// `controller.write(_:)`; user input arrives via `onInput`.
    let controller: TerminalWebViewController

    /// Currently-active theme; switches automatically on system appearance change.
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView(controller: controller)
        container.backgroundColor = .clear
        controller.onReady = { [weak controller] in
            let theme: TerminalTheme = context.environment.colorScheme == .dark ? .dark : .light
            controller?.applyTheme(theme)
        }
        controller.load()
        return container
    }

    func updateUIView(_ uiView: TerminalContainerView, context: Context) {
        let theme: TerminalTheme = colorScheme == .dark ? .dark : .light
        controller.applyTheme(theme)
        uiView.setNeedsLayout()
    }
}

/// UIKit container that:
/// 1. Hosts the WKWebView (xterm.js).
/// 2. Hosts the keyboard-input proxy view that becomes first responder.
/// 3. Lays both out edge-to-edge.
final class TerminalContainerView: UIView {

    let controller: TerminalWebViewController
    let terminalInput: TerminalInputView

    init(controller: TerminalWebViewController) {
        self.controller = controller
        self.terminalInput = TerminalInputView()
        super.init(frame: .zero)

        // Attach the soft-keyboard accessory row.
        let accessory = KeyboardAccessoryView(input: terminalInput)
        terminalInput.attachAccessoryView(accessory)

        addSubview(controller.webView)
        addSubview(terminalInput)
        controller.webView.translatesAutoresizingMaskIntoConstraints = false
        terminalInput.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.webView.topAnchor.constraint(equalTo: topAnchor),
            controller.webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controller.webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controller.webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalInput.topAnchor.constraint(equalTo: topAnchor),
            terminalInput.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalInput.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalInput.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Wire input → controller (Brick 4 will wire controller → SSH).
        terminalInput.onBytes = { [weak controller] bytes in
            controller?.onInput?(bytes)
        }

        // Tapping the terminal makes the input view first responder so the
        // soft keyboard appears.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleTap() {
        if !terminalInput.isFirstResponder {
            terminalInput.becomeFirstResponder()
        }
        controller.focus()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            terminalInput.becomeFirstResponder()
        }
    }
}
