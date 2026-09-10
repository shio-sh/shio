import Testing
import Foundation
@testable import Shio

/// Tests for the `tmux -CC` control-mode parser.
///
/// The transcript in `realSessionTranscript` is not invented: it was captured
/// from `tmux -C new-session` on this machine, so the shapes here are the ones
/// tmux actually emits rather than the ones the man page implies.
struct TmuxControlProtocolTests {

    private func parse(_ s: String) -> [TmuxControl.Event] {
        var p = TmuxControl.Parser()
        return p.feed(s)
    }

    // MARK: notifications

    @Test func parsesBlockDelimitersAndContent() {
        let events = parse("""
        %begin 1363006971 2 1
        0: ksh* (1 panes) [80x24] [layout b25f,80x24,0,0,2] @2 (active)
        %end 1363006971 2 1

        """)
        #expect(events.first == .begin(time: 1363006971, number: 2, flags: 1))
        #expect(events.contains(.blockLine("0: ksh* (1 panes) [80x24] [layout b25f,80x24,0,0,2] @2 (active)")))
        #expect(events.last == .end(time: 1363006971, number: 2, flags: 1, error: false))
    }

    @Test func distinguishesErrorBlocksFromSuccessfulOnes() {
        let events = parse("%begin 1 2 0\nno such window\n%error 1 2 0\n")
        #expect(events.last == .end(time: 1, number: 2, flags: 0, error: true))
    }

    /// Everything between %begin and its own %end is content, including lines
    /// that start with '%'. `capture-pane` returns whatever is on somebody's
    /// screen, and screens are full of '%': pane ids, zsh prompts, percentages.
    @Test func blockContentIsNotMistakenForNotifications() {
        let events = parse("%begin 1 2 0\n%not-a-real-verb payload\n%end 1 2 0\n")
        #expect(events.contains(.blockLine("%not-a-real-verb payload")))
        #expect(!events.contains(.unhandled("%not-a-real-verb payload")))
    }

    /// A captured screen containing the literal text of a block terminator must
    /// not close the block. Doing so delivers a truncated reply and shifts every
    /// later reply onto the wrong request, which ends as a terminal that never
    /// draws and never accepts a keystroke.
    @Test func aBlockIsClosedOnlyByItsOwnTerminator() {
        let events = parse("%begin 7 42 1\nline one\n%end 1 2 3\nline two\n%end 7 42 1\n")
        #expect(events.contains(.blockLine("%end 1 2 3")))
        #expect(events.contains(.blockLine("line two")))
        #expect(events.filter { if case .end = $0 { return true }; return false }.count == 1)
    }

    /// Real pane ids lead a `list-panes` line, so a captured screen showing
    /// tmux's own output is the ordinary case, not a corner one.
    @Test func keepsCapturedLinesThatLookLikePaneIDs() {
        let events = parse("%begin 1 2 0\n%0: [80x24] [history 0/2000]\n%end 1 2 0\n")
        #expect(events.contains(.blockLine("%0: [80x24] [history 0/2000]")))
    }

    @Test func parsesStructuralNotifications() {
        #expect(parse("%window-add @9\n") == [.windowAdd(window: "@9")])
        #expect(parse("%window-close @9\n") == [.windowClose(window: "@9")])
        #expect(parse("%sessions-changed\n") == [.sessionsChanged])
        #expect(parse("%window-pane-changed @9 %3\n")
                == [.windowPaneChanged(window: "@9", pane: "%3")])
        #expect(parse("%session-window-changed $9 @2\n")
                == [.sessionWindowChanged(session: "$9", window: "@2")])
    }

    /// Names can contain spaces, so trailing arguments must be rejoined rather
    /// than truncated at the first space.
    @Test func keepsNamesThatContainSpaces() {
        #expect(parse("%window-renamed @9 my long window name\n")
                == [.windowRenamed(window: "@9", name: "my long window name")])
        #expect(parse("%session-changed $9 shio Infer\n")
                == [.sessionChanged(session: "$9", name: "shio Infer")])
    }

    @Test func parsesExitWithAndWithoutAReason() {
        #expect(parse("%exit\n") == [.exit(reason: nil)])
        #expect(parse("%exit server exited unexpectedly\n")
                == [.exit(reason: "server exited unexpectedly")])
    }

    /// tmux gains notifications over time; an older client must degrade rather
    /// than drop the line or crash.
    @Test func unknownNotificationsSurviveAsUnhandled() {
        #expect(parse("%some-future-thing a b c\n") == [.unhandled("%some-future-thing a b c")])
    }

    // MARK: %output

    @Test func decodesOctalEscapesInPaneOutput() {
        let events = parse("%output %9 hi\\033[0mthere\\015\n")
        guard case .output(let pane, let bytes)? = events.first else {
            Issue.record("expected .output, got \(events)"); return
        }
        #expect(pane == "%9")
        // Built in steps rather than as one concatenation. As a single
        // expression the type checker times out on a slower machine — it
        // compiled here and failed in CI with "unable to type-check this
        // expression in reasonable time", because every `+` and every literal
        // is another overload to resolve.
        var expected = Array("hi".utf8)
        expected.append(0x1B)
        expected.append(contentsOf: Array("[0mthere".utf8))
        expected.append(0x0D)
        #expect(bytes == expected)
    }

    /// tmux escapes backslash itself as \134; decoding must yield one literal
    /// backslash and must not then treat it as the start of a new escape.
    @Test func decodesAnEscapedBackslash() {
        let events = parse("%output %1 a\\134\\061b\n")
        guard case .output(_, let bytes)? = events.first else {
            Issue.record("expected .output"); return
        }
        #expect(bytes == Array("a\\1b".utf8))
    }

    /// A malformed escape must stay literal rather than consuming what follows.
    @Test func leavesMalformedEscapesAlone() {
        #expect(TmuxControl.Parser.unescapeOctal(Array("a\\9b".utf8)) == Array("a\\9b".utf8))
        #expect(TmuxControl.Parser.unescapeOctal(Array("trailing\\".utf8)) == Array("trailing\\".utf8))
        #expect(TmuxControl.Parser.unescapeOctal(Array("short\\03".utf8)) == Array("short\\03".utf8))
    }

    /// Pane bytes are arbitrary — invalid UTF-8 is normal mid-escape-sequence
    /// and must survive rather than being replaced with U+FFFD.
    @Test func preservesBytesThatAreNotValidUTF8() {
        let events = parse("%output %1 \\377\\376\n")
        guard case .output(_, let bytes)? = events.first else {
            Issue.record("expected .output"); return
        }
        #expect(bytes == [0xFF, 0xFE])
    }

    @Test func parsesExtendedOutput() {
        let events = parse("%extended-output %2 42 : hi\\033x\n")
        guard case .output(let pane, let bytes)? = events.first else {
            Issue.record("expected .output, got \(events)"); return
        }
        #expect(pane == "%2")
        var expected = Array("hi".utf8)
        expected.append(0x1B)
        expected.append(contentsOf: Array("x".utf8))
        #expect(bytes == expected)
    }

    // MARK: streaming

    /// Bytes arrive from SSH in arbitrary chunks, so every notification and
    /// payload must survive being split at any offset.
    @Test func reassemblesNotificationsSplitAcrossChunks() {
        var p = TmuxControl.Parser()
        var events = p.feed("%window-ad")
        #expect(events.isEmpty, "an incomplete line must not emit anything yet")
        events += p.feed("d @7\n%sessions-chan")
        #expect(events == [.windowAdd(window: "@7")])
        events += p.feed("ged\n")
        #expect(events.last == .sessionsChanged)
    }

    @Test func survivesBeingSplitAtEveryOffset() {
        let transcript = "%window-add @1\n%output %1 a\\033b\n%exit\n"
        let whole = parse(transcript)
        for cut in 1..<transcript.count {
            var p = TmuxControl.Parser()
            let idx = transcript.index(transcript.startIndex, offsetBy: cut)
            var got = p.feed(String(transcript[..<idx]))
            got += p.feed(String(transcript[idx...]))
            #expect(got == whole, "splitting at \(cut) changed the parse")
        }
    }

    @Test func handlesCRLFIdenticallyToLF() {
        #expect(parse("%window-add @4\r\n") == [.windowAdd(window: "@4")])
    }

    // MARK: a real captured session

    /// Captured from `tmux -C new-session` on this machine.
    private static let realSessionTranscript = """
    %begin 1788876277 674590 0
    %end 1788876277 674590 0
    %window-add @9
    %sessions-changed
    %session-changed $9 ccprobe-93406
    %window-renamed @9 tmux
    %begin 1788876277 674597 1
    0: tmux* (1 panes) [80x24] [layout b266,80x24,0,0,9] @9 (active)
    %end 1788876277 674597 1
    %output %9 \\033[1m\\033[7m%\\033[27m\\033[1m\\033[0m \\015
    %output %9 \\015\\033[0m\\033[27m\\033[24m\\033[Jamrith@host Shio % \\033[K\\033[?2004h
    %window-renamed @9 zsh
    %sessions-changed
    %exit

    """

    @Test func parsesARealCapturedSession() {
        let events = parse(Self.realSessionTranscript)

        #expect(events.contains(.windowAdd(window: "@9")))
        #expect(events.contains(.sessionChanged(session: "$9", name: "ccprobe-93406")))
        #expect(events.contains(.windowRenamed(window: "@9", name: "tmux")))
        #expect(events.contains(.windowRenamed(window: "@9", name: "zsh")))
        #expect(events.last == .exit(reason: nil))

        // The list-windows response must land as block content, not as a
        // notification and not as pane output.
        #expect(events.contains { if case .blockLine(let l) = $0 { return l.hasPrefix("0: tmux*") }
                                  else { return false } })

        // Both output lines belong to pane %9 and carry real escape bytes.
        let outputs = events.compactMap { event -> [UInt8]? in
            if case .output(let pane, let bytes) = event, pane == "%9" { return bytes }
            return nil
        }
        #expect(outputs.count == 2)
        #expect(outputs.allSatisfy { $0.contains(0x1B) }, "escape sequences should decode to real ESC bytes")
        #expect(outputs[1].contains(0x0D), "the \\015 should decode to a carriage return")
    }

}

/// Drives a REAL `tmux -C` process and parses its live output.
///
/// The fixture tests above prove the parser against a transcript captured at one
/// moment. This proves it against whatever tmux is actually installed, so a
/// protocol change in a future tmux shows up as a failing test rather than as a
/// terminal that renders nothing.
struct TmuxControlLiveTests {

    static let tmux: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    @Test(.enabled(if: tmux != nil))
    func parsesTheOutputOfARealTmuxControlSession() throws {
        guard let tmux = Self.tmux else {
            Issue.record("tmux was found during discovery but not at run time")
            return
        }
        let session = "shio-cctest-\(UUID().uuidString.prefix(8))"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmux)
        // -C (not -CC) keeps echo on stdin harmless for a piped driver; the
        // notification stream is identical, which is what we're parsing.
        proc.arguments = ["-C", "new-session", "-s", session]
        let stdin = Pipe(), stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = Pipe()
        try proc.run()
        defer {
            if proc.isRunning { proc.terminate() }
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: tmux)
            kill.arguments = ["kill-session", "-t", session]
            kill.standardError = Pipe()
            try? kill.run()
            kill.waitUntilExit()
        }

        // Ask for something with a known response shape, then leave.
        stdin.fileHandleForWriting.write(Data("list-windows\n".utf8))
        Thread.sleep(forTimeInterval: 1.5)
        stdin.fileHandleForWriting.write(Data("kill-session\n".utf8))
        proc.waitUntilExit()

        let raw = stdout.fileHandleForReading.readDataToEndOfFile()
        var parser = TmuxControl.Parser()
        let events = parser.feed([UInt8](raw))

        #expect(!events.isEmpty, "tmux produced no parseable control output")

        // Every block opened must close, or block content would leak into the
        // notification stream and pane output would be mis-attributed.
        let begins = events.filter { if case .begin = $0 { return true } else { return false } }.count
        let ends = events.filter { if case .end = $0 { return true } else { return false } }.count
        #expect(begins > 0)
        #expect(begins == ends, "unbalanced %begin/%end: \(begins) vs \(ends)")

        // The session tmux reports must be the one we asked it to create.
        let named = events.contains { event in
            if case .sessionChanged(_, let name) = event { return name == session }
            return false
        }
        #expect(named, "expected a %session-changed naming \(session)")

        // list-windows must land as block content, never as a notification.
        let windowLine = events.contains { event in
            if case .blockLine(let line) = event { return line.contains("[layout") }
            return false
        }
        #expect(windowLine, "list-windows output should arrive as block lines")

        // Nothing structural should fall through as unhandled; that would mean
        // this tmux speaks something we don't model.
        let unhandled = events.compactMap { event -> String? in
            if case .unhandled(let line) = event, line.hasPrefix("%") { return line }
            return nil
        }
        #expect(unhandled.isEmpty, "unmodelled notifications from this tmux: \(unhandled)")
    }
}
