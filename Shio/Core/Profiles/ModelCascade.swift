import Foundation
import SwiftData

/// Manual delete cascades. Every relationship in the schema is `.nullify`
/// (CloudKit forbids `.cascade`), so a bare `context.delete` on a parent
/// silently orphans its children — records that sync forever and surface as
/// dead rows: checkouts whose host is gone masquerading as "This Mac",
/// project-scoped skills promoted to global. Delete paths call these.
enum ModelCascade {

    /// Remove a machine and the checkouts that only make sense on it.
    @MainActor
    static func delete(host: Host, context: ModelContext) {
        for checkout in host.checkouts ?? [] {
            context.delete(checkout)
        }
        context.delete(host)
    }

    /// Remove a project with its repos, checkouts, and project-scoped skills.
    /// Skills are retired first (files cleaned up + tombstoned) — `.nullify`
    /// would otherwise turn them into GLOBAL skills and fan them out to every
    /// machine on the next sync.
    @MainActor
    static func delete(project: Project, context: ModelContext, isLocalHost: (Host) -> Bool) {
        for skill in project.skills ?? [] {
            SkillMaterializer.shared.retire(skill, isLocalHost: isLocalHost)
            context.delete(skill)
        }
        for checkout in project.allCheckouts {
            context.delete(checkout)
        }
        for repo in project.repos ?? [] {
            context.delete(repo)
        }
        context.delete(project)
    }
}
