import Foundation
import SwiftData

/// A **Skill** — one vendor-neutral rule the terminal agents follow (à la
/// chops.md): "swift-style", "no comments unless asked", "commit-haiku". The
/// library is universal by default and tweakable per project.
///
/// Scope is the `project` relationship: **nil = global** (applies to every
/// project); **set = project-scoped** (only that project, layered on top of the
/// enabled globals). One model, two scopes — the dashboard shows globals ∪ the
/// project's own. CloudKit-valid: every attribute defaulted, the relationship
/// optional with `.nullify`, so it syncs across the user's devices.
@Model
final class Skill {
    var id: UUID = UUID()
    var name: String = ""
    /// One-line summary written as the SKILL.md frontmatter `description:`. This
    /// is what an agent (e.g. Claude Code) uses to decide WHEN to load the skill
    /// — skills are progressively disclosed, so without a good description the
    /// rule barely fires. Named `skillDescription` to avoid shadowing
    /// `CustomStringConvertible.description`.
    var skillDescription: String = ""
    /// The rule itself (markdown) — what the agent is told to follow.
    var content: String = ""
    /// Library on/off. A disabled global stops applying everywhere.
    var enabled: Bool = true
    var createdAt: Date = Date.now

    /// nil = global/universal; set = scoped to this one project. The inverse
    /// (`Project.skills`) is declared on Project — CloudKit requires it.
    var project: Project?

    init(name: String, skillDescription: String = "", content: String = "",
         enabled: Bool = true, project: Project? = nil) {
        self.id = UUID()
        self.name = name
        self.skillDescription = skillDescription
        self.content = content
        self.enabled = enabled
        self.createdAt = .now
        self.project = project
    }

    var isGlobal: Bool { project == nil }

    /// Filesystem-safe directory name for this skill (the SKILL.md lives in
    /// `<base>/<dirName>/SKILL.md`). The frontmatter keeps the original `name`.
    var dirName: String {
        Self.dirName(for: name) ?? "skill-\(id.uuidString.prefix(8))"
    }

    /// The dir a given display name would map to (nil when nothing survives
    /// scrubbing). Exposed so the editor can check for collisions *before*
    /// saving — two skills sharing a dir clobber and delete each other's file.
    static func dirName(for name: String) -> String? {
        let lowered = name.lowercased()
        let mapped = lowered.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "-"
        }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? nil : collapsed
    }
}
