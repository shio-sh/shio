import SwiftUI

/// Builds the LOCAL-backend launch for a Project opened on this Mac.
///
/// A local Project is a folder on the Mac itself (no SSH host). We open it as
/// an **invisible-tmux** session so the very same session is reachable from the
/// phone later (the Mac is a host; the tmux name matches what iOS computes for
/// the project). But tmux must never be *required*: if it isn't installed we
/// fall straight through to a plain login shell in the repo directory, so the
/// local terminal stays the "perfect plain shell."
///
/// The command ghostty execs is `<shell> -lc '<script>'`. The script references
/// only `$SHIO_*` env vars (set via the surface config) and uses double quotes
/// internally — never single quotes — so it survives whether libghostty execs
/// the string directly (quote-aware argv split) or wraps it in `/bin/sh -c`.
/// Passing the path/name through the environment also sidesteps any quoting
/// hazard from spaces in the project path.
enum MacLocalLaunch {

    static func forProject(name: String, path: String, cloneURL: String? = nil) -> GhosttyMacSurface.LocalLaunch {
        // Match the tmux name iOS computes for a project (index 0): `shio-<scrubbed>`.
        // This is what makes a local Mac project and the same project opened
        // from the phone (over SSH to this Mac) attach the one tmux session.
        let tmuxName = "shio-\(TmuxResume.scrubName(name))"
        let shell = MacSettings.defaultShell

        // 1. If created from a git URL, clone once (only when the dir is
        //    missing) — mirrors the SSH path's clone-on-first-open.
        // 2. tmux if present → attach/create the invisible session (mouse mode
        //    on, scoped, for scrollback parity), opened in the repo dir; else a
        //    plain login shell there. `exec` so the terminal closes cleanly.
        // Everything rides $SHIO_* env vars (double quotes only, no single
        // quotes) so the path survives spaces and the outer single-quoting.
        let script = #"[ -z "$SHIO_CLONE" ] || [ -d "$SHIO_DIR" ] || git clone "$SHIO_CLONE" "$SHIO_DIR"; command -v tmux >/dev/null 2>&1 && exec tmux new-session -A -s "$SHIO_TMUX" -c "$SHIO_DIR" \; set mouse on || { cd "$SHIO_DIR" && exec "$SHIO_SHELL" -l; }"#
        let command = "\(shell) -lc '\(script)'"

        // Start in the repo's *parent* so the cwd is valid even before a clone
        // creates the repo dir; the script then enters $SHIO_DIR itself.
        let parent = (path as NSString).deletingLastPathComponent
        return .init(
            workingDirectory: parent.isEmpty ? path : parent,
            command: command,
            env: [
                "SHIO_TMUX": tmuxName,
                "SHIO_SHELL": shell,
                "SHIO_DIR": path,
                "SHIO_CLONE": cloneURL ?? "",
            ]
        )
    }
}

/// A local Project terminal on the Mac: a `.local` ghostty surface that owns
/// its own PTY (no SSHClient), launched into the project's invisible-tmux
/// session. Mirrors `MacSSHSession`'s shape so the detail pane can host either.
@MainActor
@Observable
final class MacLocalProjectSession: Identifiable {
    let id = UUID()
    let displayName: String
    // Stored for tab persistence + reopen on relaunch.
    let path: String
    let cloneURL: String?
    let surface: GhosttyMacSurface

    convenience init(project: Project) {
        self.init(name: project.name, path: project.path, cloneURL: project.cloneURL)
    }

    init(name: String, path: String, cloneURL: String?) {
        self.displayName = name
        self.path = path
        self.cloneURL = cloneURL
        let launch = MacLocalLaunch.forProject(name: name, path: path, cloneURL: cloneURL)
        self.surface = GhosttyMacSurface(backend: .local, launch: launch)
    }

    /// Dropping the session frees the surface (deinit → `ghostty_surface_free`),
    /// which ends the local PTY. The invisible-tmux session keeps running on
    /// the machine — that's the point — so reopening reattaches it.
    func stop() async {}
}
