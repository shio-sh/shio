import SwiftUI
import SwiftData

@main
struct ShioApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(nil)  // follow system
                .tint(ShioColor.Text.primary)
        }
        .modelContainer(ShioModelContainer.shared)
    }
}
