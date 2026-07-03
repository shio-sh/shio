import Foundation
import Network
import AppKit

/// ONE network/wake watcher for every SSH pane on the Mac. A Mac holds many
/// tabs at once — per-session `NWPathMonitor`s would be N copies of the same
/// signal — so sessions register here and the monitor fans events out:
///
/// - network returned while a session is mid-backoff → jump the queue, retry now
/// - primary interface flipped (Wi-Fi ↔ wired) while connected → the old
///   socket is dead even though it hasn't timed out; force-reconnect
/// - Mac woke from sleep / app became active → sockets died while the state
///   still says connected; verify transports and recover in place
///
/// tmux reattach makes every recovery lossless.
@MainActor
final class MacNetworkMonitor {
    static let shared = MacNetworkMonitor()

    private struct WeakSession { weak var session: MacSSHSession? }
    private var sessions: [WeakSession] = []

    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "sh.shio.mac.path")
    private var lastSatisfied = true
    private var lastPrimaryInterface: NWInterface.InterfaceType?
    private var started = false

    private init() {}

    /// Sessions register on init; storage is weak so closed tabs just fall out.
    func register(_ session: MacSSHSession) {
        start()
        sessions.removeAll { $0.session == nil }
        sessions.append(WeakSession(session: session))
    }

    private var live: [MacSSHSession] { sessions.compactMap(\.session) }

    private func start() {
        guard !started else { return }
        started = true

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = (path.status == .satisfied)
            let primary = Self.primaryInterface(of: path)
            Task { @MainActor [weak self] in
                self?.pathChanged(satisfied: satisfied, primary: primary)
            }
        }
        pathMonitor.start(queue: queue)

        // Sleep/wake lives on NSWorkspace's center; app activation on the
        // default center. Both funnel into the same recovery sweep.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in MacNetworkMonitor.shared.recoverAll() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in MacNetworkMonitor.shared.recoverAll() }
        }
    }

    private func pathChanged(satisfied: Bool, primary: NWInterface.InterfaceType?) {
        let wasSatisfied = lastSatisfied
        let previousPrimary = lastPrimaryInterface
        lastSatisfied = satisfied
        lastPrimaryInterface = primary

        if !wasSatisfied, satisfied {
            for s in live { s.networkReturned() }
            return
        }
        if satisfied, let previousPrimary, let primary, previousPrimary != primary {
            for s in live { s.interfaceSwitched() }
        }
    }

    private func recoverAll() {
        for s in live { s.recoverIfNeeded() }
    }

    /// The interface a path is primarily using, in priority order. Pure, so
    /// it's safe to call from the nonisolated path-monitor callback.
    private nonisolated static func primaryInterface(of path: NWPath) -> NWInterface.InterfaceType? {
        for type in [NWInterface.InterfaceType.wifi, .wiredEthernet, .cellular] where path.usesInterfaceType(type) {
            return type
        }
        return path.availableInterfaces.first?.type
    }
}
