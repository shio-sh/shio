import Foundation
import SwiftData

/// A project in Shio — an **org / workspace** that can span several repos (e.g.
/// the app, the landing site, and a worker all under one "Shio" project). The
/// hierarchy is `Project → Repo → ProjectCheckout(host, path)`: a project groups
/// repos; a repo is checked out on one or more machines.
///
/// MIGRATION NOTE: this evolved additively across two steps. The legacy
/// single-host fields (`path`, `host`, …) and the M1 direct `checkouts` are KEPT
/// so the CloudKit schema stays lightweight and older clients keep syncing.
/// `ProjectMigration` backfills a `Repo` per project and reparents checkouts to
/// it; reads go through `repos` / `activeRepo` / `activeCheckout`. The legacy
/// columns drop in a later schema version once all installs are migrated.
@Model
final class Project {

    // Every stored attribute is optional or defaulted (CloudKit requirement);
    // the initializer still sets real values. See Host for the migration note.

    /// Display name — the org/initiative (e.g. "Shio"), or the repo name for a
    /// single-repo project.
    var name: String = ""

    /// Freeform project-home notes scratchpad. Synced via CloudKit.
    var notes: String?

    var createdAt: Date = Date()
    var lastOpenedAt: Date?

    /// The repos under this project. Inverse of `Repo.project`. `.nullify`
    /// (CloudKit forbids cascade); optional to-many (CloudKit).
    @Relationship(deleteRule: .nullify, inverse: \Repo.project)
    var repos: [Repo]?

    // MARK: - Legacy fields (kept for additive migration; see note)

    /// LEGACY (M1) — identity now lives on `Repo`. Kept so old clients sync.
    var identityKey: String?

    /// LEGACY (M1) — clone URL now lives on `Repo`. Kept so old clients sync.
    var cloneURL: String?

    /// LEGACY (M1) — direct per-project checkouts, now reparented under `Repo`.
    @Relationship(deleteRule: .nullify, inverse: \ProjectCheckout.project)
    var checkouts: [ProjectCheckout]?

    // MARK: - Legacy single-host fields (M0; kept for additive migration)

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
    /// Create a project with one repo and that repo's first checkout, in one
    /// step — the add path. New projects get the full Project→Repo→Checkout chain
    /// immediately, so `activeRepo`/`activeCheckout` work the moment they're
    /// created (not just after the next launch's `ProjectMigration`). Legacy
    /// fields stay populated during the migration window so older clients sync.
    @discardableResult
    static func create(name: String, path: String, host: Host?, cloneURL: String? = nil,
                       in context: ModelContext) -> Project {
        let identity = cloneURL.flatMap { ProjectMigration.normalize(cloneURL: $0) } ?? UUID().uuidString

        let project = Project(name: name, path: path, host: host)
        project.cloneURL = cloneURL          // legacy (transition)
        project.identityKey = identity       // legacy (transition)
        context.insert(project)

        let repo = Repo(name: name, cloneURL: cloneURL, identityKey: identity, project: project)
        repo.lastOpenedAt = .now
        context.insert(repo)

        let checkout = ProjectCheckout(path: path, project: project, host: host)
        checkout.repo = repo
        checkout.lastOpenedAt = .now
        context.insert(checkout)
        return project
    }

    /// All repos under this project, most-recently-opened first.
    var sortedRepos: [Repo] {
        (repos ?? []).sorted {
            ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
        }
    }

    /// The repo the user most recently worked in, else the first.
    var activeRepo: Repo? { sortedRepos.first }

    /// Every checkout across every repo (for the machines line on a card). Falls
    /// back to the legacy direct checkouts before the migration runs.
    var allCheckouts: [ProjectCheckout] {
        let viaRepos = (repos ?? []).flatMap { $0.checkouts ?? [] }
        return viaRepos.isEmpty ? (checkouts ?? []) : viaRepos
    }

    /// The checkout to open by default — the active repo's active checkout.
    /// Falls back to a legacy direct checkout during the migration window.
    var activeCheckout: ProjectCheckout? {
        if let viaRepo = activeRepo?.activeCheckout { return viaRepo }
        return (checkouts ?? []).sorted {
            ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
        }.first
    }

    /// The effective clone URL of the active repo (transition: legacy field).
    var effectiveCloneURL: String? { activeRepo?.cloneURL ?? cloneURL }

    /// Add another repo to this project (the multi-repo path) with its first
    /// checkout, inserted into the context.
    @discardableResult
    func addRepo(name: String, path: String, host: Host?, cloneURL: String? = nil,
                 in context: ModelContext) -> Repo {
        let identity = cloneURL.flatMap { ProjectMigration.normalize(cloneURL: $0) } ?? UUID().uuidString
        let repo = Repo(name: name, cloneURL: cloneURL, identityKey: identity, project: self)
        repo.lastOpenedAt = .now
        context.insert(repo)

        let checkout = ProjectCheckout(path: path, project: self, host: host)
        checkout.repo = repo
        checkout.lastOpenedAt = .now
        context.insert(checkout)
        return repo
    }
}
