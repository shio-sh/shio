import UIKit

/// Translates physical/soft keyboard events into the byte sequences expected
/// by a VT100/xterm terminal. This is the core of Shio's keyboard correctness.
///
/// References:
/// - xterm Control Sequences spec (https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
/// - macOS Terminal.app behavior (the comparison target).
///
/// Coverage:
/// - Plain printable characters (delegated to insertText path)
/// - Tab, Shift+Tab, Enter, Backspace, Esc
/// - Arrows (with all modifier permutations via CSI 1;<mod>X)
/// - Home/End/PgUp/PgDn (with modifiers)
/// - F1–F12 (with modifiers)
/// - Ctrl+<letter> → control characters 0x01–0x1A
/// - Alt/Opt-as-Meta → ESC prefix
/// - Insert/Delete keys
enum ANSI {

    private static let ESC = "\u{1B}"
    private static let CSI = "\u{1B}["

    /// Translate a hardware UIKey + tracked modifiers into a byte sequence.
    /// Returns nil if the key has no meaningful translation (e.g. Cmd-only
    /// chords, which should be left alone for system shortcuts).
    @MainActor
    static func bytes(for key: UIKey, modifiers: KeyModifiers) -> String? {

        // Cmd-only or Cmd+letter: let UIKit handle these as system shortcuts.
        // (Cmd+C / Cmd+V are intercepted higher up by UIResponder copy/paste.)
        if modifiers.contains(.command) {
            return nil
        }

        // Special / arrow / function keys → CSI sequences.
        if let csi = csiSequence(for: key.keyCode, modifiers: modifiers) {
            return csi
        }

        // Whatever's left: derive from the character payload.
        let chars = key.characters
        guard !chars.isEmpty else { return nil }

        // Backspace key (DEL byte) — xterm convention.
        if chars == "\u{8}" || chars == "\u{7F}" {
            // Alt+Backspace → ESC + DEL  (word-delete in bash/zsh).
            return modifiers.contains(.alt) ? ESC + "\u{7F}" : "\u{7F}"
        }

        // Tab key.
        if chars == "\t" {
            return modifiers.contains(.shift) ? "\(CSI)Z" : "\t"
        }

        // Enter key.
        if chars == "\r" || chars == "\n" {
            return "\r"
        }

        // Escape key.
        if chars == "\u{1B}" {
            return "\u{1B}"
        }

        // Ctrl + letter / Ctrl + symbol.
        if modifiers.contains(.control) {
            if let scalar = chars.unicodeScalars.first {
                if let ctrlByte = controlByte(for: scalar) {
                    let prefix = modifiers.contains(.alt) ? ESC : ""
                    return prefix + String(UnicodeScalar(ctrlByte))
                }
            }
            return nil
        }

        // Alt/Opt-as-Meta → ESC prefix on plain characters.
        if modifiers.contains(.alt) {
            return ESC + chars
        }

        // No modifiers — pass through.
        return chars
    }

    /// Translate a soft-keyboard character + modifiers (when no UIKey is
    /// available). Used by `insertText` after applying pending modifiers.
    static func bytesForCharacter(_ scalar: UnicodeScalar, modifiers: KeyModifiers) -> String? {
        if modifiers.contains(.command) { return nil }

        if modifiers.contains(.control) {
            guard let ctrlByte = controlByte(for: scalar) else { return nil }
            let prefix = modifiers.contains(.alt) ? ESC : ""
            return prefix + String(UnicodeScalar(ctrlByte))
        }
        if modifiers.contains(.alt) {
            return ESC + String(scalar)
        }
        return String(scalar)
    }

    // MARK: - CSI sequences for navigation/function keys

    private static func csiSequence(for keyCode: UIKeyboardHIDUsage, modifiers: KeyModifiers) -> String? {
        let mod = modifiers.xtermModifierCode

        // Arrow keys: ESC [ <mod> <letter>  if modified, ESC [ <letter> if not.
        if let letter = arrowLetter(for: keyCode) {
            return mod == 1 ? "\(CSI)\(letter)" : "\(CSI)1;\(mod)\(letter)"
        }

        // Home / End: ESC [ 1;<mod> H  /  ESC [ 1;<mod> F  (or ESC [ H / F unmodified)
        if keyCode == .keyboardHome {
            return mod == 1 ? "\(CSI)H" : "\(CSI)1;\(mod)H"
        }
        if keyCode == .keyboardEnd {
            return mod == 1 ? "\(CSI)F" : "\(CSI)1;\(mod)F"
        }

        // Page Up / Page Down: ESC [ 5~ / ESC [ 6~  (with mods: ESC [ 5;<mod>~)
        if keyCode == .keyboardPageUp {
            return mod == 1 ? "\(CSI)5~" : "\(CSI)5;\(mod)~"
        }
        if keyCode == .keyboardPageDown {
            return mod == 1 ? "\(CSI)6~" : "\(CSI)6;\(mod)~"
        }

        // Insert / Delete-forward.
        if keyCode == .keyboardInsert {
            return mod == 1 ? "\(CSI)2~" : "\(CSI)2;\(mod)~"
        }
        if keyCode == .keyboardDeleteForward {
            return mod == 1 ? "\(CSI)3~" : "\(CSI)3;\(mod)~"
        }

        // Function keys.
        if let fSeq = functionKeySequence(for: keyCode, modifierCode: mod) {
            return fSeq
        }

        return nil
    }

    private static func arrowLetter(for code: UIKeyboardHIDUsage) -> String? {
        switch code {
        case .keyboardUpArrow:    return "A"
        case .keyboardDownArrow:  return "B"
        case .keyboardRightArrow: return "C"
        case .keyboardLeftArrow:  return "D"
        default: return nil
        }
    }

    private static func functionKeySequence(for code: UIKeyboardHIDUsage, modifierCode: Int) -> String? {
        // SS3 prefix for F1-F4 when unmodified (xterm convention).
        let SS3 = "\u{1B}O"
        if modifierCode == 1 {
            switch code {
            case .keyboardF1:  return "\(SS3)P"
            case .keyboardF2:  return "\(SS3)Q"
            case .keyboardF3:  return "\(SS3)R"
            case .keyboardF4:  return "\(SS3)S"
            case .keyboardF5:  return "\(CSI)15~"
            case .keyboardF6:  return "\(CSI)17~"
            case .keyboardF7:  return "\(CSI)18~"
            case .keyboardF8:  return "\(CSI)19~"
            case .keyboardF9:  return "\(CSI)20~"
            case .keyboardF10: return "\(CSI)21~"
            case .keyboardF11: return "\(CSI)23~"
            case .keyboardF12: return "\(CSI)24~"
            default: return nil
            }
        } else {
            // With modifiers, all F-keys use CSI form.
            let n: Int
            switch code {
            case .keyboardF1:  n = 1
            case .keyboardF2:  n = 2
            case .keyboardF3:  n = 3
            case .keyboardF4:  n = 4
            case .keyboardF5:  n = 15
            case .keyboardF6:  n = 17
            case .keyboardF7:  n = 18
            case .keyboardF8:  n = 19
            case .keyboardF9:  n = 20
            case .keyboardF10: n = 21
            case .keyboardF11: n = 23
            case .keyboardF12: n = 24
            default: return nil
            }
            // F1-F4 use a different form when modified.
            if n <= 4 {
                let letter: String
                switch n {
                case 1: letter = "P"
                case 2: letter = "Q"
                case 3: letter = "R"
                case 4: letter = "S"
                default: return nil
                }
                return "\(CSI)1;\(modifierCode)\(letter)"
            }
            return "\(CSI)\(n);\(modifierCode)~"
        }
    }

    // MARK: - Ctrl-letter mapping

    /// Maps a character to its Ctrl-prefixed byte (Ctrl+A → 0x01, etc.).
    /// Supports letters (a-z, case insensitive), and a handful of standard
    /// control-symbol pairings: Ctrl+[ → ESC, Ctrl+] → GS, Ctrl+\ → FS,
    /// Ctrl+_ → US, Ctrl+@ → NUL, Ctrl+? → DEL.
    private static func controlByte(for scalar: UnicodeScalar) -> UInt8? {
        let v = scalar.value

        // a-z, A-Z → 0x01..0x1A
        if (0x41...0x5A).contains(v) { return UInt8(v - 0x40) }
        if (0x61...0x7A).contains(v) { return UInt8(v - 0x60) }

        // Specific punctuation:
        switch v {
        case 0x40: return 0x00 // Ctrl+@ → NUL
        case 0x5B: return 0x1B // Ctrl+[ → ESC
        case 0x5C: return 0x1C // Ctrl+\ → FS
        case 0x5D: return 0x1D // Ctrl+] → GS
        case 0x5E: return 0x1E // Ctrl+^ → RS
        case 0x5F: return 0x1F // Ctrl+_ → US
        case 0x3F: return 0x7F // Ctrl+? → DEL
        case 0x20: return 0x00 // Ctrl+Space → NUL (matches macOS Terminal)
        default:
            return nil
        }
    }
}
