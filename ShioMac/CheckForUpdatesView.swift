import SwiftUI
import Combine
import Sparkle

/// Bridges Sparkle's `SPUUpdater` to a SwiftUI menu command. The menu item is
/// enabled only when a manual check is actually possible (nothing in flight),
/// mirroring Sparkle's own AppKit behavior. Used by the "Check for Updates…"
/// item in the app menu; automatic background checks run independently.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
