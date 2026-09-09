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
        return "tmux new-session -A -s \(safe)\(sessionOptions)\n"
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
        let scrubbed = scrubName(hostName)
        return index == 0 ? "shio-\(scrubbed)" : "shio-\(scrubbed)-\(index)"
    }

    /// Scrub an arbitrary string (host or project name) down to tmux-safe
    /// characters. Used when building project session names.
    static func scrubName(_ s: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return String(s.map { allowed.contains($0) ? $0 : "-" })
    }

    /// Resume command for an explicitly-named tmux session, optionally
    /// starting in `startDir` (project sessions: `shio-<project>` opened in
    /// the repo directory). `-A` attaches-or-creates; mouse mode is scoped
    /// to the session.
    ///
    /// If `cloneURL` is given alongside `startDir`, a guarded `git clone`
    /// runs first — only when `startDir` doesn't already exist — so a
    /// project created from a git URL clones itself on first open and is a
    /// plain resume thereafter. The clone rides the host's own git auth.
    static func resumeCommand(named name: String, startDir: String? = nil, cloneURL: String? = nil) -> String {
        var cmd = ""
        if let cloneURL, !cloneURL.isEmpty, let startDir, !startDir.isEmpty {
            // `[ -d dir ] || git clone url dir` — clone only if missing.
            cmd += "[ -d \(SSHClient.shellQuotedPath(startDir)) ] || git clone \(singleQuoted(cloneURL)) \(SSHClient.shellQuotedPath(startDir)); "
        }
        cmd += "tmux new-session -A -s \(name)"
        if let startDir, !startDir.isEmpty {
            cmd += " -c \(SSHClient.shellQuotedPath(startDir))"
        }
        cmd += "\(sessionOptions)\n"
        return cmd
    }

    /// Exec-channel form of `resumeCommand(named:)` — the SSH session runs this
    /// directly as its command (NON-interactive shell), so it bypasses the
    /// user's `.zshrc`/`.bashrc` and any auto-tmux there can't preempt Shio.
    /// `command -v tmux` guards a fallback to a plain login shell when tmux
    /// isn't installed. No trailing newline (it's the command, not typed input).
    ///
    /// `controlMode` swaps in `tmux -CC`, where tmux stops drawing a screen and
    /// starts describing one. It is the same line otherwise — same PATH repair,
    /// same clone guard, same start directory, same options — because any
    /// divergence between the two would be a second way for the start directory
    /// or the clone to quietly not happen.
    static func execLine(named name: String, startDir: String? = nil, cloneURL: String? = nil,
                         controlMode: Bool = false) -> String {
        var cmd = ""
        if let cloneURL, !cloneURL.isEmpty, let startDir, !startDir.isEmpty {
            cmd += "[ -d \(SSHClient.shellQuotedPath(startDir)) ] || git clone \(singleQuoted(cloneURL)) \(SSHClient.shellQuotedPath(startDir)); "
        }
        // The exec channel runs NON-interactively, so PATH is the bare system
        // default (/usr/bin:/bin:/usr/sbin:/sbin) — the login shell's PATH never
        // ran. Homebrew tmux lives outside that, so `command -v tmux` failed and
        // the `||` below silently dropped the user into a plain shell: no tmux,
        // no session to share, no start directory. That is the cross-device
        // promise quietly not working. Linux distros ship tmux in /usr/bin and
        // were unaffected, which is why it hid for so long.
        cmd += "PATH=\"$PATH:\(Self.commonBinDirs.joined(separator: ":"))\"; "
        cmd += "command -v tmux >/dev/null 2>&1 && exec tmux \(controlMode ? "-CC " : "")new-session -A -s \(name)"
        if let startDir, !startDir.isEmpty {
            cmd += " -c \(SSHClient.shellQuotedPath(startDir))"
        }
        cmd += "\(sessionOptions) || exec \"${SHELL:-/bin/sh}\" -l"
        return cmd
    }

    /// Where tmux actually lives when PATH hasn't been set up: Homebrew on
    /// Apple Silicon, Homebrew on Intel, MacPorts. Appended (never prepended)
    /// so a tmux the user put earlier on PATH still wins.
    static let commonBinDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]

    /// tmux options applied on every attach (`\;`-chained onto `new-session`).
    /// `set mouse on` lets Shio's pan / page controls (mouse-scroll events) reach
    /// tmux and the running TUI.
    ///
    /// `window-size latest` sizes the session to whichever device is active —
    /// native size on each (Mac full and clean, phone phone-sized), reflowing
    /// only when both are open and you switch. We set it EXPLICITLY (not just
    /// omit it): `window-size` is a global server option that persists, so a
    /// session previously attached with `smallest` stays pinned small (the
    /// dotted dead-zone) until something overrides it.
    ///
    /// `escape-time 0` kills the single biggest source of perceived lag: tmux's
    /// default 500ms wait after ESC (to disambiguate escape sequences) makes vim
    /// and agent TUIs feel sluggish over SSH. It's a server option (`-sg`), so it
    /// applies to every Shio attach. `status off` hides tmux's own status bar so
    /// the terminal reads as a clean native surface — session-scoped (no `-g`),
    /// so it never touches the user's other tmux sessions on the same server.
    static let attachOptions =
        " \\; set mouse on \\; setw -g window-size latest \\; set -sg escape-time 0 \\; set status off"

    /// Remote control: **Mirror** — tmux's native behavior. Every device that
    /// attaches the same `shio-<name>` session sees it live and shares control.
    static var sessionOptions: String { attachOptions }

    private static func singleQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
