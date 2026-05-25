import AppIntents
import SwiftData
import Foundation

/// App Intents entity that surfaces saved Hosts to Shortcuts, Siri, and
/// Spotlight. Pulled from SwiftData by hostname (which is unique enough for
/// MVP — Brick 11 will harden with stable IDs if collisions appear).
struct HostEntity: AppEntity, Identifiable {

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Mac")
    }

    static let defaultQuery = HostEntityQuery()

    var id: String          // hostname; doubles as the lookup key
    var name: String
    var hostname: String
    var username: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(username)@\(hostname)"
        )
    }
}

struct HostEntityQuery: EntityQuery {
    func entities(for identifiers: [HostEntity.ID]) async throws -> [HostEntity] {
        try await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HostEntity] {
        try await all()
    }

    @MainActor
    private func all() async throws -> [HostEntity] {
        let context = ModelContext(ShioModelContainer.shared)
        let hosts = try context.fetch(FetchDescriptor<Host>())
        return hosts.map { host in
            HostEntity(
                id: host.hostname,
                name: host.name,
                hostname: host.hostname,
                username: host.username
            )
        }
    }
}
