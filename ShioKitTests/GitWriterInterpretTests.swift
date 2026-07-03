import Testing
@testable import Shio

/// The exec-truth table: a verdict comes from the exit status, never from
/// grepping the transcript. "Committed and pushed." must never be a lie.
struct GitWriterInterpretTests {

    @Test func timeoutNeverReadsAsSuccess() {
        let o = GitWriter.interpret(stdout: "Enumerating objects: 12",
                                    stderr: "", exitStatus: nil, timedOut: true)
        guard case .failed(let msg) = o else {
            Issue.record("timeout must be a failure"); return
        }
        #expect(msg.contains("Timed out"))
        #expect(msg.contains("Enumerating objects"))
    }

    @Test func lostConnectionIsFailure() {
        let o = GitWriter.interpret(stdout: "", stderr: "", exitStatus: nil, timedOut: false)
        #expect(o == .failed("The connection closed before git finished."))
    }

    @Test func nothingToCommitGetsTheFriendlyCopy() {
        let o = GitWriter.interpret(stdout: "On branch main\nnothing to commit, working tree clean",
                                    stderr: "", exitStatus: 1, timedOut: false)
        #expect(o == .failed("Nothing to commit — working tree clean."))
    }

    @Test func nonZeroExitSurfacesStderr() {
        let o = GitWriter.interpret(stdout: "",
                                    stderr: "fatal: could not read Username", exitStatus: 128, timedOut: false)
        guard case .failed(let msg) = o else {
            Issue.record("exit 128 must be a failure"); return
        }
        #expect(msg.contains("fatal: could not read Username"))
    }

    @Test func silentNonZeroExitStillNamesTheStatus() {
        let o = GitWriter.interpret(stdout: "", stderr: "", exitStatus: 1, timedOut: false)
        #expect(o == .failed("git exited with status 1."))
    }

    @Test func errorWordInACommitMessageIsNotFailure() {
        // exit 0 is the only truth — a commit subject containing "error:" is fine.
        let o = GitWriter.interpret(stdout: "[main 3f2a1c9] fix: error: handling in parser",
                                    stderr: "", exitStatus: 0, timedOut: false)
        guard case .ok(let msg) = o else {
            Issue.record("exit 0 must be success"); return
        }
        #expect(msg.contains("error: handling"))
    }

    @Test func quietSuccessGetsTheFallbackCopy() {
        let o = GitWriter.interpret(stdout: "", stderr: "", exitStatus: 0, timedOut: false)
        #expect(o == .ok("Committed and pushed."))
    }
}
