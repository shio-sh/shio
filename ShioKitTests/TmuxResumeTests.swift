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
        // Non-interactive exec bootstrap: make tmux findable, probe it, exec it,
        // fall back to a login shell — and never end with a newline (it's the
        // command). The PATH extension leads because a non-interactive shell
        // gets the bare system PATH and would otherwise miss Homebrew's tmux
        // entirely, silently dropping the user into a shell with no session.
        #expect(line.hasPrefix("PATH="))
        #expect(line.contains("command -v tmux"))
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

/// The bootstrap that broke the cross-device promise in the field.
///
/// `execLine` is the SSH exec command, run NON-interactively so a user's
/// `.zshrc` cannot preempt Shio's session. The cost of that choice is a bare
/// system PATH: the login shell's PATH never runs, so Homebrew's tmux was
/// invisible, `command -v tmux` failed, and the `||` fallback dropped the user
/// into a plain login shell — no tmux, no shared session, no start directory.
/// The Mac looked fine because it launches tmux locally; only the phone hit it.
struct TmuxExecLinePathTests {

    @Test func extendsPathBeforeLookingForTmux() {
        let line = TmuxResume.execLine(named: "shio-Infer")
        for dir in TmuxResume.commonBinDirs {
            #expect(line.contains(dir), "bootstrap must be able to find tmux in \(dir)")
        }
        // The PATH assignment has to come first or the lookup still misses.
        let pathIndex = line.range(of: "PATH=")?.lowerBound
        let lookupIndex = line.range(of: "command -v tmux")?.lowerBound
        #expect(pathIndex != nil && lookupIndex != nil)
        if let p = pathIndex, let l = lookupIndex { #expect(p < l) }
    }

    /// Appended, never prepended: a tmux the user deliberately put earlier on
    /// PATH must still win over whatever Homebrew happens to have.
    @Test func appendsRatherThanOverridingTheUsersPath() {
        #expect(TmuxResume.execLine(named: "x").contains("PATH=\"$PATH:"))
    }

    /// tmux genuinely absent must still fall through to a usable shell.
    @Test func keepsThePlainShellFallback() {
        #expect(TmuxResume.execLine(named: "x").contains("exec \"${SHELL:-/bin/sh}\" -l"))
    }

    @Test func stillAttachesOrCreatesInTheStartDirectory() {
        let line = TmuxResume.execLine(named: "shio-Infer", startDir: "/Users/am/Infer")
        #expect(line.contains("new-session -A -s shio-Infer"))
        #expect(line.contains("/Users/am/Infer"))
    }

    /// The exec form takes no trailing newline — it is the command, not typed
    /// input — and a stray one would break the exec channel.
    @Test func carriesNoTrailingNewline() {
        #expect(TmuxResume.execLine(named: "x").hasSuffix("\n") == false)
    }
}
