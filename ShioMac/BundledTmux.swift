import Foundation

/// The tmux Shio carries so a Mac that never installed one still gets
/// standing conversations, agent watching, and cross-device continuity.
///
/// Precedence is sacred: the user's own tmux ALWAYS wins (their config, their
/// running server — tmux clients and servers must speak the same protocol, so
/// we never mix ours with theirs). The session bootstrap appends this dir to
/// the END of PATH; the agent monitor tries it last. Produced by
/// scripts/bundle-tmux.sh (gitignored) — absent in a fresh clone, and
/// everything degrades exactly as before.
enum BundledTmux {

    /// `…/Shio.app/Contents/Resources/tmux/bin`, or nil when not bundled.
    static let binDir: String? = {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("tmux/bin"),
              FileManager.default.isExecutableFile(atPath: dir.appendingPathComponent("tmux").path)
        else { return nil }
        return dir.path
    }()

    /// Full path to the bundled binary, or nil when not bundled.
    static var binaryPath: String? { binDir.map { $0 + "/tmux" } }
}
