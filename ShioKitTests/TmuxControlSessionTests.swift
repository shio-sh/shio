import Testing
import Foundation
@testable import Shio

/// The layer between the control-mode parser and any UI: bytes in, pane output
/// and structure out, keystrokes and resizes back.
///
/// It owns no rendering and no SSH, so all of it is testable without a terminal.
/// That is the point of building it before wiring anything: the protocol work
/// gets proven while a failure still says something useful, rather than showing
/// up as a blank terminal on a phone.
@MainActor
struct TmuxControlSessionTests {

    private func session() -> TmuxControlSession {
        let s = TmuxControlSession()
        s.send = { _ in }
        return s
    }

    // MARK: output routing

    @Test func routesPaneOutputToItsPane() {
        let s = session()
        var got: [(String, [UInt8])] = []
        s.onPaneOutput = { got.append(($0, $1)) }

        s.receive(Array("%output %7 hello\n%output %8 world\n".utf8))

        #expect(got.count == 2)
        #expect(got[0].0 == "%7")
        #expect(got[1].0 == "%8")
        #expect(got[1].1 == Array("world".utf8))
    }

    /// The whole reason payloads are bytes: a cut escape sequence or invalid
    /// UTF-8 has to reach the renderer untouched.
    @Test func preservesRawBytesThroughRouting() {
        let s = session()
        var bytes: [UInt8] = []
        s.onPaneOutput = { _, b in bytes = b }
        s.receive(Array("%output %1 \\033[31m\\377\n".utf8))
        #expect(bytes == [0x1B] + Array("[31m".utf8) + [0xFF])
    }

    // MARK: input

    /// Keys go as hex because it is the only encoding that survives arbitrary
    /// bytes without per-shell quoting rules.
    @Test func sendsKeystrokesAsHexToTheRightPane() {
        let s = session()
        var sent: [String] = []
        s.send = { sent.append($0) }

        s.sendKeys(Array("ls".utf8), toPane: "%3")

        #expect(sent.count == 1)
        #expect(sent[0].contains("send-keys -t %3 -H"))
        #expect(sent[0].contains("6c 73"))          // l s
        #expect(sent[0].hasSuffix("\n"))
    }

    @Test func encodesControlBytesThatWouldNotSurviveQuoting() {
        let s = session()
        var sent = ""
        s.send = { sent = $0 }
        s.sendKeys([0x03, 0x1B, 0x0D], toPane: "%1")   // ctrl-C, ESC, CR
        #expect(sent.contains("03 1b 0d"))
    }

    @Test func ignoresEmptyKeystrokes() {
        let s = session()
        var sent = 0
        s.send = { _ in sent += 1 }
        s.sendKeys([], toPane: "%1")
        #expect(sent == 0)
    }

    /// In control mode the client renders, so tmux only knows the size it's told.
    @Test func reportsClientSize() {
        let s = session()
        var sent = ""
        s.send = { sent = $0 }
        s.resize(cols: 120, rows: 40)
        #expect(sent.contains("refresh-client -C 120x40"))
    }

    @Test func ignoresNonsenseSizes() {
        let s = session()
        var sent = 0
        s.send = { _ in sent += 1 }
        s.resize(cols: 0, rows: 40)
        s.resize(cols: 80, rows: -1)
        #expect(sent == 0)
    }

    // MARK: structure

    @Test func buildsWindowsAndPanesFromALayoutListing() {
        let s = session()
        var layoutChanges = 0
        s.onLayoutChanged = { layoutChanges += 1 }

        s.receive(Array("""
        %begin 1 1 1
        @1 editor %1 0
        @1 editor %2 1
        @2 logs %3 0
        %end 1 1 1

        """.utf8))

        #expect(layoutChanges == 1)
        #expect(s.windows.count == 2)
        #expect(s.windows[0] == TmuxControlSession.Window(id: "@1", name: "editor",
                                                          paneIDs: ["%1", "%2"]))
        #expect(s.windows[1].paneIDs == ["%3"])
        #expect(s.activePaneID == "%2")
    }

    @Test func keepsWindowNamesContainingSpaces() {
        let parsed = TmuxControlSession.parseLayout(["@4 my long name %9 1"])
        #expect(parsed?.windows.first?.name == "my long name")
        #expect(parsed?.activePaneID == "%9")
    }

    /// A user's own command comes back through the same %begin/%end door, so
    /// anything that isn't shaped like a layout must not be mistaken for one.
    @Test func doesNotMistakeOrdinaryCommandOutputForLayout() {
        let s = session()
        var results: [[String]] = []
        s.onCommandResult = { lines, _ in results.append(lines) }

        s.receive(Array("%begin 1 2 1\ntotal 24\ndrwxr-xr-x  5 amrith\n%end 1 2 1\n".utf8))

        #expect(s.windows.isEmpty)
        #expect(results.count == 1)
        #expect(results[0].first == "total 24")
    }

    @Test func surfacesCommandErrors() {
        let s = session()
        var sawError = false
        s.onCommandResult = { _, error in sawError = error }
        s.receive(Array("%begin 1 3 1\nno such window\n%error 1 3 1\n".utf8))
        #expect(sawError)
    }

    /// Rather than patching the model per notification (and drifting the first
    /// time tmux does something unmodelled), structure changes re-ask.
    @Test func refetchesLayoutWhenStructureChanges() {
        let s = session()
        var asked = 0
        s.send = { if $0.hasPrefix("list-panes") { asked += 1 } }

        s.receive(Array("%window-add @5\n".utf8))
        s.receive(Array("%window-close @5\n".utf8))
        s.receive(Array("%window-pane-changed @1 %2\n".utf8))
        s.receive(Array("%layout-change @1 abc,80x24,0,0 abc,80x24,0,0 *\n".utf8))

        #expect(asked == 4)
    }

    @Test func reportsExit() {
        let s = session()
        var reason: String??
        s.onExit = { reason = $0 }
        s.receive(Array("%exit server exited\n".utf8))
        #expect(reason == "server exited")
    }

    // MARK: the attach command

    /// Control mode goes through the same non-interactive exec channel as the
    /// plain bootstrap, so it needs the same PATH treatment. Without it tmux is
    /// invisible and the terminal is silently empty — the exact failure that
    /// stopped the phone joining the Mac's session.
    @Test func attachCommandCanFindTmuxOnABarePath() {
        let cmd = TmuxControlSession.attachCommand(session: "shio-Infer")
        #expect(cmd.hasPrefix("PATH="))
        for dir in TmuxResume.commonBinDirs { #expect(cmd.contains(dir)) }
        #expect(cmd.contains("-CC new-session -A -s shio-Infer"))
        #expect(cmd.contains("exec \"${SHELL:-/bin/sh}\" -l"))
    }
}

/// The control session driven against a REAL `tmux -C` process.
///
/// The fixture tests above prove the logic; this proves the contract with tmux
/// itself. If a future tmux changes how `list-panes` formats, or stops
/// accepting hex `send-keys`, this fails here rather than as an empty terminal
/// on somebody's phone.
/// File-scope so the `.enabled(if:)` trait can read it: trait closures are
/// Sendable and cannot touch a main-actor-isolated static.
private let liveTmuxPath: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

@MainActor
struct TmuxControlSessionLiveTests {

    @Test(.enabled(if: liveTmuxPath != nil))
    func discoversLayoutAndRoundTripsKeystrokesThroughRealTmux() async throws {
        guard let tmux = liveTmuxPath else {
            Issue.record("tmux was found during discovery but not at run time")
            return
        }
        let name = "shio-cs-\(UUID().uuidString.prefix(8))"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmux)
        proc.arguments = ["-C", "new-session", "-s", name]
        let stdin = Pipe(), stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = Pipe()
        try proc.run()
        defer {
            if proc.isRunning { proc.terminate() }
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: tmux)
            kill.arguments = ["kill-session", "-t", name]
            kill.standardError = Pipe()
            try? kill.run(); kill.waitUntilExit()
        }

        let session = TmuxControlSession()
        session.send = { stdin.fileHandleForWriting.write(Data($0.utf8)) }

        // Pump tmux's output into the session on a background reader.
        let collected = OutputBox()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collected.append([UInt8](data))
        }

        // Give tmux a moment to come up, then ask what it has.
        try await Task.sleep(for: .milliseconds(700))
        session.receive(collected.drain())
        session.requestLayout()
        try await Task.sleep(for: .milliseconds(700))
        session.receive(collected.drain())

        #expect(!session.windows.isEmpty, "real tmux should report at least one window")
        #expect(session.activePaneID != nil, "an active pane must be identified")
        let paneCount = session.windows.reduce(0) { $0 + $1.paneIDs.count }
        #expect(paneCount >= 1)

        // Type into the active pane and confirm tmux echoes it back as output
        // for that same pane — the full round trip through hex send-keys.
        guard let pane = session.activePaneID else { return }
        var sawOutputForPane = false
        session.onPaneOutput = { id, _ in if id == pane { sawOutputForPane = true } }
        session.sendKeys(Array("echo shio-control-ok\n".utf8), toPane: pane)
        try await Task.sleep(for: .milliseconds(900))
        session.receive(collected.drain())

        #expect(sawOutputForPane, "keystrokes should produce output on the pane they were sent to")

        stdout.fileHandleForReading.readabilityHandler = nil
    }
}

/// Thread-safe scratch buffer for the background reader.
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8] = []
    func append(_ new: [UInt8]) { lock.lock(); bytes += new; lock.unlock() }
    func drain() -> [UInt8] {
        lock.lock(); defer { bytes = []; lock.unlock() }
        return bytes
    }
}
