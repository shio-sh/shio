import Foundation
import SwiftData

/// A repo or folder on a `Host` that the user has chosen to work on in Shio.
/// Projects are the home screen; each holds one or more terminal sessions.
/// (Session wiring and repo selection land in Phase 2.)
@Model
final class Project {

    // Every stored attribute is optional or defaulted (CloudKit requirement);
    // the initializer still sets real values. See Host for the migration note.

    /// Display name, usually the repo folder name.
    var name: String = ""

    /// Absolute path to the repo/folder on the host (e.g. /Users/amrith/shio.sh).
    var path: String = ""

    /// If this project was created from a git URL, the URL to clone. The clone
    /// runs lazily on first open (only if `path` doesn't already exist on the
    /// host), riding the host's existing git auth. nil for path-based projects.
    var cloneURL: String?

    /// The machine this project lives on.
    var host: Host?

    /// Optional per-project override of the host's persistence mode.
    var persistenceModeOverrideRaw: String?

    var persistenceModeOverride: Host.PersistenceMode? {
        get { persistenceModeOverrideRaw.flatMap(Host.PersistenceMode.init(rawValue:)) }
        set { persistenceModeOverrideRaw = newValue?.rawValue }
    }

    var createdAt: Date = Date()
    var lastOpenedAt: Date?

    init(name: String, path: String, host: Host? = nil) {
        self.name = name
        self.path = path
        self.host = host
        self.createdAt = .now
    }
}
