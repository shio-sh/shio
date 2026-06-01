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
            // `keycode` is the RAW native macOS virtual keycode — libghostty
            // translates it to a logical key via the system keyboard layout
            // (the Carbon TIS APIs the macOS slice links). Passing a ghostty
            // GHOSTTY_KEY_* enum here instead is wrong: it breaks Enter,
            // Delete, arrows, and Ctrl-chords (text-producing keys still work
            // because they ride the `text` field).
            key.keycode = UInt32(event.keyCode)
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
