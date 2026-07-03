import Foundation
import SwiftData

/// A git repository that belongs to a `Project` (an org/workspace can span
/// several repos — e.g. the app, the landing site, and a worker all under one
/// project). A `Repo` is checked out on one or more machines as `ProjectCheckout`s.
///
/// This is the middle level of `Project → Repo → Checkout`. Identity (cloneURL /
/// identityKey) lives here, not on the project, because identity is a property of
/// the repo, not the initiative.
///
/// CloudKit constraints (see Host): every attribute optional/defaulted; to-many
/// optional; `.nullify` everywhere; explicit inverses on the parents.
@Model
final class Repo {

    /// Display name, usually the repo folder name.
    var name: String = ""

    /// Stable cross-device identity — a normalized cloneURL when available, else
    /// a generated UUID string. Two repos with the same non-nil `identityKey` are
    /// "the same repo."
    var identityKey: String?

    /// If created from a git URL, the URL to clone (lazily, on first open).
    var cloneURL: String?

    var createdAt: Date = Date()
    var lastOpenedAt: Date?

    /// The org/workspace this repo belongs to. Inverse on `Project.repos`.
    var project: Project?

    /// Per-machine checkouts of this repo. Inverse of `ProjectCheckout.repo`.
    @Relationship(deleteRule: .nullify, inverse: \ProjectCheckout.repo)
    var checkouts: [ProjectCheckout]?

    init(name: String, cloneURL: String? = nil, identityKey: String? = nil, project: Project? = nil) {
        self.name = name
        self.cloneURL = cloneURL
        self.identityKey = identityKey
        self.project = project
        self.createdAt = .now
    }
}

extension Repo {
    /// The checkout most recently worked in, else the first available.
    ///
    /// On iOS, checkouts with a host always outrank host-less ones: a nil-host
    /// checkout is a legacy Mac-local one — real on that Mac, but this device
    /// can't open it (no local shell), so letting recency pick it makes the
    /// repo tap a silent no-op while a perfectly reachable checkout hides
    /// behind it. The Mac keeps pure recency (nil host = this mac is real
    /// there, and MacSelfHost adopts provable ones anyway).
    var activeCheckout: ProjectCheckout? {
        let byRecency = (checkouts ?? []).sorted {
            ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
        }
        #if os(macOS)
        return byRecency.first
        #else
        return byRecency.first { $0.host != nil } ?? byRecency.first
        #endif
    }

    func checkout(on host: Host) -> ProjectCheckout? {
        (checkouts ?? []).first { $0.host?.persistentModelID == host.persistentModelID }
    }
}
