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
/// Not wired into the app yet. Deliberately.
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

    init() {}

    // MARK: driving it

    /// The command that starts control mode. Goes through the same exec channel
    /// as the plain bootstrap, so it needs the same PATH treatment — a
    /// non-interactive shell cannot see Homebrew's tmux without it.
    static func attachCommand(session: String) -> String {
        "PATH=\"$PATH:\(TmuxResume.commonBinDirs.joined(separator: ":"))\"; "
        + "command -v tmux >/dev/null 2>&1 && exec tmux -CC new-session -A -s \(session)"
        + " || exec \"${SHELL:-/bin/sh}\" -l"
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
        let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        send?("send-keys -t \(paneID) -H \(hex)\n")
    }

    /// Tell tmux how big this client's screen is. In control mode the client
    /// renders, so tmux has no idea unless it is told.
    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        send?("refresh-client -C \(cols)x\(rows)\n")
    }

    /// Ask for the current window and pane layout. Used on attach, and after any
    /// structural notification, so the model never drifts from tmux's truth.
    func requestLayout() {
        send?("list-panes -s -F '#{window_id} #{window_name} #{pane_id} #{pane_active}'\n")
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
            // A layout listing and a user command come back through the same
            // door, so the shape decides: only rows that parse as panes are
            // treated as layout.
            if !error, let parsed = Self.parseLayout(lines) {
                windows = parsed.windows
                activePaneID = parsed.activePaneID
                onLayoutChanged?()
            } else {
                onCommandResult?(lines, error)
            }

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

    /// Parse `list-panes` rows into windows. Returns nil when the lines are not
    /// a layout listing, which is how a normal command's output is told apart
    /// from one of ours.
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
