import Testing
@testable import Shio

/// The agent classifier's stated bias: a false "waiting" ping is worse than a
/// missed one. These tests pin the cases that enforce it.
struct AgentDetectionTests {

    // MARK: Waiting — the actionable state

    @Test func numberedApprovalMenuWaits() {
        let tail = """
        Do you want to make this edit?
        ❯ 1. yes
          2. no
        """
        let snap = AgentDetector.classify(cleanTail: tail)
        #expect(snap.activity == .waiting)
        #expect(snap.detail == "Approve to continue")
    }

    @Test func bareNumberedListNeverWaits() {
        // "1. yes" without a "2. no" partner is displayed content, not a menu.
        let tail = """
        Verification steps:
        1. yes it compiles
        and nothing else remains
        """
        let snap = AgentDetector.classify(cleanTail: tail)
        #expect(snap.activity != .waiting)
    }

    @Test func explicitConfirmationInLiveWindowWaits() {
        let tail = "About to run the migration.\nAllow this command?\n"
        let snap = AgentDetector.classify(cleanTail: tail)
        #expect(snap.activity == .waiting)
        #expect(snap.detail == "Waiting for your confirmation")
    }

    @Test func genericPromptOnlyCountsAtTheVeryEnd() {
        // End-anchored: fires…
        let ends = AgentDetector.classify(cleanTail: "This will replace 3 files. proceed?")
        #expect(ends.activity == .waiting)
        // …scrolled-past: doesn't.
        let scrolled = AgentDetector.classify(cleanTail: "proceed? y\nDone. All files written.")
        #expect(scrolled.activity != .waiting)
    }

    @Test func yesNoBracketAtEndWaits() {
        let snap = AgentDetector.classify(cleanTail: "Overwrite existing config [y/n]")
        #expect(snap.activity == .waiting)
    }

    // MARK: Running suppresses waiting

    @Test func spinnerAtTheEndSuppressesStalePromptAbove() {
        // A prompt scrolled past while the agent visibly works must NOT ping.
        let tail = "(y/n)\n⠧ crunching the diff"
        let snap = AgentDetector.classify(cleanTail: tail)
        #expect(snap.activity == .running)
    }

    @Test func escToInterruptIsRunning() {
        let snap = AgentDetector.classify(cleanTail: "esc to interrupt · 12s elapsed")
        #expect(snap.activity == .running)
    }

    @Test func tokenCounterIsRunning() {
        let snap = AgentDetector.classify(cleanTail: "Weaving the plan (4.2k tokens)")
        #expect(snap.activity == .running)
    }

    // MARK: Finished / identification

    @Test func agentBackAtShellPromptIsFinished() {
        let tail = "welcome to claude code\n…work happened…\nuser@mbp shio %"
        let snap = AgentDetector.classify(cleanTail: tail)
        #expect(snap.agentName == "Claude Code")
        #expect(snap.activity == .finished)
    }

    @Test func detectsKnownAgents() {
        #expect(AgentDetector.detectAgent(in: "welcome to claude") == "Claude Code")
        #expect(AgentDetector.detectAgent(in: "openai codex session") == "Codex")
        #expect(AgentDetector.detectAgent(in: "aider v0.5") == "Aider")
        #expect(AgentDetector.detectAgent(in: "gemini cli ready") == "Gemini CLI")
        #expect(AgentDetector.detectAgent(in: "plain zsh output") == nil)
    }

    @Test func plainShellOutputIsNone() {
        let snap = AgentDetector.classify(cleanTail: "drwxr-xr-x  5 am  staff  160 Jul  3 10:00 src")
        #expect(snap.activity == .none)
        #expect(snap.agentName == nil)
    }

    // MARK: ANSI stripping

    @Test func stripRemovesEscapesAndCROverwrites() {
        let raw = "\u{001B}[31mred\u{001B}[0m\u{001B}]0;title\u{0007}text\rline"
        #expect(AgentDetector.strip(raw) == "redtext\nline")
    }
}
