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
    var onPaneRestore: ((_ paneID: String, _ lines: [String]) -> Void)?
    /// tmux answered the attach and is ready for commands.
    var onStarted: (() -> Void)?

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
        case passthrough
    }
    private var pending: [Reply] = []
    /// tmux answers the attach itself with one empty block before it has been
    /// asked anything. Everything is sent after that, so it is also the signal
    /// that ordered matching can start.
    private var started = false

    /// Opt-in while the transport earns trust. Lives here rather than on a
    /// view model so both targets can read it — the Mac's settings cannot see
    /// iOS-only types.
    static let enabledKey = "shio.terminal.controlMode"
    static var isEnabled: Bool {
        UserDefaults(suiteName: ShioModelContainer.appGroup)?.bool(forKey: enabledKey) ?? false
    }

    init() {}

    // MARK: driving it

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
        let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        run("send-keys -t \(paneID) -H \(hex)", expecting: .passthrough)
    }

    /// Send a command and remember what its reply is for.
    private func run(_ command: String, expecting reply: Reply) {
        pending.append(reply)
        send?(command + "\n")
    }

    /// Tell tmux how big this client's screen is. In control mode the client
    /// renders, so tmux has no idea unless it is told.
    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        run("refresh-client -C \(cols)x\(rows)", expecting: .passthrough)
    }

    /// Ask for the current window and pane layout. Used on attach, and after any
    /// structural notification, so the model never drifts from tmux's truth.
    func requestLayout() {
        run("list-panes -s -F '#{window_id} #{window_name} #{pane_id} #{pane_active}'",
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
        guard started else {
            started = true
            onStarted?()
            return
        }
        switch pending.isEmpty ? .passthrough : pending.removeFirst() {
        case .layout:
            guard !error, let parsed = Self.parseLayout(lines) else { return }
            windows = parsed.windows
            activePaneID = parsed.activePaneID
            onLayoutChanged?()
        case .capture(let paneID):
            guard !error else { return }
            onPaneRestore?(paneID, lines)
        case .passthrough:
            onCommandResult?(lines, error)
        }
    }

    /// Parse `list-panes` rows into windows. Returns nil when the lines are not
    /// a layout listing, so a malformed or unexpected reply is ignored rather
    /// than half-applied.
    static func parseLayout(_ lines: [String]) -> (windows: [Window], activePaneID: String?)? {
        var order: [String] = []
        var byID: [String: Window] = [:]
        var active: String?
        var sawAny = false

        for line in lines {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 4,
                  parts[0].hasPrefix("@"),
                  parts[parts.count - 2].hasPrefix("%"),
                  let isActive = Int(parts[parts.count - 1])
            else { return nil }   // not a layout listing

            sawAny = true
            let windowID = parts[0]
            let paneID = parts[parts.count - 2]
            // Window names can contain spaces; everything between is the name.
            let name = parts[1..<(parts.count - 2)].joined(separator: " ")

            if byID[windowID] == nil {
                order.append(windowID)
                byID[windowID] = Window(id: windowID, name: name, paneIDs: [])
            }
            byID[windowID]?.paneIDs.append(paneID)
            if isActive == 1 { active = paneID }
        }

        guard sawAny else { return nil }
        return (order.compactMap { byID[$0] }, active)
    }
}
