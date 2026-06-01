import AppKit
import GhosttyKit

/// Native macOS host for a libghostty terminal surface, backed by a Metal
/// layer. Unlike the iOS surface (which uses the EXTERNAL IO backend and is
/// fed SSH bytes), this uses the DEFAULT backend so libghostty forks/execs a
/// real local shell and owns the PTY — a true local terminal.
///
/// M2 scaffold: local shell, rendering, keyboard, scroll, focus, resize.
/// Invisible-tmux wrapping (for continuity), tabs/splits, and SSH sessions
/// layer on in later milestones. Visual render + input feel need on-device
/// verification (can't be validated by a headless build).
final class GhosttyMacSurface: NSView {

    nonisolated(unsafe) private var surface: ghostty_surface_t?
    private var fontSize: Float = 13

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect.isEmpty ? NSRect(x: 0, y: 0, width: 800, height: 500) : frameRect)
        wantsLayer = true
        commonInit()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true; commonInit() }

    deinit {
        if let surface { ghostty_surface_free(surface) }
    }

    /// Metal-backed layer (libghostty renders into a sublayer it owns).
    override func makeBackingLayer() -> CALayer { CAMetalLayer() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    private func commonInit() {
        LibGhosttyBridge.shared.ensureInitialized()
        guard let app = LibGhosttyBridge.shared.app else { return }

        var cfg = ghostty_surface_config_new()
        cfg.font_size = fontSize
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque())
        )
        cfg.scale_factor = Double(window?.backingScaleFactor ?? 2.0)
        // DEFAULT backend → libghostty forks/execs a local shell and owns the
        // PTY. command == nil runs the user's login shell. (Invisible-tmux
        // wrapping for cross-device continuity lands next.)
        cfg.io_backend = UInt8(GHOSTTY_IO_BACKEND_DEFAULT.rawValue)

        guard let surface = ghostty_surface_new(app, &cfg) else { return }
        self.surface = surface
    }

    // MARK: Layout / sizing

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSurfaceSize()
    }

    override func layout() {
        super.layout()
        if let sublayers = layer?.sublayers {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for sub in sublayers { sub.frame = bounds }
            CATransaction.commit()
        }
        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        guard let surface else { return }
        let scale = window?.backingScaleFactor ?? 2.0
        ghostty_surface_set_content_scale(surface, scale, scale)
        ghostty_surface_set_size(surface, UInt32(bounds.width * scale), UInt32(bounds.height * scale))
    }

    // MARK: Focus

    override func becomeFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, true) }
        return super.becomeFirstResponder()
    }
    override func resignFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, false) }
        return super.resignFirstResponder()
    }

    // MARK: Input

    override func keyDown(with event: NSEvent) {
        sendKey(event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS)
    }
    override func keyUp(with event: NSEvent) {
        sendKey(event, action: GHOSTTY_ACTION_RELEASE)
    }

    private func sendKey(_ event: NSEvent, action: ghostty_input_action_e) {
        guard let surface else { return }
        let chars = event.characters ?? ""
        let unshifted = event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0
        let flags = event.modifierFlags

        // Only forward `text` for genuine printable input. Control characters
        // (backspace 0x7F, return, tab…), the private-use codepoints AppKit
        // uses for function keys / arrows (0xF700–0xF8FF), and Ctrl/Cmd chords
        // must NOT be sent as text — ghostty would insert the raw character
        // (e.g. a literal DEL, breaking backspace). Those are encoded from
        // keycode + mods instead. Printable letters/digits/symbols still flow
        // through `text` so non-US layouts and symbol keys work.
        let nonText = chars.unicodeScalars.contains {
            $0.value < 0x20 || $0.value == 0x7F || (0xF700...0xF8FF).contains($0.value)
        }
        let suppressText = nonText || flags.contains(.control) || flags.contains(.command)
        let textToSend = suppressText ? "" : chars

        textToSend.withCString { cText in
            var key = ghostty_input_key_s()
            key.action = action
            key.mods = Self.mods(from: flags)
            key.consumed_mods = GHOSTTY_MODS_NONE
            key.keycode = UInt32(Self.ghosttyKey(from: event.keyCode).rawValue)
            key.text = cText
            key.unshifted_codepoint = unshifted
            key.composing = false
            _ = ghostty_surface_key(surface, key)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        let precision: Int32 = event.hasPreciseScrollingDeltas ? 1 : 0
        ghostty_surface_mouse_scroll(surface, Double(event.scrollingDeltaX), Double(event.scrollingDeltaY), precision)
    }

    // MARK: NSEvent → ghostty translation

    private static func mods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var m: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift)   { m |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { m |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option)  { m |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { m |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock){ m |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(m)
    }

    /// Map the ANSI macOS virtual key codes to ghostty key constants. Covers
    /// letters, digits, and the essential control keys; unmapped keys fall
    /// back to UNIDENTIFIED and still type via the `text` field. (A complete
    /// table — F-keys, keypad, punctuation — is a follow-up refinement.)
    private static func ghosttyKey(from code: UInt16) -> ghostty_input_key_e {
        switch code {
        case 0: return GHOSTTY_KEY_A;  case 1: return GHOSTTY_KEY_S
        case 2: return GHOSTTY_KEY_D;  case 3: return GHOSTTY_KEY_F
        case 4: return GHOSTTY_KEY_H;  case 5: return GHOSTTY_KEY_G
        case 6: return GHOSTTY_KEY_Z;  case 7: return GHOSTTY_KEY_X
        case 8: return GHOSTTY_KEY_C;  case 9: return GHOSTTY_KEY_V
        case 11: return GHOSTTY_KEY_B; case 12: return GHOSTTY_KEY_Q
        case 13: return GHOSTTY_KEY_W; case 14: return GHOSTTY_KEY_E
        case 15: return GHOSTTY_KEY_R; case 16: return GHOSTTY_KEY_Y
        case 17: return GHOSTTY_KEY_T; case 31: return GHOSTTY_KEY_O
        case 32: return GHOSTTY_KEY_U; case 34: return GHOSTTY_KEY_I
        case 35: return GHOSTTY_KEY_P; case 37: return GHOSTTY_KEY_L
        case 38: return GHOSTTY_KEY_J; case 40: return GHOSTTY_KEY_K
        case 45: return GHOSTTY_KEY_N; case 46: return GHOSTTY_KEY_M
        case 18: return GHOSTTY_KEY_DIGIT_1; case 19: return GHOSTTY_KEY_DIGIT_2
        case 20: return GHOSTTY_KEY_DIGIT_3; case 21: return GHOSTTY_KEY_DIGIT_4
        case 22: return GHOSTTY_KEY_DIGIT_6; case 23: return GHOSTTY_KEY_DIGIT_5
        case 25: return GHOSTTY_KEY_DIGIT_9; case 26: return GHOSTTY_KEY_DIGIT_7
        case 28: return GHOSTTY_KEY_DIGIT_8; case 29: return GHOSTTY_KEY_DIGIT_0
        case 36: return GHOSTTY_KEY_ENTER
        case 48: return GHOSTTY_KEY_TAB
        case 49: return GHOSTTY_KEY_SPACE
        case 51: return GHOSTTY_KEY_BACKSPACE
        case 53: return GHOSTTY_KEY_ESCAPE
        case 117: return GHOSTTY_KEY_DELETE
        case 123: return GHOSTTY_KEY_ARROW_LEFT
        case 124: return GHOSTTY_KEY_ARROW_RIGHT
        case 125: return GHOSTTY_KEY_ARROW_DOWN
        case 126: return GHOSTTY_KEY_ARROW_UP
        default:  return GHOSTTY_KEY_UNIDENTIFIED
        }
    }
}

// MARK: - SwiftUI host

import SwiftUI

/// Embeds a `GhosttyMacSurface` in SwiftUI and makes it first responder so
/// keystrokes flow to the terminal.
struct GhosttyMacTerminal: NSViewRepresentable {
    func makeNSView(context: Context) -> GhosttyMacSurface {
        let view = GhosttyMacSurface(frame: .zero)
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }
    func updateNSView(_ nsView: GhosttyMacSurface, context: Context) {}
}
