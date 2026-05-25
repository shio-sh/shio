import AppIntents

/// Surfaces the intents in the Shortcuts app and Spotlight automatically.
struct ShioAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectToHostIntent(),
            phrases: [
                "Connect to \(\.$host) in \(.applicationName)",
                "Open my Mac in \(.applicationName)",
            ],
            shortTitle: "Connect to Mac",
            systemImageName: "desktopcomputer"
        )
        AppShortcut(
            intent: RunCommandIntent(),
            phrases: [
                "Run a command on \(\.$host) with \(.applicationName)",
            ],
            shortTitle: "Run Command",
            systemImageName: "terminal"
        )
    }
}
