import Testing
import Foundation
@testable import Shio

/// The local project launch is one string handed to a shell, and the whole
/// string is wrapped in single quotes: `<shell> -lc '<script>'`.
///
/// Two ways that has gone wrong, both pinned here.
///
/// **Quoting.** A single quote anywhere inside the script closes the wrapper
/// early and the rest of the line is reparsed as bare shell words. That is not
/// a runtime failure in the unlucky case — it is a PARSE error, and it takes
/// down every local project terminal on the Mac. It shipped once, when the
/// clone-failure message was written as `printf '...'`, and zsh answered every
/// local project with `parse error near ``n033[31m[shio]'`.
///
/// **Drift.** The local script once duplicated the tmux option list and was
/// missing `set status off` (so tmux drew its status bar on local sessions but
/// never on SSH ones) and `set -sg escape-time 0` (the escape-key lag fix).
/// Both paths share `TmuxResume.attachOptions` now.
struct MacLocalLaunchTests {

    private func launch(name: String = "Infer",
                        path: String = "/Users/amrith/Infer",
                        cloneURL: String? = nil) -> GhosttyMacSurface.LocalLaunch {
        MacLocalLaunch.forProject(name: name, path: path, cloneURL: cloneURL)
    }

    /// `LocalLaunch.command` is optional because a plain shell surface has
    /// none. A project surface always does, and a nil here is itself a bug.
    private func command(_ l: GhosttyMacSurface.LocalLaunch) throws -> String {
        try #require(l.command)
    }

    private var script: String {
        MacLocalLaunch.forProject(name: "Infer", path: "/Users/x/Infer").command ?? ""
    }

    // MARK: Quoting

    /// The invariant. Two single quotes in the whole command: the pair this
    /// builder puts around the script itself.
    @Test func theScriptCarriesNoSingleQuoteOfItsOwn() throws {
        for url in [nil, "https://github.com/shio-sh/shio.git"] {
            let command = try command(launch(cloneURL: url))
            #expect(command.filter { $0 == "'" }.count == 2,
                    "a single quote inside the script closes the -lc wrapper: \(command)")
            #expect(command.hasSuffix("'"))
        }
    }

    /// The message the user reads when a clone fails still has to be there —
    /// the fix for the quoting must not have been "delete the message".
    @Test func aFailedCloneStillExplainsItself() throws {
        let command = try command(launch(cloneURL: "https://example.invalid/nope.git"))
        #expect(command.contains("git clone failed."))
        #expect(command.contains("Check the URL"))
    }

    /// Everything variable rides the environment, so a project path with a
    /// space or a quote in it never reaches the script as text.
    @Test func thePathTravelsInTheEnvironmentNotTheScript() throws {
        let launch = launch(name: "My Project", path: "/Users/amrith/Code/My Project")
        #expect(!(try command(launch)).contains("My Project"))
        #expect(launch.env["SHIO_DIR"] == "/Users/amrith/Code/My Project")
        #expect(launch.env["SHIO_TMUX"] == "shio-My-Project")
    }

    /// The working directory is the repo's PARENT, so the cwd is valid before
    /// a clone has created the repo directory.
    @Test func itStartsInTheParentSoAPendingCloneHasSomewhereToLand() {
        #expect(launch(path: "/Users/amrith/Infer").workingDirectory == "/Users/amrith")
    }

    // MARK: Parity with the SSH path

    @Test func localLaunchCarriesEveryAttachOption() {
        for option in ["set mouse on", "setw -g window-size latest",
                       "set -sg escape-time 0", "set status off"] {
            #expect(script.contains(option), "local tmux launch is missing: \(option)")
        }
    }

    @Test func itUsesTheSameTmuxOptionsAsTheSSHPath() throws {
        #expect(try command(launch()).contains(TmuxResume.attachOptions))
    }

    /// The status bar is the visible symptom users report ("what is this green
    /// bar and how do I get rid of it"), so pin it on its own.
    @Test func localLaunchHidesTheTmuxStatusBar() {
        #expect(script.contains("set status off"))
    }

    @Test func localLaunchAttachesOrCreatesTheProjectSession() {
        #expect(script.contains("new-session -A -s"))
        // Same name the SSH path computes, or the phone and the Mac land in
        // two different sessions for one project.
        #expect(MacLocalLaunch.forProject(name: "Infer", path: "/Users/x/Infer")
            .env["SHIO_TMUX"] == TmuxResume.sessionName(for: "Infer"))
    }

    /// tmux must never be required: no tmux on the machine falls through to a
    /// plain login shell in the project directory.
    @Test func localLaunchFallsBackToAPlainShellWithoutTmux() {
        #expect(script.contains("command -v tmux"))
        #expect(script.contains("exec \"$SHIO_SHELL\" -l"))
    }
}
