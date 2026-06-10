import Foundation
import SwiftData

/// Turns Shio's synced `Skill` records into the files the agents actually read.
///
/// There is no injection or MCP: a skill *is* a `SKILL.md` (markdown + YAML
/// frontmatter) sitting in a directory the agent scans natively — global at
/// `~/.claude/skills/<name>/SKILL.md`, per-project at `<repo>/.claude/skills/`.
/// Shio's edge over a local-only tool: it writes those files on **every machine
/// and project** where the agent runs, over the same SSH/checkout layer the
/// status engine uses. `enabled` ⇔ file present.
///
/// v1 targets Claude Code's `.claude/skills` layout; the vendor-neutral
/// `.agents` canonical + symlink fan-out is v2 (#38).
@MainActor
final class SkillMaterializer {
    static let shared = SkillMaterializer()
    private init() {}

    /// One skill resolved to plain, Sendable values so file/SSH I/O can run off
    /// the main actor without touching the (non-Sendable) SwiftData model.
    struct Item: Sendable { let dir: String; let body: String; let enabled: Bool }

    // MARK: - SKILL.md content

    /// `--- name / description ---` frontmatter + the rule body. The description
    /// is what the agent uses to decide when to load the skill, so it's emitted
    /// even though it's optional in our model.
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

    // MARK: - Global skills → this machine (Mac only; iOS has no local agent dir)

    /// Mirror the enabled global skills into this Mac's `~/.claude/skills`. A
    /// disabled global is removed. Fire-and-forget; safe to call on every edit.
    func scheduleGlobalSync() {
        #if os(macOS)
        let all = (try? ShioModelContainer.shared.mainContext.fetch(FetchDescriptor<Skill>())) ?? []
        let base = ("~/.claude/skills" as NSString).expandingTildeInPath
        let items = all.filter(\.isGlobal).map { Self.item(for: $0) }
        Task.detached(priority: .utility) {
            for it in items {
                let dir = "\(base)/\(it.dir)"
                if it.enabled { Self.writeLocal(dir: dir, body: it.body) }
                else { Self.removeLocal(dir: dir) }
            }
        }
        #endif
    }

    /// Remove a deleted skill's directory locally (the record is already gone, so
    /// `scheduleGlobalSync` can't reach it). Mac only.
    func removeGlobalLocally(dirName: String) {
        #if os(macOS)
        let base = ("~/.claude/skills" as NSString).expandingTildeInPath
        let dir = "\(base)/\(dirName)"
        Task.detached(priority: .utility) { Self.removeLocal(dir: dir) }
        #endif
    }

    // MARK: - On project open → materialize to its checkout (local or remote)

    /// Write the skills that apply to `project` (enabled globals ∪ this project's
    /// own) into the active checkout's `.claude/skills` — local FileManager if the
    /// checkout is on this device, else over SSH. Called when a project opens.
    func materialize(project: Project, isLocalHost: (Host) -> Bool) {
        guard let checkout = project.activeRepo?.activeCheckout ?? project.allCheckouts.first,
              !checkout.path.isEmpty else { return }
        let all = (try? ShioModelContainer.shared.mainContext.fetch(FetchDescriptor<Skill>())) ?? []
        let pid = project.persistentModelID
        let applicable = all.filter { $0.enabled && ($0.isGlobal || $0.project?.persistentModelID == pid) }
        guard !applicable.isEmpty else { return }
        let items = applicable.map { Self.item(for: $0) }
        let base = "\(checkout.path)/.claude/skills"

        if let host = checkout.host, !isLocalHost(host) {
            let config = SSHClient.Configuration(
                host: host.hostname, port: host.port, username: host.username,
                authentication: .systemKeys, initialCols: 80, initialRows: 24)
            Task { await Self.writeRemote(base: base, items: items, config: config) }
        } else {
            let absBase = (base as NSString).expandingTildeInPath
            Task.detached(priority: .utility) {
                for it in items { Self.writeLocal(dir: "\(absBase)/\(it.dir)", body: it.body) }
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

    // MARK: - Remote (SSH), one round trip

    /// Write every applicable skill into `<base>/<dir>/SKILL.md` on the host in a
    /// single connection. Content is base64'd so arbitrary markdown can't break
    /// the shell. Best-effort: failures are swallowed (skills are advisory).
    nonisolated static func writeRemote(base: String, items: [Item], config: SSHClient.Configuration) async {
        let enabled = items.filter(\.enabled)
        guard !enabled.isEmpty else { return }
        let blocks = enabled.map { it -> String in
            let dir = q("\(base)/\(it.dir)")
            let b64 = Data(it.body.utf8).base64EncodedString()
            return "mkdir -p \(dir) && printf '%s' \(q(b64)) | base64 -d > \(dir)/SKILL.md"
        }
        let script = blocks.joined(separator: "\n") + "\n"
        let client = SSHClient(configuration: config)
        do {
            try await client.connect()
            _ = try? await client.exec(script, timeout: .seconds(10))
            await client.disconnect()
        } catch {
            await client.disconnect()
        }
    }

    private nonisolated static func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
