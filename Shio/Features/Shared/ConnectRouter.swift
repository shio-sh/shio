import Foundation
import SwiftData
import SwiftUI

/// Resolves every "connect to this host" request — an away-push tap, a widget
/// link, the Siri intent, Handoff, a `shio://connect` URL — into a live
/// session. The producers reference a host in different ways (the widget a
/// persistentModelID string, Siri a hostname, the Mac's away-signal its synced
/// deviceID), so resolution tries each stable identity in turn.
///
/// Routing happens only on explicit user intent (a tap), never on push
/// arrival — `RootView` is the single observer of `.shioConnectToHost`.
@Observable
@MainActor
final class ConnectRouter {
    static let shared = ConnectRouter()

    /// Drives RootView's terminal cover. Only raised when no TerminalScene is
    /// already on screen — if one is, switching `SessionStore.activeSession`
    /// is enough (the scene renders whatever's active).
    var showTerminal = false

    /// A `shio://pair` payload that arrived from outside the app (Camera-app
    /// scan, tapped link) — RootView presents the pairing sheet for it.
    var pendingPairing: PendingPairing?

    struct PendingPairing: Identifiable {
        let id = UUID()
        let scanned: String
    }

    private init() {}

    /// Entry point for `.shioConnectToHost`. `hostId` is required; `sessionId`
    /// (the tmux session named by an away-signal, e.g. "shio-myrepo") narrows
    /// the route to that project's session on the resolved host.
    func handle(userInfo: [AnyHashable: Any], context: ModelContext) {
        guard let ref = userInfo["hostId"] as? String, !ref.isEmpty,
              let host = resolveHost(ref: ref, context: context) else { return }

        var opened: SessionStore.Session?
        if let tmux = userInfo["sessionId"] as? String,
           let (project, checkout) = checkout(forTmuxSession: tmux, on: host) {
            // openOrCreate grounds the checkout's skills on the way in.
            opened = SessionStore.shared.openOrCreate(project: project, checkout: checkout)
        }
        if opened == nil {
            SessionStore.shared.openOrCreate(host: host)
        }
        if !SessionStore.shared.isTerminalPresented {
            showTerminal = true
        }
    }

    /// Try each identity the producers use: the synced per-device id (away-push
    /// from a Mac), the local persistentModelID string (widget links), the
    /// hostname (Siri / Handoff), then the display name as a last resort.
    private func resolveHost(ref: String, context: ModelContext) -> Host? {
        guard let hosts = try? context.fetch(FetchDescriptor<Host>()) else { return nil }
        if let h = hosts.first(where: { $0.deviceID == ref }) { return h }
        if let h = hosts.first(where: { "\($0.persistentModelID)" == ref }) { return h }
        if let h = hosts.first(where: { $0.hostname.caseInsensitiveCompare(ref) == .orderedSame }) { return h }
        return hosts.first { $0.name.caseInsensitiveCompare(ref) == .orderedSame }
    }

    /// Map a tmux session name back to the (project, checkout) it was created
    /// from — `shio-<scrubbed repo name>[-index]` — scoped to the resolved
    /// host. Indexed sessions route to the repo's primary session.
    private func checkout(forTmuxSession tmux: String, on host: Host) -> (Project, ProjectCheckout)? {
        guard tmux.hasPrefix("shio-") else { return nil }
        let stripped = String(tmux.dropFirst("shio-".count))
        for checkout in host.checkouts ?? [] {
            guard let repo = checkout.repo, let project = checkout.project else { continue }
            let scrubbed = TmuxResume.scrubName(repo.name)
            guard !scrubbed.isEmpty else { continue }
            if stripped == scrubbed || stripped.hasPrefix("\(scrubbed)-") {
                return (project, checkout)
            }
        }
        return nil
    }
}
