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
    /// The rule itself (markdown) — what the agent is told to follow.
    var content: String = ""
    /// Library on/off. A disabled global stops applying everywhere.
    var enabled: Bool = true
    var createdAt: Date = Date.now

    /// nil = global/universal; set = scoped to this one project. The inverse
    /// (`Project.skills`) is declared on Project — CloudKit requires it.
    var project: Project?

    init(name: String, content: String = "", enabled: Bool = true, project: Project? = nil) {
        self.id = UUID()
        self.name = name
        self.content = content
        self.enabled = enabled
        self.createdAt = .now
        self.project = project
    }

    var isGlobal: Bool { project == nil }
}
