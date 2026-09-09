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

    /// Remove one repo and the checkouts that place it on machines.
    ///
    /// Nothing on disk is touched — a checkout is only Shio's note of where a
    /// folder lives. Until now there was no caller for this at all: a repo
    /// could be added on any platform and removed on none, so a mistyped path
    /// or an abandoned experiment was permanent.
    @MainActor
    static func delete(repo: Repo, context: ModelContext) {
        for checkout in repo.checkouts ?? [] {
            context.delete(checkout)
        }
        context.delete(repo)
    }

    /// Remove a project with its repos and checkouts.
    @MainActor
    static func delete(project: Project, context: ModelContext) {
        for checkout in project.allCheckouts {
            context.delete(checkout)
        }
        for repo in project.repos ?? [] {
            context.delete(repo)
        }
        context.delete(project)
    }
}
