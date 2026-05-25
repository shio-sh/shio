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

    /// Build the resume command for a given host name.
    /// Returns the raw bytes to send after the shell is ready.
    static func resumeCommand(for hostName: String) -> String {
        let safe = sessionName(for: hostName)
        // `-A` = attach if session exists, create if not.
        // `-s` = session name.
        // Trailing newline executes it.
        return "tmux new-session -A -s \(safe)\n"
    }

    /// Detect (heuristically) whether the remote responded that tmux is
    /// missing. Used by SessionViewModel to fall back gracefully.
    static func looksLikeTmuxMissing(_ output: String) -> Bool {
        let s = output.lowercased()
        return s.contains("tmux: command not found")
            || s.contains("tmux: not found")
            || s.contains("command not found: tmux")
    }

    static func sessionName(for hostName: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let scrubbed = String(hostName.map { allowed.contains($0) ? $0 : "-" })
        return "shio-\(scrubbed)"
    }
}
