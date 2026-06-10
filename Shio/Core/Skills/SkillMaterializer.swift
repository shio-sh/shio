import Foundation
import SwiftData

/// Turns Shio's synced `Skill` records into the files the agents actually read.
///
/// There is no injection or MCP: a skill *is* a `SKILL.md` (markdown + YAML
/// frontmatter) in a directory the agent scans natively. Shio's edge over a
/// local-only tool: it writes those files on **every machine and project** where
/// the agent runs, over the same SSH/checkout layer the status engine uses.
/// `enabled` ⇔ file present.
///
/// **Global** skills are vendor-neutral (v2): the canonical copy lives at
/// `~/.agents/skills/<name>/SKILL.md` and each *installed* tool's dir is
/// **symlinked** to it (`~/.claude/skills/<name>` → canonical, same for Cursor /
/// Codex) — one file, every agent. **Project** skills are written into the
/// checkout's `.claude/skills`. Symlinks are only ever created where nothing
/// real exists or where we already own the symlink — a user's own skill dir is
/// never clobbered.
@MainActor
final class SkillMaterializer {
    static let shared = SkillMaterializer()
    private init() {}

    /// One skill resolved to plain, Sendable values so file/SSH I/O can run off
    /// the main actor without touching the (non-Sendable) SwiftData model.
    struct Item: Sendable { let dir: String; let body: String; let enabled: Bool }

    /// Tools we fan a global skill out to (relative to `$HOME`). The canonical
    /// store is `.agents/skills`; these are symlinked to it when installed.
    private nonisolated static let fanoutTools: [(config: String, skills: String)] = [
        (".claude", ".claude/skills"),
        (".cursor", ".cursor/skills"),
        (".codex",  ".codex/skills"),
    ]
    private nonisolated static let canonicalRel = ".agents/skills"

    // MARK: - SKILL.md content

    /// `--- name / description ---` frontmatter + the rule body. The description
    /// is what the agent uses to decide when to load the skill.
    nonisolated static func fileBody(name: String, description: String, content: String) -> String {
        var s = "---\nname: \(name)\n"
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { s += "description: \(d)\n" }
        s += "---\n\n" + content
        if !content.hasSuffix("\n") { s += "\n" }
        return s
    }

    private static func item(for skill: Skill) -> Item {
        Item(dir: skill.dirName,
             body: fileBody(name: skill.name, description: skill.skillDescription, content: skill.content),
             enabled: skill.enabled)
    }

    private func globalItems() -> [Item] {
        let all = (try? ShioModelContainer.shared.mainContext.fetch(FetchDescriptor<Skill>())) ?? []
        return all.filter(\.isGlobal).map { Self.item(for: $0) }
    }

    // MARK: - Global skills → this Mac (canonical + symlink fan-out)

    /// Sync enabled global skills into this Mac (`~/.agents/skills` + symlinks).
    /// Fire-and-forget; safe to call on launch and every edit. iOS no-ops (no
    /// local agent dir — globals reach remotes when a project opens).
    func scheduleGlobalSync() {
        #if os(macOS)
        let items = globalItems()
        Task.detached(priority: .utility) { Self.syncGlobalsLocal(items) }
        #endif
    }

    /// Remove a deleted skill's files locally (the record is gone, so the sync
    /// can't reach it). Mac only.
    func removeGlobalLocally(dirName: String) {
        #if os(macOS)
        let item = Item(dir: dirName, body: "", enabled: false)
        Task.detached(priority: .utility) { Self.syncGlobalsLocal([item]) }
        #endif
    }

    // MARK: - On project open → materialize to its checkout (local or remote)

    /// Write the skills that apply to `project` — enabled globals (user-level,
    /// vendor-neutral) and this project's own (into the checkout's
    /// `.claude/skills`) — local or over SSH depending on where the checkout is.
    func materialize(project: Project, isLocalHost: (Host) -> Bool) {
        guard let checkout = project.activeRepo?.activeCheckout ?? project.allCheckouts.first,
              !checkout.path.isEmpty else { return }
        let all = (try? ShioModelContainer.shared.mainContext.fetch(FetchDescriptor<Skill>())) ?? []
        let pid = project.persistentModelID
        let applicable = all.filter { $0.isGlobal || $0.project?.persistentModelID == pid }
        guard !applicable.isEmpty else { return }
        let globals = applicable.filter(\.isGlobal).map { Self.item(for: $0) }
        let proj = applicable.filter { !$0.isGlobal }.map { Self.item(for: $0) }
        let projectBase = "\(checkout.path)/.claude/skills"

        if let host = checkout.host, !isLocalHost(host) {
            let config = SSHClient.Configuration(
                host: host.hostname, port: host.port, username: host.username,
                authentication: .systemKeys, initialCols: 80, initialRows: 24)
            Task { await Self.writeRemote(globals: globals, projectBase: projectBase, project: proj, config: config) }
        } else {
            Task.detached(priority: .utility) {
                Self.syncGlobalsLocal(globals)
                let base = (projectBase as NSString).expandingTildeInPath
                for it in proj where it.enabled { Self.writeLocal(dir: "\(base)/\(it.dir)", body: it.body) }
                for it in proj where !it.enabled { Self.removeLocal(dir: "\(base)/\(it.dir)") }
            }
        }
    }

    // MARK: - Local filesystem

    nonisolated static func writeLocal(dir: String, body: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? body.write(toFile: "\(dir)/SKILL.md", atomically: true, encoding: .utf8)
    }

    nonisolated static func removeLocal(dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    /// Write/remove globals at the canonical store + symlink into each installed
    /// tool. Never overwrites a real directory — only paths that are absent or
    /// symlinks we own.
    nonisolated static func syncGlobalsLocal(_ items: [Item]) {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let canonicalBase = "\(home)/\(canonicalRel)"
        for it in items {
            let canonical = "\(canonicalBase)/\(it.dir)"
            if it.enabled {
                writeLocal(dir: canonical, body: it.body)
                for tool in fanoutTools where fm.fileExists(atPath: "\(home)/\(tool.config)") {
                    let skillsDir = "\(home)/\(tool.skills)"
                    try? fm.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
                    linkLocal(link: "\(skillsDir)/\(it.dir)", to: canonical)
                }
            } else {
                try? fm.removeItem(atPath: canonical)
                for tool in fanoutTools {
                    let link = "\(home)/\(tool.skills)/\(it.dir)"
                    if isSymlink(link) { try? fm.removeItem(atPath: link) }
                }
            }
        }
    }

    private nonisolated static func linkLocal(link: String, to dest: String) {
        let fm = FileManager.default
        if isSymlink(link) { try? fm.removeItem(atPath: link) }   // re-point our own symlink
        else if fm.fileExists(atPath: link) { return }            // a REAL dir/file — never clobber
        try? fm.createSymbolicLink(atPath: link, withDestinationPath: dest)
    }

    private nonisolated static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.type]) as? FileAttributeType == .typeSymbolicLink
    }

    // MARK: - Remote (SSH), one round trip

    /// Materialize globals (canonical + symlink fan-out) and project skills on a
    /// host in a single connection. Content is base64'd so arbitrary markdown
    /// can't break the shell; symlinks only replace symlinks/absent paths.
    nonisolated static func writeRemote(globals: [Item], projectBase: String, project: [Item],
                                        config: SSHClient.Configuration) async {
        var lines: [String] = ["AG=\"$HOME/\(canonicalRel)\""]
        for it in globals {
            let d = it.dir
            if it.enabled {
                let b64 = Data(it.body.utf8).base64EncodedString()
                lines.append("mkdir -p \"$AG/\(d)\" && printf '%s' \(q(b64)) | base64 -d > \"$AG/\(d)/SKILL.md\"")
                for tool in fanoutTools {
                    lines.append("if [ -d \"$HOME/\(tool.config)\" ]; then mkdir -p \"$HOME/\(tool.skills)\"; T=\"$HOME/\(tool.skills)/\(d)\"; if [ -L \"$T\" ] || [ ! -e \"$T\" ]; then ln -sfn \"$AG/\(d)\" \"$T\"; fi; fi")
                }
            } else {
                lines.append("rm -rf \"$AG/\(d)\"")
                for tool in fanoutTools {
                    lines.append("T=\"$HOME/\(tool.skills)/\(d)\"; [ -L \"$T\" ] && rm -f \"$T\"")
                }
            }
        }
        let pb = q(projectBase)
        for it in project {
            if it.enabled {
                let b64 = Data(it.body.utf8).base64EncodedString()
                lines.append("mkdir -p \(pb)/\(q(it.dir)) && printf '%s' \(q(b64)) | base64 -d > \(pb)/\(q(it.dir))/SKILL.md")
            } else {
                lines.append("rm -rf \(pb)/\(q(it.dir))")
            }
        }
        guard lines.count > 1 else { return }
        let script = lines.joined(separator: "\n") + "\n"
        let client = SSHClient(configuration: config)
        do {
            try await client.connect()
            _ = try? await client.exec(script, timeout: .seconds(12))
            await client.disconnect()
        } catch {
            await client.disconnect()
        }
    }

    private nonisolated static func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
