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

    /// Master switch — when off, Shio never writes skills into your coding
    /// agents' folders (so it never triggers macOS's "data from other apps"
    /// prompt). Default on. Settable from Settings.
    nonisolated static let syncEnabledKey = "shio.skills.syncToAgents"
    nonisolated static var syncEnabled: Bool {
        UserDefaults.standard.object(forKey: syncEnabledKey) as? Bool ?? true
    }

    /// Set once the user has seen the cross-app explainer (MacShell's alert).
    /// Until then no local sync runs — a library edit must not beat the
    /// explainer to the first "data from other apps" prompt.
    nonisolated static let crossAppExplainedKey = "shio.skills.crossAppExplained"
    nonisolated static var crossAppExplained: Bool {
        UserDefaults.standard.bool(forKey: crossAppExplainedKey)
    }

    /// Whether the launch sync has anything to do — something to write OR
    /// something to remove. A disable/delete made on another device still has
    /// to clean this Mac's folders, so "no enabled globals" isn't "no work".
    func hasGlobalWork() -> Bool {
        let items = globalItems()
        return !items.isEmpty || !Self.tombstones(excluding: Set(items.map(\.dir))).isEmpty
    }

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
        guard Self.syncEnabled, Self.crossAppExplained else { return }
        let items = globalItems()
        Task.detached(priority: .utility) { Self.syncGlobalsLocal(items) }
        #endif
    }

    /// Remove a deleted skill's files locally (the record is gone, so the sync
    /// can't reach it). Mac only. Honors the kill switch — when sync is off,
    /// Shio touches the agents' folders for nothing, removals included.
    func removeGlobalLocally(dirName: String) {
        #if os(macOS)
        guard Self.syncEnabled, Self.crossAppExplained else { return }
        let item = Item(dir: dirName, body: "", enabled: false)
        Task.detached(priority: .utility) { Self.syncGlobalsLocal([item]) }
        #endif
    }

    // MARK: - Tombstones (deleted / renamed-away dirs)

    /// Dirs whose skill was deleted or renamed away. Local cleanup happens
    /// immediately, but a machine that's offline (or a checkout that isn't
    /// open) at that moment still holds the old SKILL.md — so every later
    /// materialize pass sweeps these dirs too. Per-device and capped; sweeping
    /// an absent dir costs nothing. A dir reclaimed by a live skill is
    /// filtered out at sweep time.
    nonisolated private static let tombstoneKey = "shio.skills.tombstones"

    nonisolated static func addTombstone(_ dir: String) {
        guard !dir.isEmpty else { return }
        var list = UserDefaults.standard.stringArray(forKey: tombstoneKey) ?? []
        list.removeAll { $0 == dir }
        list.append(dir)
        if list.count > 64 { list.removeFirst(list.count - 64) }
        UserDefaults.standard.set(list, forKey: tombstoneKey)
    }

    nonisolated static func tombstones(excluding live: Set<String> = []) -> [String] {
        (UserDefaults.standard.stringArray(forKey: tombstoneKey) ?? [])
            .filter { !live.contains($0) }
    }

    /// Call **before** deleting a skill record: tombstones its dir (so future
    /// materialize passes sweep machines that are unreachable right now) and
    /// removes what's reachable immediately.
    func retire(_ skill: Skill, isLocalHost: (Host) -> Bool) {
        Self.addTombstone(skill.dirName)
        if skill.isGlobal {
            removeGlobalLocally(dirName: skill.dirName)
        } else if let project = skill.project {
            skill.enabled = false   // materialize writes the removal for disabled skills
            materialize(project: project, isLocalHost: isLocalHost)
        }
    }

    // MARK: - On project open → materialize to its checkout (local or remote)

    /// Write the skills that apply to `project` — enabled globals (user-level,
    /// vendor-neutral) and this project's own (into the checkout's
    /// `.claude/skills`) — local or over SSH depending on where the checkout is.
    /// Pass `checkout` explicitly when opening one (the default is the
    /// *currently* active checkout, which mid-tap is still the previous one —
    /// and for multi-repo projects can belong to a different repo entirely).
    func materialize(project: Project, checkout explicitCheckout: ProjectCheckout? = nil,
                     isLocalHost: (Host) -> Bool) {
        guard Self.syncEnabled else { return }
        guard let checkout = explicitCheckout
                ?? project.activeRepo?.activeCheckout ?? project.allCheckouts.first,
              !checkout.path.isEmpty else { return }
        let all = (try? ShioModelContainer.shared.mainContext.fetch(FetchDescriptor<Skill>())) ?? []
        let pid = project.persistentModelID
        let applicable = all.filter { $0.isGlobal || $0.project?.persistentModelID == pid }
        let stones = Self.tombstones(excluding: Set(all.map(\.dirName)))
        guard !applicable.isEmpty || !stones.isEmpty else { return }
        let globals = applicable.filter(\.isGlobal).map { Self.item(for: $0) }
        let proj = applicable.filter { !$0.isGlobal }.map { Self.item(for: $0) }
        let projectBase = "\(checkout.path)/.claude/skills"

        if let host = checkout.host, !isLocalHost(host) {
            let config = SSHClient.Configuration(
                host: host.hostname, port: host.port, username: host.username,
                authentication: .systemKeys, initialCols: 80, initialRows: 24)
            Task { await Self.writeRemote(globals: globals, projectBase: projectBase, project: proj,
                                          tombstones: stones, config: config) }
        } else {
            Task.detached(priority: .utility) {
                Self.syncGlobalsLocal(globals)
                let base = (projectBase as NSString).expandingTildeInPath
                for stone in stones { Self.removeLocal(dir: "\(base)/\(stone)") }
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
    /// tool, then sweep tombstoned dirs. Never overwrites a real directory —
    /// only paths that are absent, symlinks we own, or single-file skill dirs
    /// we can adopt losslessly.
    nonisolated static func syncGlobalsLocal(_ items: [Item]) {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let canonicalBase = "\(home)/\(canonicalRel)"
        for stone in tombstones(excluding: Set(items.map(\.dir))) {
            try? fm.removeItem(atPath: "\(canonicalBase)/\(stone)")
            for tool in fanoutTools {
                removeOwnedLink("\(home)/\(tool.skills)/\(stone)", canonicalBase: canonicalBase)
            }
        }
        for it in items {
            let canonical = "\(canonicalBase)/\(it.dir)"
            if it.enabled {
                writeLocal(dir: canonical, body: it.body)
                for tool in fanoutTools where fm.fileExists(atPath: "\(home)/\(tool.config)") {
                    let skillsDir = "\(home)/\(tool.skills)"
                    try? fm.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
                    adoptOrLink(link: "\(skillsDir)/\(it.dir)", to: canonical, canonicalBase: canonicalBase)
                }
            } else {
                try? fm.removeItem(atPath: canonical)
                for tool in fanoutTools {
                    removeOwnedLink("\(home)/\(tool.skills)/\(it.dir)", canonicalBase: canonicalBase)
                }
            }
        }
    }

    /// Create/refresh the tool-dir symlink. Re-points only symlinks that
    /// already point into the canonical store (a user's own symlink to
    /// somewhere else is theirs). A *real* directory is adopted — replaced
    /// with a symlink — only when it's unmistakably the same skill and the
    /// swap loses nothing: a single SKILL.md (no scripts, no extra files)
    /// whose frontmatter name matches the canonical copy's. This is what
    /// makes an *imported* skill follow Shio edits — without adoption, the
    /// agent keeps reading the stale original forever. Anything else is the
    /// user's; never touched.
    private nonisolated static func adoptOrLink(link: String, to dest: String, canonicalBase: String) {
        let fm = FileManager.default
        if isSymlink(link) {
            guard ownsLink(link, canonicalBase: canonicalBase) else { return }
            try? fm.removeItem(atPath: link)
        } else if fm.fileExists(atPath: link) {
            guard let entries = try? fm.contentsOfDirectory(atPath: link),
                  entries.filter({ $0 != ".DS_Store" }) == ["SKILL.md"],
                  let theirs = frontmatterName(at: "\(link)/SKILL.md"),
                  theirs == frontmatterName(at: "\(dest)/SKILL.md")
            else { return }   // a REAL dir we don't own — never clobber
            try? fm.removeItem(atPath: link)
        }
        try? fm.createSymbolicLink(atPath: link, withDestinationPath: dest)
    }

    /// Remove a tool-dir symlink only if it points into the canonical store.
    private nonisolated static func removeOwnedLink(_ path: String, canonicalBase: String) {
        if ownsLink(path, canonicalBase: canonicalBase) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private nonisolated static func ownsLink(_ path: String, canonicalBase: String) -> Bool {
        guard isSymlink(path),
              let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: path)
        else { return false }
        return dest == canonicalBase || dest.hasPrefix(canonicalBase + "/")
    }

    private nonisolated static func frontmatterName(at path: String) -> String? {
        guard let body = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in body.split(separator: "\n").prefix(8) where line.hasPrefix("name:") {
            return line.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private nonisolated static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.type]) as? FileAttributeType == .typeSymbolicLink
    }

    // MARK: - Remote (SSH), one round trip

    /// Materialize globals (canonical + symlink fan-out) and project skills on a
    /// host in a single connection, sweeping tombstoned dirs first. Content is
    /// base64'd so arbitrary markdown can't break the shell; symlinks are only
    /// created where nothing exists and only re-pointed/removed when they
    /// already point into the canonical store (a user's own symlink is theirs).
    nonisolated static func writeRemote(globals: [Item], projectBase: String, project: [Item],
                                        tombstones: [String] = [],
                                        config: SSHClient.Configuration) async {
        var lines: [String] = ["AG=\"$HOME/\(canonicalRel)\""]
        let pb = SSHClient.shellQuotedPath(projectBase)

        /// Remove the canonical dir + any owned tool symlinks for `d`.
        func removalLines(_ d: String) {
            lines.append("rm -rf \"$AG/\(d)\"")
            for tool in fanoutTools {
                lines.append("T=\"$HOME/\(tool.skills)/\(d)\"; if [ -L \"$T\" ]; then case \"$(readlink \"$T\")\" in \"$AG\"*) rm -f \"$T\";; esac; fi")
            }
        }

        for stone in tombstones {
            removalLines(stone)
            lines.append("rm -rf \(pb)/\(q(stone))")
        }
        for it in globals {
            let d = it.dir
            if it.enabled {
                let b64 = Data(it.body.utf8).base64EncodedString()
                lines.append("mkdir -p \"$AG/\(d)\" && printf '%s' \(q(b64)) | base64 --decode > \"$AG/\(d)/SKILL.md\"")
                for tool in fanoutTools {
                    lines.append("if [ -d \"$HOME/\(tool.config)\" ]; then mkdir -p \"$HOME/\(tool.skills)\"; T=\"$HOME/\(tool.skills)/\(d)\"; if [ -L \"$T\" ]; then case \"$(readlink \"$T\")\" in \"$AG\"*) ln -sfn \"$AG/\(d)\" \"$T\";; esac; elif [ ! -e \"$T\" ]; then ln -sfn \"$AG/\(d)\" \"$T\"; fi; fi")
                }
            } else {
                removalLines(d)
            }
        }
        for it in project {
            if it.enabled {
                let b64 = Data(it.body.utf8).base64EncodedString()
                lines.append("mkdir -p \(pb)/\(q(it.dir)) && printf '%s' \(q(b64)) | base64 --decode > \(pb)/\(q(it.dir))/SKILL.md")
            } else {
                lines.append("rm -rf \(pb)/\(q(it.dir))")
            }
        }
        guard lines.count > 1 else { return }
        let script = lines.joined(separator: "\n") + "\n"
        let client = SSHClient(configuration: config)
        do {
            try await client.connect()
            _ = try? await client.exec(posixScript: script, timeout: .seconds(12))
            await client.disconnect()
        } catch {
            await client.disconnect()
        }
    }

    private nonisolated static func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
