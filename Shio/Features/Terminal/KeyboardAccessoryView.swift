import UIKit

/// The soft-keyboard accessory row that sits above the system keyboard and
/// gives users the keys iOS doesn't (Esc, Tab, Ctrl, Opt, arrows, symbols).
///
/// Behavior summary (mirrors macOS Terminal expectations):
///
///  - **Tap a modifier** → it's armed for the *next* keypress only.
///  - **Long-press a modifier** → sticky lock (stays on for chords). Tap again
///    to clear.
///  - **Tap a key** (e.g. Esc, ←, |) → sent immediately.
///  - **Long-press an arrow** → repeats. (iOS provides this for free via
///    UIControl's default behavior when we send actions on .touchDown.)
///
/// We use plain UIButtons in a horizontal stack — no SwiftUI here because
/// SwiftUI introduces input latency we can't accept on the keyboard layer.
final class KeyboardAccessoryView: UIInputView {

    weak var terminalInput: TerminalInputView?

    private let stack = UIStackView()
    private let scrollView = UIScrollView()

    // Modifier buttons keep references so we can update their selected/locked
    // appearance.
    private var modifierButtons: [KeyModifiers: ModifierKey] = [:]

    init(input: TerminalInputView) {
        self.terminalInput = input
        super.init(frame: .zero, inputViewStyle: .keyboard)
        allowsSelfSizing = true
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.layoutMargins = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        heightAnchor.constraint(equalToConstant: 46).isActive = true

        layoutKeys()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Key layout

    private func layoutKeys() {
        addImmediateKey(label: "esc",  bytes: "\u{1B}")
        addImmediateKey(label: "tab",  bytes: "\t")
        addModifierKey(.control, label: "ctrl")
        addModifierKey(.alt,     label: "opt")

        addSeparator()

        addImmediateKey(label: "←", bytes: "\u{1B}[D")
        addImmediateKey(label: "↓", bytes: "\u{1B}[B")
        addImmediateKey(label: "↑", bytes: "\u{1B}[A")
        addImmediateKey(label: "→", bytes: "\u{1B}[C")

        addSeparator()

        for sym in ["|", "~", "/", "\\", "-", "_", "{", "}", "[", "]"] {
            addImmediateKey(label: sym, bytes: sym)
        }
    }

    private func addImmediateKey(label: String, bytes: String) {
        let key = ImmediateKey(label: label, bytes: bytes)
        key.onTap = { [weak self] bytes in self?.terminalInput?.onBytes?(bytes) }
        stack.addArrangedSubview(key)
    }

    private func addModifierKey(_ mod: KeyModifiers, label: String) {
        let key = ModifierKey(label: label, modifier: mod)
        key.onTap = { [weak self] in
            guard let self else { return }
            // Toggle pending: if pending is set, clear; otherwise set.
            let pending = self.terminalInput?.pendingModifiers ?? []
            let sticky  = self.terminalInput?.stickyModifiers ?? []
            if sticky.contains(mod) {
                self.terminalInput?.setStickyModifier(mod, on: false)
                key.appearance = .off
            } else if pending.contains(mod) {
                self.terminalInput?.setPendingModifier(mod, on: false)
                key.appearance = .off
            } else {
                self.terminalInput?.setPendingModifier(mod, on: true)
                key.appearance = .pending
            }
        }
        key.onLongPress = { [weak self] in
            guard let self else { return }
            let sticky = self.terminalInput?.stickyModifiers ?? []
            if sticky.contains(mod) {
                self.terminalInput?.setStickyModifier(mod, on: false)
                key.appearance = .off
            } else {
                self.terminalInput?.setStickyModifier(mod, on: true)
                self.terminalInput?.setPendingModifier(mod, on: false)
                key.appearance = .locked
            }
        }
        modifierButtons[mod] = key
        stack.addArrangedSubview(key)
    }

    private func addSeparator() {
        let sep = UIView()
        sep.backgroundColor = .separator.withAlphaComponent(0.4)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(sep)
    }
}

// MARK: - Key buttons

private class BaseKey: UIControl {
    let titleLabel = UILabel()

    init(label: String) {
        super.init(frame: .zero)
        titleLabel.text = label
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        backgroundColor = UIColor.systemFill
        heightAnchor.constraint(equalToConstant: 34).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.06) {
                self.backgroundColor = self.isHighlighted ?
                    UIColor.tertiarySystemFill :
                    UIColor.systemFill
            }
        }
    }
}

private final class ImmediateKey: BaseKey {
    var onTap: ((String) -> Void)?
    private let bytes: String

    init(label: String, bytes: String) {
        self.bytes = bytes
        super.init(label: label)
        addTarget(self, action: #selector(fire), for: .touchDown)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap?(bytes)
    }
}

private final class ModifierKey: BaseKey {
    enum Appearance { case off, pending, locked }
    var appearance: Appearance = .off { didSet { refresh() } }

    let modifier: KeyModifiers
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?

    init(label: String, modifier: KeyModifiers) {
        self.modifier = modifier
        super.init(label: label)
        addTarget(self, action: #selector(fireTap), for: .touchUpInside)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(fireLongPress(_:)))
        lp.minimumPressDuration = 0.32
        addGestureRecognizer(lp)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func fireTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap?()
    }
    @objc private func fireLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPress?()
    }

    private func refresh() {
        switch appearance {
        case .off:
            backgroundColor = UIColor.systemFill
            titleLabel.textColor = .label
        case .pending:
            backgroundColor = UIColor.label.withAlphaComponent(0.85)
            titleLabel.textColor = UIColor.systemBackground
        case .locked:
            backgroundColor = UIColor.label
            titleLabel.textColor = UIColor.systemBackground
        }
    }
}
