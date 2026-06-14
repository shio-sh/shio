import Foundation

/// Plays a scripted **Claude Code** session into the real libghostty surface
/// when a repo's terminal is opened in demo mode — the hero screenshot ("Claude
/// Code, on your own machine, from your phone"). No SSH; the bytes are written
/// straight to the surface, animated with small delays, and it ends on an
/// approval prompt that matches the seeded ⚑ "needs you" state.
@MainActor
enum DemoTerminal {

    /// The agent state to publish once the transcript reaches the prompt, so the
    /// channel header shows ⚑ and the Approve/Deny bar appears.
    static let waiting = AgentSnapshot(agentName: "Claude Code", activity: .waiting,
                                       detail: "Apply the schema migration?")

    /// Stream the transcript via `write` (which feeds the surface). `repo`/`path`
    /// tailor the prompt to whatever conversation was opened.
    static func play(repo: String, host: String, user: String, path: String,
                     write: @escaping (String) -> Void) async {
        let O = "\u{1b}[38;2;215;119;87m"   // Claude orange
        let G = "\u{1b}[38;2;78;186;112m"   // green
        let D = "\u{1b}[90m"                // dim
        let B = "\u{1b}[1m"
        let R = "\u{1b}[0m"

        func emit(_ s: String, _ ms: UInt64 = 230) async {
            write(s)
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
        }
        // A padded box row (W = inner content width), so borders align regardless
        // of ANSI color codes (which have zero display width).
        let W = 38
        let bar = String(repeating: "─", count: W + 1)
        func row(_ text: String, _ color: String = "") -> String {
            let pad = String(repeating: " ", count: max(0, W - text.count))
            return "\(O)│\(R) \(color)\(text)\(R)\(pad)\(O)│\(R)\r\n"
        }

        await emit("\u{1b}[2J\u{1b}[H", 60)   // clear + home
        await emit("\(D)\(user)@\(host)\(R) \(path) \(G)(main)\(R)\r\n", 140)
        await emit("$ claude\r\n\r\n", 520)
        await emit("\(O)✻\(R) \(B)Welcome to Claude Code\(R)\r\n", 320)
        await emit("\(D)  Sonnet 4.6 · cwd: \(path)\(R)\r\n\r\n", 280)
        await emit("\(B)>\(R) add a projects-first overview\r\n\r\n", 620)
        await emit("\(O)●\(R) I'll add the overview.\r\n\r\n", 460)
        await emit("\(O)●\(R) \(B)Read\(R)(HomeTabView.swift)\r\n", 240)
        await emit("\(D)  ⎿  Read 312 lines\(R)\r\n\r\n", 360)
        await emit("\(O)●\(R) \(B)Update\(R)(HomeTabView.swift)\r\n", 240)
        await emit("\(D)  ⎿  Updated · 47 additions, 6 removals\(R)\r\n\r\n", 420)
        await emit("\(O)●\(R) \(B)Bash\(R)(xcodebuild build)\r\n", 240)
        await emit("\(D)  ⎿  \(R)\(G)** BUILD SUCCEEDED **\(R)\r\n\r\n", 520)
        await emit("\(O)●\(R) Done. The overview lists every project,\r\n", 220)
        await emit("  its agents, and git state.\r\n\r\n", 360)
        await emit("  Apply the schema migration?\r\n\r\n", 420)
        await emit("\(O)╭\(bar)╮\(R)\r\n", 70)
        await emit(row("Apply this change?"), 70)
        await emit(row("❯ 1. Yes", O), 70)
        await emit(row("  2. No, tell me what to change", D), 70)
        await emit("\(O)╰\(bar)╯\(R)\r\n", 70)
    }
}
