import Foundation
import SwiftData

/// One-time, idempotent backfill from the legacy single-host `Project{host,path}`
/// shape to the project-first `Project` + `ProjectCheckout` model.
///
/// This runs in app code, NOT a `SchemaMigrationPlan`, on purpose: the store is
/// CloudKit-mirrored, so a migration plan would run per-device at first launch on
/// the new schema and create N duplicate checkouts as the same records sync in.
/// Instead we guard on the *synced* `checkouts` relationship — the first device
/// to migrate creates the checkout, it syncs, and every other device sees a
/// non-empty `checkouts` and skips. A reconciler collapses any duplicates created
/// in the narrow window before sync converges. The worst case is a transient
/// duplicate checkout the reconciler removes next launch — never data loss, never
/// a duplicated *logical* project (backfill attaches checkouts to the existing
/// project, it never creates new ones).
enum ProjectMigration {

    /// Run after the container loads (alongside `MacSelfHost.ensure`). Cheap and
    /// safe to call every launch — every pass no-ops when there's nothing to do.
    static func run(in context: ModelContext) {
        backfillCheckouts(in: context)   // M1: legacy project → one ProjectCheckout
        backfillRepos(in: context)       // M-repo: project → one Repo, reparent checkouts
        reconcileRepos(in: context)      // collapse race-duplicated repos first…
        reconcile(in: context)           // …then their (now merged) checkouts
        reconcileSkills(in: context)
    }

    /// Collapse duplicate Skills two devices created concurrently (an import
    /// run on both before sync converged): same dir, same scope = the same
    /// skill, and the duplicates would fight over one SKILL.md on disk. Keep
    /// the oldest, tie-broken on the synced UUID so every device deletes the
    /// same copy. Files are untouched — the winner owns the same dir.
    private static func reconcileSkills(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Skill>())) ?? []
        guard all.count > 1 else { return }
        var didChange = false
        var seen: [String: Skill] = [:]
        let ordered = all.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        for skill in ordered {
            let scope = skill.project.map { "\($0.persistentModelID)" } ?? "global"
            let key = "\(scope)|\(skill.dirName)"
            if seen[key] != nil {
                context.delete(skill)
                didChange = true
            } else {
                seen[key] = skill
            }
        }
        if didChange { try? context.save() }
    }

    /// Give every project that has no repos one `Repo` (carrying the project's
    /// identity), and reparent the project's direct checkouts onto it. Idempotent:
    /// the guard is the *synced* `repos` relationship, so the first device to
    /// migrate wins and the rest skip once it syncs.
    private static func backfillRepos(in context: ModelContext) {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var didChange = false

        for project in projects {
            guard (project.repos ?? []).isEmpty else { continue }
            let checkouts = project.checkouts ?? []
            // Nothing to hang a repo on yet (no checkout) → skip; backfillCheckouts
            // runs first, so a legacy project will have one by now.
            guard !checkouts.isEmpty || project.cloneURL != nil || !project.name.isEmpty else { continue }

            let identity = project.identityKey
                ?? project.cloneURL.flatMap { normalize(cloneURL: $0) }
                ?? UUID().uuidString
            let repo = Repo(name: project.name, cloneURL: project.cloneURL,
                            identityKey: identity, project: project)
            repo.lastOpenedAt = project.lastOpenedAt
            // createdAt stays "now" (the migration moment) on purpose: if two
            // devices race this backfill, their stamps differ, so the
            // reconciler's keep-the-oldest pick is deterministic on both.
            // Copying project.createdAt made the duplicates tie exactly.
            context.insert(repo)
            for checkout in checkouts { checkout.repo = repo }
            didChange = true
        }

        if didChange { try? context.save() }
    }

    /// Give every legacy project exactly one checkout derived from its host/path,
    /// and stamp an `identityKey`. Skips any project that already has a checkout.
    private static func backfillCheckouts(in context: ModelContext) {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var didChange = false

        for project in projects {
            // Idempotency: once a project has any checkout, never backfill it
            // again. This is the self-coordinating guard across synced devices.
            let alreadyMigrated = !(project.checkouts ?? []).isEmpty

            if project.identityKey == nil {
                project.identityKey = identity(for: project)
                didChange = true
            }

            guard !alreadyMigrated else { continue }
            guard let host = project.host, !project.path.isEmpty else { continue }

            let checkout = ProjectCheckout(path: project.path, project: project, host: host)
            checkout.persistenceModeOverrideRaw = project.persistenceModeOverrideRaw
            checkout.lastOpenedAt = project.lastOpenedAt
            // createdAt stays "now" — see backfillRepos: distinct stamps make
            // the duplicate-reconciler deterministic across racing devices.
            context.insert(checkout)
            didChange = true
        }

        if didChange { try? context.save() }
    }

    /// Collapse duplicate Repos a multi-device migration race produced — two
    /// devices that both ran `backfillRepos` before sync converged each made
    /// one, and the duplicate can hold (steal) half the project's checkouts.
    /// The loser's checkouts are merged onto the winner before it's deleted,
    /// so nothing is lost; the winner is the oldest, tie-broken on synced
    /// fields so every device picks the same one.
    private static func reconcileRepos(in context: ModelContext) {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var didChange = false

        for project in projects {
            let repos = project.repos ?? []
            guard repos.count > 1 else { continue }
            var seen: [String: Repo] = [:]
            let ordered = repos.sorted {
                ($0.createdAt, $0.identityKey ?? "", $0.name)
                    < ($1.createdAt, $1.identityKey ?? "", $1.name)
            }
            for repo in ordered {
                let key = repo.identityKey
                    ?? repo.cloneURL.flatMap { normalize(cloneURL: $0) }
                    ?? repo.name
                if let winner = seen[key] {
                    for checkout in repo.checkouts ?? [] { checkout.repo = winner }
                    context.delete(repo)
                    didChange = true
                } else {
                    seen[key] = repo
                }
            }
        }

        if didChange { try? context.save() }
    }

    private struct DupKey: Hashable {
        let host: PersistentIdentifier?
        let path: String
    }

    /// Collapse duplicate checkouts of the same (host, path) that a multi-device
    /// migration race may have produced; keep the oldest by `createdAt` (with a
    /// synced tiebreak so racing devices delete the same copy, not each other's).
    private static func reconcile(in context: ModelContext) {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var didChange = false

        for project in projects {
            let checkouts = project.allCheckouts
            guard checkouts.count > 1 else { continue }
            var seen: [DupKey: ProjectCheckout] = [:]
            let ordered = checkouts.sorted {
                ($0.createdAt, $0.lastOpenedAt ?? .distantPast)
                    < ($1.createdAt, $1.lastOpenedAt ?? .distantPast)
            }
            for c in ordered {
                let key = DupKey(host: c.host?.persistentModelID, path: c.path)
                if seen[key] == nil {
                    seen[key] = c
                } else {
                    context.delete(c) // duplicate — the older one is already kept
                    didChange = true
                }
            }
        }

        if didChange { try? context.save() }
    }

    /// Identity key: a normalized cloneURL when present, else a stable UUID.
    private static func identity(for project: Project) -> String {
        if let url = project.cloneURL, let norm = normalize(cloneURL: url) { return norm }
        return UUID().uuidString
    }

    /// Normalize a git clone URL so the https and ssh forms of the same repo
    /// match: `git@github.com:you/repo.git` and `https://github.com/you/repo.git`
    /// both become `github.com/you/repo`. Conservative on purpose — a wrong merge
    /// is worse than a missed one.
    static func normalize(cloneURL raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }

        if let range = s.range(of: "://") {
            // scheme://[user@]host/path
            s = String(s[range.upperBound...])
            if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        } else if let at = s.firstIndex(of: "@") {
            // scp-like: user@host:path → host/path
            let after = String(s[s.index(after: at)...])
            s = after.replacingOccurrences(of: ":", with: "/")
        }

        while s.hasSuffix("/") { s = String(s.dropLast()) }
        return s.isEmpty ? nil : s
    }
}
