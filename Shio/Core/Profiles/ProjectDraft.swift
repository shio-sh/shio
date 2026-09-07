import Foundation
import SwiftData

/// An in-progress new project, assembled in the create form and committed in
/// one save. Shared by the iOS and Mac forms so they behave identically: a name
/// + logo + context (memory), and any number of repos across machines.
struct ProjectDraft {
    var name: String = ""
    /// Memory / context — what this project is, conventions, links the agents
    /// should read. Stored as the project's `notes`.
    var memory: String = ""
    var imageData: Data?
    var repos: [RepoSpec] = []

    var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// One repo to create under the project: where it lives (machine + path) and,
/// if cloned, the URL. `hostID == nil` means the local machine (resolved at
/// create time, since "This Mac" has no stable id until `MacSelfHost.ensure`).
struct RepoSpec: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var path: String
    var hostID: PersistentIdentifier?
    var cloneURL: String?
    /// Display label for the machine, shown in the repos list.
    var machineLabel: String
}

extension Project {
    /// Build a project + all its repos from a draft, in one save. `resolveHost`
    /// maps a spec's `hostID` to a `Host` (platform-specific: the Mac form
    /// turns `nil` into `MacSelfHost`, iOS always has a real id).
    @discardableResult
    @MainActor
    static func build(from draft: ProjectDraft,
                      resolveHost: (PersistentIdentifier?) -> Host?,
                      in context: ModelContext) -> Project {
        let first = draft.repos.first
        let project = Project(name: draft.name.trimmingCharacters(in: .whitespaces),
                              path: first?.path ?? "",
                              host: first.flatMap { resolveHost($0.hostID) })
        let memo = draft.memory.trimmingCharacters(in: .whitespacesAndNewlines)
        project.notes = memo.isEmpty ? nil : memo
        project.imageData = draft.imageData
        context.insert(project)

        for spec in draft.repos {
            project.addRepo(name: spec.name, path: spec.path,
                            host: resolveHost(spec.hostID), cloneURL: spec.cloneURL, in: context)
        }
        project.lastOpenedAt = .now
        try? context.save()
        return project
    }
}
