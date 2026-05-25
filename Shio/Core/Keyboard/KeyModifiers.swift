import UIKit

/// Modifier state used by the ANSI translator. We track Shift / Ctrl / Alt(Opt) / Cmd
/// separately because xterm semantics depend on the exact combination.
struct KeyModifiers: OptionSet, Sendable, Hashable {
    let rawValue: Int
    static let shift   = KeyModifiers(rawValue: 1 << 0)
    static let control = KeyModifiers(rawValue: 1 << 1)
    /// On Mac/iOS this is Option/Alt. With `macOptionIsMeta = true`, xterm.js
    /// treats it as Meta — so do we.
    static let alt     = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(uiKeyModifierFlags flags: UIKeyModifierFlags) {
        var s: KeyModifiers = []
        if flags.contains(.shift)     { s.insert(.shift) }
        if flags.contains(.control)   { s.insert(.control) }
        if flags.contains(.alternate) { s.insert(.alt) }
        if flags.contains(.command)   { s.insert(.command) }
        self = s
    }

    /// xterm escape-sequence modifier code per the xterm spec:
    /// 1=none, 2=Shift, 3=Alt, 4=Shift+Alt, 5=Ctrl, 6=Shift+Ctrl, 7=Alt+Ctrl, 8=Shift+Alt+Ctrl.
    /// (Cmd is intentionally not included — Cmd is a Mac chord, not an xterm modifier.)
    var xtermModifierCode: Int {
        var code = 1
        if contains(.shift)   { code += 1 }
        if contains(.alt)     { code += 2 }
        if contains(.control) { code += 4 }
        return code
    }
}
