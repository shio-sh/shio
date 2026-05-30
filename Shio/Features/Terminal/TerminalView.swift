import SwiftUI
import UIKit

/// SwiftUI view that hosts the libghostty terminal surface.
/// Owns the `LibGhosttyTerminalController` and a `TerminalInputView` (UIKit)
/// that captures hardware and soft keyboard input.
struct TerminalView: UIViewRepresentable {

    /// Bidirectional pipe owner. Swift writes into the terminal via
    /// `controller.write(_:)`; user input arrives via `onInput`.
    let controller: LibGhosttyTerminalController

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
/// 1. Hosts the libghostty Metal-backed surface view.
/// 2. Hosts the keyboard-input proxy view that becomes first responder.
/// 3. Lays both out edge-to-edge.
final class TerminalContainerView: UIView {

    let controller: LibGhosttyTerminalController
    let terminalInput: TerminalInputView

    init(controller: LibGhosttyTerminalController) {
        self.controller = controller
        self.terminalInput = TerminalInputView()
        super.init(frame: .zero)

        let accessory = KeyboardAccessoryView(input: terminalInput)
        terminalInput.attachAccessoryView(accessory)

        let surface = controller.surfaceView
        addSubview(surface)
        addSubview(terminalInput)
        surface.translatesAutoresizingMaskIntoConstraints = false
        terminalInput.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalInput.topAnchor.constraint(equalTo: topAnchor),
            terminalInput.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalInput.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalInput.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Wire input → controller → SSH (via SessionViewModel.onInput).
        terminalInput.onBytes = { [weak controller] bytes in
            controller?.onInput?(bytes)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        addGestureRecognizer(pinch)

        // One-finger pan = scroll the terminal history. Two-finger pinch
        // = zoom (handled separately). Different minimum touch counts
        // make them naturally exclusive without needing delegate plumbing.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        // The pan only kicks in once movement exceeds iOS's recognition
        // threshold, so brief taps still reach TerminalInputView for
        // keyboard focus.
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    private var pinchAccumulatedScale: CGFloat = 1.0

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            pinchAccumulatedScale = 1.0
        case .changed:
            pinchAccumulatedScale *= recognizer.scale
            recognizer.scale = 1.0
            controller.surfaceView.applyPinchDelta(&pinchAccumulatedScale)
        default:
            break
        }
    }

    /// Accumulated sub-line pan translation. We dispatch a discrete
    /// `scroll_page_lines` step whenever this crosses a row-height
    /// threshold; remainder carries into the next event for smooth feel.
    private var scrollAccumulatedPoints: CGFloat = 0
    /// Points-per-row heuristic for normal-screen scrolling — each
    /// accumulated unit scrolls one row in libghostty's scrollback.
    private let pointsPerScrollLine: CGFloat = 16

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            scrollAccumulatedPoints = 0
        case .changed:
            let translation = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)

            if controller.surfaceView.isAlternateScreenActive {
                // Alt-screen path: send a mouse-wheel event with the
                // raw pixel delta. tmux (with mouse mode on, which
                // Shio enables via TmuxResume) interprets these as
                // scroll-its-own-buffer; Claude Code / vim / htop with
                // their respective mouse-capture modes do the same.
                // No accumulation needed — libghostty handles
                // sub-line precision internally.
                controller.surfaceView.sendMouseScroll(deltaY: translation.y)
            } else {
                // Normal-screen path: accumulate to whole-line steps
                // and shift libghostty's scrollback via the binding
                // action. Negative units = scroll up into older.
                scrollAccumulatedPoints += translation.y
                let step = Int(scrollAccumulatedPoints / pointsPerScrollLine)
                if step != 0 {
                    scrollAccumulatedPoints -= CGFloat(step) * pointsPerScrollLine
                    controller.surfaceView.scrollLines(-step)
                }
            }
        default:
            break
        }
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
