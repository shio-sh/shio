import UIKit

/// Invisible UIKit view that captures all keyboard input — hardware and
/// soft — and translates it into raw bytes for the SSH stream. This is the
/// foundation of Shio's keyboard correctness: every chord that works in
/// macOS Terminal must work here.
///
/// We override `pressesBegan`/`pressesChanged`/`pressesEnded` to intercept
/// hardware keyboard events before they reach the responder chain, and
/// `insertText`/`deleteBackward` from `UIKeyInput` to handle soft-keyboard
/// characters. The `KeyboardAccessoryView` (see Brick 4 part 2) sets modifier
/// state via `setModifier(_:)` so users can tap Ctrl, then a letter.
final class TerminalInputView: UIView {

    /// Called with raw bytes to send over the SSH channel.
    var onBytes: ((String) -> Void)?

    /// Modifier state controlled by the soft accessory row (tap → next key
    /// only; sticky → persists until tapped off).
    private(set) var pendingModifiers: KeyModifiers = []
    private(set) var stickyModifiers:  KeyModifiers = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        // Clear iPad's QuickType bar above the system keyboard. None of those
        // buttons make sense for a terminal and they steal vertical space
        // from the accessory row.
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Text input traits
    //
    // A terminal wants *none* of iOS's text-helping behaviors. Autocorrect
    // mangles commands. Auto-capitalization makes the first letter of every
    // sentence wrong. Smart quotes break `'foo'`. The QuickType prediction
    // bar (iOS 17+ inline predictions, plus the older suggestions row)
    // covers our accessory keys. We turn every one of them off.
    //
    // These come from the UITextInputTraits protocol (which UIKeyInput
    // conforms to via UITextInput), so they're protocol requirements we
    // implement — not overrides of a UIView property.

    var autocorrectionType:    UITextAutocorrectionType    = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType:     UITextSpellCheckingType     = .no
    var smartQuotesType:       UITextSmartQuotesType       = .no
    var smartDashesType:       UITextSmartDashesType       = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    /// ASCII-only keyboard. Reduces the chance of IME / emoji layouts
    /// surprising terminal apps.
    var keyboardType:          UIKeyboardType              = .asciiCapable
    /// iOS 17+ inline predictions — the ghost-text suggestions that appear
    /// inline as you type. Off for terminals.
    var inlinePredictionType:  UITextInlinePredictionType  = .no

    // MARK: - First responder / IME

    override var canBecomeFirstResponder: Bool { true }

    // Tell UIKit we accept text input.
    override var canResignFirstResponder: Bool { true }

    // The keyboard accessory row is attached by KeyboardAccessoryView (Brick 4 P2).
    private var _inputAccessoryView: UIView?
    override var inputAccessoryView: UIView? {
        get { _inputAccessoryView }
    }
    func attachAccessoryView(_ view: UIView) {
        _inputAccessoryView = view
        reloadInputViews()
    }

    // MARK: - Soft keyboard modifier control

    func setPendingModifier(_ mod: KeyModifiers, on: Bool) {
        if on { pendingModifiers.insert(mod) } else { pendingModifiers.remove(mod) }
    }
    func setStickyModifier(_ mod: KeyModifiers, on: Bool) {
        if on { stickyModifiers.insert(mod) } else { stickyModifiers.remove(mod) }
    }
    func clearPendingModifiers() {
        pendingModifiers = []
    }

    private func consumeModifiers() -> KeyModifiers {
        let combined = pendingModifiers.union(stickyModifiers)
        pendingModifiers = []   // tap-once consumed
        return combined
    }

    // MARK: - Hardware keyboard interception

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            let modifiers = KeyModifiers(uiKeyModifierFlags: key.modifierFlags)
                .union(consumeModifiers())
            if let bytes = ANSI.bytes(for: key, modifiers: modifiers) {
                onBytes?(bytes)
                handled = true
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    // We don't currently autorepeat on the SSH side — the server handles it.
    // pressesChanged/pressesEnded fall through to super.
}

// MARK: - UIKeyInput / soft keyboard

extension TerminalInputView: UIKeyInput {

    var hasText: Bool { false }

    func insertText(_ text: String) {
        let modifiers = consumeModifiers()
        if modifiers.isEmpty {
            // Plain text — just send it.
            onBytes?(text)
        } else {
            // For each character, apply the modifier translation.
            for scalar in text.unicodeScalars {
                if let bytes = ANSI.bytesForCharacter(scalar, modifiers: modifiers) {
                    onBytes?(bytes)
                }
            }
        }
    }

    func deleteBackward() {
        // DEL (0x7F) is what macOS Terminal sends; bash/zsh expect it.
        onBytes?("\u{7F}")
    }
}
