import UIKit
import SwiftUI
import GhosttyKit

/// Hosts a libghostty terminal surface configured with the External IO
/// backend. Output bytes are pushed in via `writeBytes(...)`, and bytes
/// the terminal wants to send back are delivered through `onOutput`.
final class LibGhosttySurfaceView: UIView {

    /// Called when the terminal wants to send bytes back to the embedder
    /// (user input, OSC responses, mouse events, etc).
    var onOutput: ((Data) -> Void)?

    /// Called when the terminal grid is resized. Embedders typically use
    /// this to send a window-change request over SSH.
    var onResize: ((_ columns: UInt16, _ rows: UInt16) -> Void)?

    /// Mobile-default font size. Also acts as the **minimum** — users
    /// can't pinch any smaller. Picked so the default state shows the
    /// most content while still being readable on iPhone.
    static let mobileDefaultFontSize: Int = 9
    /// Cap on the other end — pinching in past 24pt isn't useful, and
    /// libghostty's font rendering gets jaggy at extreme sizes.
    static let maxFontSize: Int = 24

    /// Live tracking of the surface's current font size. Initialized to
    /// the mobile default; bumped/dropped by `applyPinchDelta`. We track
    /// it Swift-side because libghostty doesn't expose a getter and we
    /// want to refuse pinch-out at the floor without a round-trip.
    private var currentFontSize: Int = mobileDefaultFontSize
    /// Where the live pinch wants the font size to land. The actual libghostty
    /// change walks toward it one step per runloop (see `applyPinchDelta`).
    private var targetFontSize: Int = mobileDefaultFontSize
    private var fontApplyScheduled = false

    nonisolated(unsafe) private var surface: ghostty_surface_t?

    // C-callable static trampolines and a stable opaque userdata pointer.
    // The static functions look up `Unmanaged<LibGhosttySurfaceView>` and
    // forward to the instance closures.
    nonisolated(unsafe) private var userdataRetained: Unmanaged<LibGhosttySurfaceView>?

    override class var layerClass: AnyClass { CAMetalLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame.isEmpty ? CGRect(x: 0, y: 0, width: 800, height: 600) : frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    nonisolated(unsafe) private var didShutdown = false

    /// Free the libghostty surface and release the `passRetained(self)` +1 NOW.
    /// MUST be called when the session/tab closes: that +1 keeps the refcount
    /// ≥ 1, so `deinit` can never fire on its own — without this every surface
    /// (and its CAMetalLayer) leaks for the process lifetime. Idempotent.
    func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        if let s = surface { ghostty_surface_free(s); surface = nil }
        userdataRetained?.release()
        userdataRetained = nil
    }

    deinit {
        // Fallback if `shutdown()` wasn't called (no-ops if it was). Note the
        // +1 means deinit normally only runs *after* shutdown() released it.
        if let s = surface { ghostty_surface_free(s) }
        userdataRetained?.release()
    }

    private func commonInit() {
        LibGhosttyBridge.shared.ensureInitialized()
        guard let app = LibGhosttyBridge.shared.app else {
            return
        }

        // Retain self once for the duration of the surface's lifetime so
        // the C trampolines can recover the instance.
        let retained = Unmanaged.passRetained(self)
        userdataRetained = retained
        let userdata = retained.toOpaque()

        var cfg = ghostty_surface_config_new()
        cfg.userdata = userdata
        // Mobile-default font size = floor of the zoom range. Picked so
        // an iPhone Pro fits ~65 columns × ~50 rows in portrait, which
        // is wide enough for Claude Code's chat layout, htop, neovim
        // status lines, etc. Users can pinch IN to enlarge for
        // readability; pinch OUT is capped here (see applyPinchDelta).
        cfg.font_size = Float(LibGhosttySurfaceView.mobileDefaultFontSize)
        cfg.platform_tag = GHOSTTY_PLATFORM_IOS
        cfg.platform = ghostty_platform_u(
            ios: ghostty_platform_ios_s(uiview: Unmanaged.passUnretained(self).toOpaque())
        )
        // Use the view's content scale factor (resolved against the trait
        // hierarchy on iOS 26+). It gets refined in `updateSurfaceSize`
        // once we're attached to a window.
        cfg.scale_factor = Double(self.contentScaleFactor)
        cfg.io_backend = UInt8(GHOSTTY_IO_BACKEND_EXTERNAL.rawValue)
        cfg.io_userdata = userdata
        cfg.io_write_callback = { userdata, ptr, len in
            guard let userdata, let ptr, len > 0 else { return }
            let view = Unmanaged<LibGhosttySurfaceView>
                .fromOpaque(userdata).takeUnretainedValue()
            let data = Data(bytes: ptr, count: len)
            DispatchQueue.main.async {
                view.onOutput?(data)
            }
        }
        cfg.io_resize_callback = { userdata, cols, rows, _, _ in
            guard let userdata else { return }
            let view = Unmanaged<LibGhosttySurfaceView>
                .fromOpaque(userdata).takeUnretainedValue()
            let columns = cols
            let r = rows
            DispatchQueue.main.async {
                view.onResize?(columns, r)
            }
        }

        guard let surface = ghostty_surface_new(app, &cfg) else { return }
        self.surface = surface
    }

    /// Push raw bytes (output from a remote PTY, SSH channel, etc) into
    /// the terminal display.
    func writeBytes(_ data: Data) {
        guard let surface = self.surface else { return }
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Void in
            guard let base = buf.baseAddress else { return }
            ghostty_surface_write_bytes(
                surface,
                base.assumingMemoryBound(to: UInt8.self),
                UInt(buf.count)
            )
        }
    }

    /// Send a UTF-8 string as if the user typed it. Goes back out the
    /// io_write_callback path (i.e., to SSH).
    func sendText(_ text: String) {
        guard let surface = self.surface else { return }
        text.withCString { cstr in
            let len = strlen(cstr)
            ghostty_surface_text(surface, cstr, UInt(len))
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSurfaceSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // libghostty's Metal renderer adds an IOSurfaceLayer as a sublayer
        // of self.layer. UIKit doesn't auto-resize sublayers when bounds
        // change, so we sync them here.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if let sublayers = self.layer.sublayers {
            for sublayer in sublayers {
                sublayer.frame = self.bounds
            }
        }

        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        guard let surface = self.surface else { return }
        let scale = self.contentScaleFactor
        ghostty_surface_set_content_scale(surface, scale, scale)
        ghostty_surface_set_size(
            surface,
            UInt32(self.bounds.width * scale),
            UInt32(self.bounds.height * scale)
        )
    }

    func setFocus(_ focused: Bool) {
        guard let surface = self.surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    /// Scroll the terminal's viewport through libghostty's *own*
    /// scrollback buffer (the one the renderer maintains), NOT a mouse
    /// wheel event passed through to the running program. This is the
    /// "scroll like you're reading a chat / web page" gesture — vim,
    /// tmux, and the shell never see it.
    ///
    /// `lines` is in terminal cell rows. Positive = scroll DOWN toward
    /// the live tail; negative = scroll UP into older history. Sub-line
    /// fractional deltas are accumulated by the caller (`TerminalContainerView`).
    func scrollLines(_ lines: Int) {
        guard let surface = self.surface, lines != 0 else { return }
        // `scroll_lines:N` is the real ghostty action — `scroll_page_lines`
        // doesn't exist, so the binding silently no-ops. Positive scrolls
        // down toward the live tail, negative scrolls up into history.
        let arg = "scroll_lines:\(lines)"
        arg.withCString { cstr in
            _ = ghostty_surface_binding_action(surface, cstr, UInt(strlen(cstr)))
        }
    }

    /// True while a full-screen TUI (vim, htop, claude code, tmux, less,
    /// etc.) owns the buffer. Terminal scrollback is suspended in that
    /// mode, so callers may want to send mouse-scroll events that the
    /// running program (or tmux, with mouse mode on) can interpret as
    /// scrolling its own buffer.
    var isAlternateScreenActive: Bool {
        guard let surface = self.surface else { return false }
        return ghostty_surface_alt_screen_active(surface)
    }

    /// Send a mouse-wheel scroll event to the surface.
    ///
    /// `deltaY` is in logical points (positive = wheel-up = older
    /// content into view; negative = wheel-down = toward live tail).
    /// Libghostty forwards this:
    ///   - To the running app if it has mouse reporting enabled
    ///     (tmux with `set mouse on`, Claude Code, vim with `set mouse=a`,
    ///     htop, etc.) — the app then handles "scroll" however it sees fit.
    ///   - If no app has mouse reporting, libghostty scrolls its own
    ///     scrollback buffer.
    /// The `precision` flag treats `deltaY` as a pixel-level delta from
    /// a touch trackpad rather than discrete wheel ticks.
    func sendMouseScroll(deltaY: CGFloat) {
        guard let surface = self.surface else { return }
        let precisionFlag: Int32 = 1
        ghostty_surface_mouse_scroll(surface, 0, Double(deltaY), precisionFlag)
    }

    // MARK: Pinch-to-zoom

    /// Apply a pinch-driven font size delta. Each ~15% scale crossing
    /// triggers a +1 or -1 pt step via libghostty's binding actions.
    /// `accumulator` should be tracked across the gesture by the caller
    /// (the container view) and reset on `.began`.
    ///
    /// Bounds:
    ///   - Pinch IN (enlarge): capped at `maxFontSize`. Past that we
    ///     swallow the gesture so pinching at the cap doesn't feel like
    ///     it's "doing nothing" mid-buffer — once we hit the cap the
    ///     accumulator stops growing.
    ///   - Pinch OUT (shrink): capped at `mobileDefaultFontSize`, the
    ///     mobile baseline. Users can't zoom below the default state.
    func applyPinchDelta(_ accumulator: inout CGFloat) {
        // Translate the live accumulator into a TARGET font size only — never
        // touch libghostty here. Rebuilding the font grid + Metal glyph atlas
        // synchronously inside the gesture callback (and the `while` could do
        // it several times per frame) races the in-flight renderer and
        // crashes. The change is coalesced onto the next runloop instead.
        while accumulator >= 1.15 {
            guard targetFontSize < Self.maxFontSize else {
                accumulator = 1.0   // clamp so we don't store overflow
                break
            }
            targetFontSize += 1
            accumulator /= 1.15
        }
        while accumulator <= 1.0 / 1.15 {
            guard targetFontSize > Self.mobileDefaultFontSize else {
                accumulator = 1.0
                break
            }
            targetFontSize -= 1
            accumulator *= 1.15
        }
        scheduleFontApply()
    }

    /// Coalesce font-size changes off the gesture stack: at most one libghostty
    /// rebuild per runloop, walking `currentFontSize` toward `targetFontSize`.
    private func scheduleFontApply() {
        guard !fontApplyScheduled, currentFontSize != targetFontSize else { return }
        fontApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fontApplyScheduled = false
            self.applyFontStep()
        }
    }

    private func applyFontStep() {
        guard let surface = self.surface, currentFontSize != targetFontSize else { return }
        let up = targetFontSize > currentFontSize
        let action = up ? "increase_font_size:1" : "decrease_font_size:1"
        action.withCString { cstr in
            _ = ghostty_surface_binding_action(surface, cstr, UInt(strlen(cstr)))
        }
        currentFontSize += up ? 1 : -1
        // More to go? Take the next step on a later runloop, so two rebuilds
        // never land in the same frame.
        if currentFontSize != targetFontSize { scheduleFontApply() }
    }
}

/// SwiftUI wrapper that exposes the libghostty terminal surface and
/// surfaces the I/O hooks via a coordinator.
struct LibGhosttyTerminal: UIViewRepresentable {
    /// Closure invoked once with the underlying view so the parent can
    /// retain a reference for byte injection / sending text.
    var attach: (LibGhosttySurfaceView) -> Void

    func makeUIView(context: Context) -> LibGhosttySurfaceView {
        let v = LibGhosttySurfaceView(frame: .zero)
        attach(v)
        return v
    }

    func updateUIView(_ uiView: LibGhosttySurfaceView, context: Context) {}
}
