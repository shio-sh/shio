import Testing
import Foundation
@testable import Shio

/// The local Mac launch and the SSH launch must configure tmux identically.
///
/// They drifted once: the local script duplicated the option list and was
/// missing `set status off` (so tmux drew its status bar on local sessions but
/// never on SSH ones) and `set -sg escape-time 0` (the escape-key lag fix).
/// Both paths now share `TmuxResume.attachOptions`; these tests fail if anyone
/// re-inlines them.
struct MacLocalLaunchTests {

    private var script: String {
        MacLocalLaunch.forProject(name: "Infer", path: "/Users/x/Infer").command ?? ""
    }

    @Test func localLaunchCarriesEveryAttachOption() {
        for option in ["set mouse on", "setw -g window-size latest",
                       "set -sg escape-time 0", "set status off"] {
            #expect(script.contains(option), "local tmux launch is missing: \(option)")
        }
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
