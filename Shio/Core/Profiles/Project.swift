import Foundation
import SwiftData

/// A logical project the user works on in Shio — project-first, not bound to one
/// machine. The same project can live on several machines as `ProjectCheckout`s
/// (the same repo on your Mac, a Pi, a VPS). The Projects command center lists
/// projects; opening one reaches its checkout on whichever machine you choose.
///
/// MIGRATION NOTE: the legacy single-host fields (`path`, `host`,
/// `persistenceModeOverrideRaw`) are KEPT during the additive project-first
/// migration so the CloudKit schema change stays lightweight and old clients keep
/// syncing. `ProjectMigration` backfills one `ProjectCheckout` per legacy project;
/// new reads go through `checkouts`/`activeCheckout`. The legacy columns are
/// dropped in a later schema version once all installs are migrated.
@Model
final class Project {

    // Every stored attribute is optional or defaulted (CloudKit requirement);
    // the initializer still sets real values. See Host for the migration note.

    /// Display name, usually the repo folder name.
    var name: String = ""

    /// Stable cross-device identity for dedup/merge — a normalized cloneURL when
    /// available, else a generated UUID string. Two projects with the same
    /// non-nil `identityKey` are "the same project."
    var identityKey: String?

    /// Freeform project-home notes scratchpad. Synced via CloudKit.
    var notes: String?

    /// If this project was created from a git URL, the URL to clone. The clone
    /// runs lazily on first open (only if the path doesn't already exist on the
    /// host), riding the host's existing git auth. nil for path-based projects.
    var cloneURL: String?

    var createdAt: Date = Date()
    var lastOpenedAt: Date?

    /// Per-machine checkouts of this project. Inverse of `ProjectCheckout.project`.
    /// `.nullify` (CloudKit forbids cascade); optional to-many (CloudKit).
    @Relationship(deleteRule: .nullify, inverse: \ProjectCheckout.project)
    var checkouts: [ProjectCheckout]?

    // MARK: - Legacy single-host fields (kept for additive migration; see note)

    /// Absolute path to the repo/folder on the host. LEGACY — read via the
    /// active checkout's `path` once migrated.
    var path: String = ""

    /// The machine this project lives on. LEGACY — read via a checkout's `host`.
    var host: Host?

    /// LEGACY per-project persistence override — now lives on `ProjectCheckout`.
    var persistenceModeOverrideRaw: String?

    var persistenceModeOverride: Host.PersistenceMode? {
        get { persistenceModeOverrideRaw.flatMap(Host.PersistenceMode.init(rawValue:)) }
        set { persistenceModeOverrideRaw = newValue?.rawValue }
    }

    init(name: String, path: String, host: Host? = nil) {
        self.name = name
        self.path = path
        self.host = host
        self.createdAt = .now
    }
}

extension Project {
    /// Create a project together with its first checkout, in one step — the
    /// project-first add path. Sets `identityKey`, inserts both into the context,
    /// and (during the migration window) keeps the legacy `path`/`host` populated
    /// so older clients still sync. New projects get a checkout immediately, so
    /// `activeCheckout` works the moment they're created (not just after the next
    /// launch's `ProjectMigration`).
    @discardableResult
    static func create(name: String, path: String, host: Host?, cloneURL: String? = nil,
                       in context: ModelContext) -> Project {
        let project = Project(name: name, path: path, host: host)
        project.cloneURL = cloneURL
        project.identityKey = cloneURL.flatMap { ProjectMigration.normalize(cloneURL: $0) } ?? UUID().uuidString
        context.insert(project)

        let checkout = ProjectCheckout(path: path, project: project, host: host)
        checkout.lastOpenedAt = .now
        context.insert(checkout)
        return project
    }

    /// The checkout the user most recently worked in, else the first available.
    /// The default target when opening a project that lives on several machines.
    var activeCheckout: ProjectCheckout? {
        (checkouts ?? []).sorted {
            ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
        }.first
    }

    /// This project's checkout on a specific host, if any.
    func checkout(on host: Host) -> ProjectCheckout? {
        (checkouts ?? []).first { $0.host?.persistentModelID == host.persistentModelID }
    }
}
