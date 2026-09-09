import Foundation

/// Drives one `tmux -CC` connection: turns a byte stream into pane output and
/// structure, and turns keystrokes and resizes back into tmux commands.
///
/// This is the piece between `TmuxControl.Parser` (pure bytes to events) and any
/// UI. It owns no rendering and no SwiftUI — a caller hands it bytes and gets
/// callbacks — so the protocol can be driven from a test with no terminal, no
/// SSH, and no window.
///
/// Why control mode at all: today one SSH channel feeds one renderer, and
/// Shio's splits live only in the Mac's view tree, so a split made on the Mac
/// cannot exist on the phone. tmux panes are server-side, so they exist
/// everywhere by construction. Letting tmux own the layout is what makes it
/// actually follow you between devices, and it deletes Shio's parallel split
/// tree rather than maintaining two hierarchies that disagree.
///
@MainActor
final class TmuxControlSession {

    // MARK: what the caller sees

    /// A pane produced bytes. Route these to that pane's renderer.
    var onPaneOutput: ((_ paneID: String, _ bytes: [UInt8]) -> Void)?
    /// The set of panes changed (added, closed, or the active one moved).
    var onLayoutChanged: (() -> Void)?
    /// tmux is gone — the client detached or the server exited.
    var onExit: ((_ reason: String?) -> Void)?
    /// A command's response block, delivered whole. `error` mirrors `%error`.
    var onCommandResult: ((_ lines: [String], _ error: Bool) -> Void)?
    /// A pane's current screen, in response to `capturePane`. Attaching to a
    /// session that already exists sends NO screen content — tmux only forwards
    /// what happens next — so without this a phone joining the Mac's session
    /// stares at a blank terminal until something moves.
    /// `lines` is nil when the capture failed, which still has to be reported:
    /// a caller holding output back until the screen is restored would hold it
    /// forever otherwise.
    var onPaneRestore: ((_ paneID: String, _ lines: [String]?) -> Void)?
    /// tmux answered the attach and is ready for commands.
    var onStarted: (() -> Void)?
    /// A layout request came back unusable. There is no active pane, so nothing
    /// can be drawn or typed into until one arrives.
    var onLayoutUnavailable: (() -> Void)?

    /// Everything this session must send to the remote. Set by the transport.
    var send: ((String) -> Void)?

    // MARK: structure

    /// Windows currently in the session, in tmux's order.
    private(set) var windows: [Window] = []
    /// The active pane, or nil before the first layout arrives.
    private(set) var activePaneID: String?

    struct Window: Equatable, Identifiable {
        let id: String          // tmux window id, e.g. "@3"
        var name: String
        var paneIDs: [String]   // tmux pane ids, e.g. ["%7", "%8"]
    }

    // MARK: internals

    private var parser = TmuxControl.Parser()
    /// Lines of the block currently being collected between %begin and %end.
    private var blockLines: [String] = []
    private var inBlock = false

    /// What each outstanding command asked for. tmux answers commands strictly
    /// in order and echoes no identifier we can predict, so the reply is matched
    /// by position rather than by parsing what came back — the block for a
    /// `capture-pane` is arbitrary text and cannot be recognised by shape.
    private enum Reply {
        case layout
        case capture(paneID: String)
        case resize(cols: Int, rows: Int)
        case passthrough
    }
    private var pending: [Reply] = []
    /// Whether the reply stream has been synchronised. Until it has, blocks are
    /// discarded rather than matched.
    private var synced = false
    /// tmux before 3.2 spells the client size differently. Learned once, from a
    /// rejection, rather than by probing the version.
    private var legacyResizeSyntax = false
    /// Whether tmux has answered the handshake. A control channel that never
    /// syncs is not a control channel.
    var isSynced: Bool { synced }

    /// Opt-in while the transport earns trust. Lives here rather than on a
    /// view model so both targets can read it — the Mac's settings cannot see
    /// iOS-only types.
    static let enabledKey = "shio.terminal.controlMode"
    static var isEnabled: Bool {
        UserDefaults(suiteName: ShioModelContainer.appGroup)?.bool(forKey: enabledKey) ?? false
    }

    init() {}

    // MARK: driving it

    /// A string tmux will echo back verbatim, marking where our replies begin.
    static let readyMarker = "shio-control-ready"

    /// Synchronise with tmux, then report ready. Call once the channel is open.
    ///
    /// Replies are matched to commands by position, so the count of blocks that
    /// arrive before the first of ours has to be exactly right — and it is not
    /// knowable. The attach line chains tmux options onto `new-session`, and
    /// tmux answers EVERY command in that chain with its own empty block: the
    /// real line produces five, not one. Counting them means the option chain
    /// can never change without silently shifting every reply by one, which
    /// looks like a terminal that never draws and never accepts a keystroke.
    ///
    /// So instead of counting, ask tmux to say something only we would say, and
    /// throw away everything before it.
    func start() {
        send?("display-message -p \(Self.readyMarker)\n")
    }

    /// Feed bytes as they arrive. Safe to call with any chunking.
    func receive(_ bytes: [UInt8]) {
        for event in parser.feed(bytes) { handle(event) }
    }

    /// Keystrokes for a pane. tmux takes them as hex, which is the only form
    /// that survives arbitrary bytes — control characters, escape sequences and
    /// invalid UTF-8 all pass through unaltered, where a quoted string would
    /// need escaping rules that differ per shell.
    func sendKeys(_ bytes: [UInt8], toPane paneID: String) {
        guard !bytes.isEmpty else { return }
        // A paste arrives here as one payload. `String(format:)` per byte is
        // both slow and locale-aware, and one command line carrying the whole
        // paste is three bytes of tmux command per byte typed, which a large
        // paste turns into a single enormous line for tmux to parse.
        for chunk in stride(from: 0, to: bytes.count, by: Self.keyChunkBytes) {
            let slice = bytes[chunk..<min(chunk + Self.keyChunkBytes, bytes.count)]
            run("send-keys -t \(paneID) -H \(Self.hex(slice))", expecting: .passthrough)
        }
    }

    /// Bytes per `send-keys`. Each costs three characters of command line, so
    /// this keeps any one command well inside what tmux parses comfortably
    /// while still sending an ordinary keystroke as a single command.
    private static let keyChunkBytes = 1024

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    /// Space-separated lowercase hex, built over a nibble table.
    static func hex(_ bytes: ArraySlice<UInt8>) -> String {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count * 3)
        for byte in bytes {
            if !out.isEmpty { out.append(UInt8(ascii: " ")) }
            out.append(hexDigits[Int(byte >> 4)])
            out.append(hexDigits[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Send a command and remember what its reply is for.
    ///
    /// Nothing is sent before the handshake. Writes to a channel that is not
    /// open yet are silently dropped by SSHClient, and a dropped command whose
    /// tag stayed in the queue would shift every later reply onto the wrong
    /// request — the same permanent blank terminal the handshake exists to
    /// prevent, arriving by a different road.
    private func run(_ command: String, expecting reply: Reply) {
        guard synced else { return }
        pending.append(reply)
        send?(command + "\n")
    }

    /// Tell tmux how big this client's screen is. In control mode the client
    /// renders, so tmux has no idea unless it is told.
    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        if legacyResizeSyntax {
            run("refresh-client -C \(cols),\(rows)", expecting: .passthrough)
        } else {
            run("refresh-client -C \(cols)x\(rows)", expecting: .resize(cols: cols, rows: rows))
        }
    }

    /// Ask for the current window and pane layout. Used on attach, and after any
    /// structural notification, so the model never drifts from tmux's truth.
    func requestLayout() {
        // The window name goes LAST because it is the only free-form field. A
        // name with spaces, or an empty one, would otherwise move the fields
        // that identify the pane, and a listing that fails to parse means no
        // active pane and a terminal that never draws.
        run("list-panes -s -F '#{window_id} #{pane_id} #{pane_active} #{window_name}'",
            expecting: .layout)
    }

    /// Ask for a pane's visible screen so a newly attached client can draw what
    /// is already there. `-e` keeps colour and style, `-J` rejoins lines tmux
    /// wrapped, so what comes back is what the pane looks like rather than a
    /// plain-text approximation of it.
    func capturePane(_ paneID: String) {
        run("capture-pane -p -e -J -t \(paneID)", expecting: .capture(paneID: paneID))
    }

    // MARK: events

    private func handle(_ event: TmuxControl.Event) {
        switch event {
        case .output(let pane, let bytes):
            onPaneOutput?(pane, bytes)

        case .begin:
            inBlock = true
            blockLines = []

        case .blockLine(let line):
            if inBlock { blockLines.append(line) }

        case .end(_, _, _, let error):
            inBlock = false
            let lines = blockLines
            blockLines = []
            deliver(lines, error: error)

        // Anything structural invalidates the model. Rather than patching it
        // notification by notification (and drifting the first time tmux does
        // something unmodelled), re-ask. It is one cheap command.
        case .windowAdd, .windowClose, .windowRenamed,
             .windowPaneChanged, .layoutChange, .sessionWindowChanged,
             .unlinkedWindowAdd, .unlinkedWindowClose:
            requestLayout()

        case .exit(let reason):
            onExit?(reason)

        case .sessionChanged, .sessionRenamed, .sessionsChanged,
             .clientDetached, .clientSessionChanged, .paneModeChanged,
             .paused, .continued, .message, .configError, .unhandled:
            break
        }
    }

    /// Hand a finished block to whoever asked for it.
    private func deliver(_ lines: [String], error: Bool) {
        guard synced else {
            guard lines.contains(Self.readyMarker) else { return }
            synced = true
            // Anything queued before this point never reached tmux, so no reply
            // is coming for it. Starting the queue empty is what keeps replies
            // lined up with requests from here on.
            pending = []
            onStarted?()
            return
        }
        switch pending.isEmpty ? .passthrough : pending.removeFirst() {
        case .layout:
            guard !error, let parsed = Self.parseLayout(lines), parsed.activePaneID != nil else {
                onLayoutUnavailable?()
                return
            }
            windows = parsed.windows
            activePaneID = parsed.activePaneID
            onLayoutChanged?()

        case .capture(let paneID):
            onPaneRestore?(paneID, error ? nil : lines)

        case .resize(let cols, let rows):
            // Older tmux rejects the `WxH` form. Learn that from the rejection
            // and re-send, rather than leaving tmux believing this client is
            // some other shape and every TUI wrapping wrong for the session.
            guard error, !legacyResizeSyntax else { return }
            legacyResizeSyntax = true
            run("refresh-client -C \(cols),\(rows)", expecting: .passthrough)

        case .passthrough:
            onCommandResult?(lines, error)
        }
    }

    /// Parse `list-panes` rows into windows. Returns nil when the lines are not
    /// a layout listing, so a malformed or unexpected reply is ignored rather
    /// than half-applied.
    /// Fields are `#{window_id} #{pane_id} #{pane_active} #{window_name}`, the
    /// name last because it is the only one that can be empty or contain
    /// spaces. A row that does not parse is skipped rather than discarding the
    /// listing: losing one window is recoverable, losing the active pane is a
    /// terminal that never draws.
    static func parseLayout(_ lines: [String]) -> (windows: [Window], activePaneID: String?)? {
        var order: [String] = []
        var byID: [String: Window] = [:]
        var active: String?

        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 3,
                                   omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3,
                  parts[0].hasPrefix("@"),
                  parts[1].hasPrefix("%"),
                  let isActive = Int(parts[2])
            else { continue }

            let windowID = parts[0]
            let paneID = parts[1]
            let name = parts.count > 3 ? parts[3] : ""

            if byID[windowID] == nil {
                order.append(windowID)
                byID[windowID] = Window(id: windowID, name: name, paneIDs: [])
            }
            byID[windowID]?.paneIDs.append(paneID)
            if isActive == 1 { active = paneID }
        }

        guard !order.isEmpty else { return nil }
        return (order.compactMap { byID[$0] }, active)
    }
}
