import Foundation

/// Coarse, agent-agnostic state inferred from a session's output stream.
public enum AgentActivity: String, Codable, Hashable, Sendable {
    case none      // no agent detected in this session
    case running   // the agent is working
    case waiting   // the agent is blocked on you (approval / input)
    case finished  // the agent finished its turn / returned to the shell
}

/// What we believe is running in a session, and its state.
public struct AgentSnapshot: Equatable, Hashable, Sendable {
    public var agentName: String?    // "Claude Code", "Codex", or nil for a generic agent
    public var activity: AgentActivity
    public var detail: String?       // short context, e.g. the prompt it's waiting on

    public init(agentName: String? = nil, activity: AgentActivity = .none, detail: String? = nil) {
        self.agentName = agentName
        self.activity = activity
        self.detail = detail
    }
}

/// Heuristic output-watching classifier — the universal baseline that works
/// for any agent (per-agent hooks harden specific tools later). We keep a
/// rolling, ANSI-stripped tail of recent output per session and re-classify
/// on each chunk.
///
/// Bias: a false "waiting" ping (telling you an agent needs you when it
/// doesn't) is worse than a missed one, so `waiting` requires a recognizable
/// approval/input prompt at the end of the output.
public enum AgentDetector {

    // MARK: ANSI stripping

    /// Remove ANSI/VT escape sequences and carriage-return overwrites so the
    /// classifier sees plain text.
    public static func strip(_ s: String) -> String {
        var out = s
        // CSI sequences: ESC [ … final-byte
        out = out.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "", options: .regularExpression)
        // OSC sequences: ESC ] … BEL  or  ESC ] … ST
        out = out.replacingOccurrences(
            of: "\u{001B}\\][^\u{0007}\u{001B}]*(\u{0007}|\u{001B}\\\\)",
            with: "", options: .regularExpression)
        // Other two-byte escapes.
        out = out.replacingOccurrences(
            of: "\u{001B}[@-Z\\\\-_]",
            with: "", options: .regularExpression)
        // Carriage returns (progress-bar overwrites) → newlines.
        out = out.replacingOccurrences(of: "\r", with: "\n")
        return out
    }

    // MARK: Agent identification

    /// Recognize which agent (if any) is present from a banner/marker.
    /// Sticky on the caller's side — once seen, remember it.
    public static func detectAgent(in lowerTail: String) -> String? {
        if lowerTail.contains("claude code") || lowerTail.contains("welcome to claude") {
            return "Claude Code"
        }
        if lowerTail.contains("openai codex") || lowerTail.contains("codex cli") {
            return "Codex"
        }
        if lowerTail.contains("aider") { return "Aider" }
        if lowerTail.contains("gemini") && lowerTail.contains("cli") { return "Gemini CLI" }
        return nil
    }

    // MARK: Classification

    /// Classify activity from a cleaned (already ANSI-stripped) tail.
    public static func classify(cleanTail tail: String) -> AgentSnapshot {
        let lower = tail.lowercased()
        let agent = detectAgent(in: lower)

        // Waiting takes priority — it's the actionable state.
        if let detail = waitingPrompt(in: tail, lower: lower) {
            return AgentSnapshot(agentName: agent, activity: .waiting, detail: detail)
        }
        if isRunning(lower) {
            return AgentSnapshot(agentName: agent, activity: .running)
        }
        if agent != nil, endsAtShellPrompt(tail) {
            return AgentSnapshot(agentName: agent, activity: .finished)
        }
        return AgentSnapshot(agentName: agent, activity: agent != nil ? .running : .none)
    }

    /// Detect an approval / input prompt the agent (or a plain command) is
    /// blocked on. Returns a short label for it, or nil.
    private static func waitingPrompt(in tail: String, lower: String) -> String? {
        // Only consider the last stretch — a prompt scrolled far up isn't live.
        let window = String(lower.suffix(800))

        // Claude Code / Codex style numbered approval menus. NOTE the explicit
        // grouping: `&&` binds tighter than `||`, so without these parens a
        // bare "1. yes" anywhere would fire a false "waiting" ping.
        if (window.contains("❯ 1. yes") || window.contains("1. yes"))
            && (window.contains("2. no") || window.contains("don't ask again")) {
            return "Approve to continue"
        }
        // Common yes/no confirmations.
        let confirmations = [
            "do you want to proceed", "do you want to make this edit",
            "allow this command", "allow command", "run this command",
            "proceed?", "continue?", "overwrite?", "are you sure",
            "(y/n)", "[y/n]", "(yes/no)", "[y/n]", "press enter to continue",
        ]
        for c in confirmations where window.contains(c) {
            return "Waiting for your confirmation"
        }
        // A bare "y/N"-style prompt at the very end.
        if window.range(of: "\\[(y/n|yes/no)\\]\\s*$", options: .regularExpression) != nil {
            return "Waiting for your confirmation"
        }
        return nil
    }

    /// Signals that an agent is actively working.
    private static func isRunning(_ lower: String) -> Bool {
        let window = String(lower.suffix(400))
        let markers = [
            "esc to interrupt", "thinking", "working…", "working...",
            "running…", "running...", "generating", "tokens)",
        ]
        if markers.contains(where: window.contains) { return true }
        // Braille spinner glyphs Claude/others animate with.
        let spinners = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        if window.unicodeScalars.contains(where: { spinners.unicodeScalars.contains($0) }) {
            return true
        }
        return false
    }

    /// True if the cleaned tail ends at what looks like a shell prompt —
    /// a rough signal the agent handed control back.
    private static func endsAtShellPrompt(_ tail: String) -> Bool {
        let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        // Typical prompt terminators. Conservative: must be the final char.
        return "$%#➜❯".contains(last)
    }
}
