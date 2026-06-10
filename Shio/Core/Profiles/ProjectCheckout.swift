import Foundation
import SwiftData

/// One machine-specific checkout of a logical `Project`: the repo/folder at
/// `path` on a particular `Host`. A project can have several checkouts — the
/// same repo on your Mac, a Pi, and a VPS — because Shio is project-first: the
/// Projects command center lists the work, and lets you reach it on any machine
/// it lives on.
///
/// CloudKit constraints (see `Host` for the full note): every attribute is
/// optional or defaulted; both relationships are optional to-one with their
/// inverses declared on the parents (`Project.checkouts`, `Host.checkouts`);
/// `.nullify` everywhere (CloudKit forbids cascade).
@Model
final class ProjectCheckout {

    /// Absolute path to the repo/folder on its host (e.g. /home/pi/shio).
    var path: String = ""

    /// Optional per-checkout override of the host's persistence mode. Persistence
    /// is a property of *how you reach a machine*, so it lives on the checkout
    /// rather than the logical project.
    var persistenceModeOverrideRaw: String?

    var persistenceModeOverride: Host.PersistenceMode? {
        get { persistenceModeOverrideRaw.flatMap(Host.PersistenceMode.init(rawValue:)) }
        set { persistenceModeOverrideRaw = newValue?.rawValue }
    }

    /// Per-checkout last-opened — drives "active checkout" default selection.
    var lastOpenedAt: Date?
    var createdAt: Date = Date()

    /// The repo this checkout is of. Inverse declared on `Repo.checkouts`. The
    /// project-first owner since the Project→Repo→Checkout refactor.
    var repo: Repo?

    /// LEGACY (M1) owning project — checkouts now hang off `Repo`. Kept during
    /// the additive migration so older clients keep syncing; reach the project via
    /// `repo?.project`.
    var project: Project?

    /// The machine this checkout lives on. Inverse declared on `Host.checkouts`.
    var host: Host?

    init(path: String, project: Project? = nil, host: Host? = nil) {
        self.path = path
        self.project = project
        self.host = host
        self.createdAt = .now
    }
}
