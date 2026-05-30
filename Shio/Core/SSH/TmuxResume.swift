import Foundation

/// Invisible tmux integration. The user's `Host.PersistenceMode` selects this
/// behavior; the SessionViewModel routes through it on connect.
///
/// The flow:
///   1. After the shell is open, send: `tmux new-session -A -s shio-<host>\n`
///   2. tmux attaches to an existing session of that name, or creates one.
///   3. On reconnect, the same command silently resumes.
///   4. If tmux isn't installed on the remote, the command produces a
///      "command not found" — we detect that via output and fall back to a
///      plain shell.
///
/// Naming uses `shio-<hostname-with-only-safe-chars>` to keep tmux happy
/// (it doesn't love dots/slashes in session names).
enum TmuxResume {

    /// Build the resume command for a given host name, optionally with a
    /// session index for multi-session support. Index 0 (default) uses the
    /// bare `shio-<host>` name to preserve compatibility with single-session
    /// users' existing tmux sessions. Index >= 1 appends `-<index>`.
    ///
    /// We also enable tmux's mouse mode for the session so Shio's
    /// one-finger pan (which sends mouse-scroll events in alt-screen
    /// mode) reaches tmux and lets it scroll its own scrollback buffer.
    /// Without mouse mode, tmux ignores mouse events and ghostty
    /// falls back to converting them into arrow keys — which then
    /// cycle bash history or get rendered as literal text. `set` (no
    /// `-g`) scopes to the session only, so we don't change the
    /// user's global tmux config.
    static func resumeCommand(for hostName: String, index: Int = 0) -> String {
        let safe = sessionName(for: hostName, index: index)
        // `-A` = attach if session exists, create if not.
        // `\;` = tmux command separator. `set mouse on` enables mouse
        //        reporting for this session only.
        return "tmux new-session -A -s \(safe) \\; set mouse on\n"
    }

    /// Detect (heuristically) whether the remote responded that tmux is
    /// missing. Used by SessionViewModel to fall back gracefully.
    static func looksLikeTmuxMissing(_ output: String) -> Bool {
        let s = output.lowercased()
        return s.contains("tmux: command not found")
            || s.contains("tmux: not found")
            || s.contains("command not found: tmux")
    }

    static func sessionName(for hostName: String, index: Int = 0) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let scrubbed = String(hostName.map { allowed.contains($0) ? $0 : "-" })
        return index == 0 ? "shio-\(scrubbed)" : "shio-\(scrubbed)-\(index)"
    }
}
