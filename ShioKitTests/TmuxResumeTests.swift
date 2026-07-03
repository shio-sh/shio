import Testing
@testable import Shio

/// The tmux bootstrap lines are what every device types into every machine —
/// quoting and shape here are load-bearing (injection safety included).
struct TmuxResumeTests {

    @Test func scrubReplacesUnsafeCharacters() {
        #expect(TmuxResume.scrubName("my repo/v2.0") == "my-repo-v2-0")
        #expect(TmuxResume.scrubName("clean-name_1") == "clean-name_1")
    }

    @Test func sessionNamesAreDeterministicAndIndexed() {
        #expect(TmuxResume.sessionName(for: "MBP") == "shio-MBP")
        #expect(TmuxResume.sessionName(for: "MBP", index: 2) == "shio-MBP-2")
        // Index 0 stays bare for compatibility with existing sessions.
        #expect(TmuxResume.sessionName(for: "MBP", index: 0) == "shio-MBP")
    }

    @Test func execLineShape() {
        let line = TmuxResume.execLine(named: "shio-app", startDir: "~/Code/app")
        // Non-interactive exec bootstrap: probe tmux, exec it, fall back to a
        // login shell — and never end with a newline (it's the command).
        #expect(line.hasPrefix("command -v tmux"))
        #expect(line.contains("exec tmux new-session -A -s shio-app"))
        #expect(line.contains("-c \"$HOME\"/'Code/app'"))
        #expect(line.hasSuffix("|| exec \"${SHELL:-/bin/sh}\" -l"))
        #expect(!line.contains("\n"))
    }

    @Test func typedResumeCommandEndsWithNewline() {
        // The interactive-shell form IS typed input — it needs the Enter.
        #expect(TmuxResume.resumeCommand(named: "shio-app").hasSuffix("\n"))
        #expect(TmuxResume.resumeCommand(for: "MBP").hasSuffix("\n"))
    }

    @Test func cloneIsGuardedAndSingleQuoted() {
        let evil = "https://x.example/repo.git'; rm -rf ~; '"
        let line = TmuxResume.execLine(named: "shio-x", startDir: "/tmp/x", cloneURL: evil)
        // Clone only when the checkout is missing.
        #expect(line.contains("[ -d '/tmp/x' ] || git clone "))
        // The URL's quotes are escaped — the injection never leaves its quoting.
        #expect(!line.contains("git'; rm"))
        #expect(line.contains("'https://x.example/repo.git'\\''; rm -rf ~; '\\'''"))
    }

    @Test func noCloneWithoutBothURLAndDir() {
        #expect(!TmuxResume.execLine(named: "s", startDir: "/tmp/x").contains("git clone"))
        #expect(!TmuxResume.execLine(named: "s", cloneURL: "https://x/y.git").contains("git clone"))
    }

    @Test func attachOptionsCarryTheLagAndSizingFixes() {
        let opts = TmuxResume.attachOptions
        #expect(opts.contains("set mouse on"))
        #expect(opts.contains("window-size latest"))
        #expect(opts.contains("escape-time 0"))
        #expect(opts.contains("set status off"))
    }

    @Test func tmuxMissingDetection() {
        #expect(TmuxResume.looksLikeTmuxMissing("zsh: command not found: tmux"))
        #expect(TmuxResume.looksLikeTmuxMissing("tmux: command not found"))
        #expect(TmuxResume.looksLikeTmuxMissing("sh: tmux: not found"))
        #expect(!TmuxResume.looksLikeTmuxMissing("tmux 3.4, attached"))
    }
}
