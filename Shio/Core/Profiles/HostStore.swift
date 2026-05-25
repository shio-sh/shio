import Foundation
import SwiftData

/// Centralized SwiftData container. The app and extensions share this via the
/// App Group so the widget and Live Activity can read the same hosts.
enum ShioModelContainer {
    static let appGroup = "group.sh.shio.app"

    static let shared: ModelContainer = {
        do {
            let schema = Schema([Host.self])
            // App Group container URL so extensions can read the same store.
            let groupURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
                ?? URL.documentsDirectory
            let storeURL = groupURL.appendingPathComponent("shio.sqlite")
            let config = ModelConfiguration(schema: schema, url: storeURL)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
