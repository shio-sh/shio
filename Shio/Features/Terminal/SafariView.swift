import SwiftUI
import SafariServices

/// Presents a URL in an in-app Safari view. Used for the away-from-laptop
/// case: a CLI (Claude Code's login, gh auth, etc.) prints an OAuth URL that
/// would otherwise open a browser on the *remote* machine you can't see — so
/// Shio surfaces it and opens it here on the phone, where you can authenticate
/// and copy any code back into the terminal.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
