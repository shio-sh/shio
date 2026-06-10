import Foundation
import Observation
import SwiftData

/// Stable key for a checkout's status — a deterministic function of (host, path)
/// so a card and a refresh agree without sharing object identity. Survives across
/// processes too (for the App Group disk cache in M5).
enum StatusKey {
    static func make(host: Host?, path: String) -> String {
        let h = host?.deviceID
            ?? host.map { "\($0.hostname):\($0.port):\($0.username)" }
            ?? "local"
        return "\(h)|\(path)"
    }
}

/// Holds the latest git status for every visible checkout. Cache-first: cards
/// render whatever's cached instantly; refreshes only ever *upgrade* it, and a
/// failed refresh never discards the last good status — so a sleeping machine
/// can't blank the grid. The analog of `AgentStateStore`.
///
/// Economy (App Group disk cache, warm-host gating, the visible-tab timer) is M5.
/// For now: refresh on appear + pull-to-refresh, capped fan-out, per-host timeouts.
@MainActor
@Observable
final class ProjectStatusStore {
    static let shared = ProjectStatusStore()
    private init() {}

    struct Cached: Equatable {
        var probe: GitProbe
        var fetchedAt: Date
    }

    /// Where a checkout lives, pre-resolved on the main actor so the fan-out
    /// never touches SwiftData off-main.
    struct Target {
        let key: String
        let path: String
        let hostKey: String        // groups checkouts that share one connection
        enum Location { case local; case remote(SSHClient.Configuration) }
        let location: Location
    }

    private(set) var statuses: [String: Cached] = [:]
    private(set) var isRefreshing = false
    private var inFlight: Task<Void, Never>?

    func status(forKey key: String) -> Cached? { statuses[key] }

    func status(forHost host: Host?, path: String) -> Cached? {
        statuses[StatusKey.make(host: host, path: path)]
    }

    /// Refresh the given checkouts. Cancels any in-flight refresh.
    func refresh(_ targets: [Target]) {
        inFlight?.cancel()
        guard !targets.isEmpty else { isRefreshing = false; return }
        isRefreshing = true
        inFlight = Task { [weak self] in await self?.run(targets) }
    }

    private func run(_ targets: [Target]) async {
        let groups = Array(Dictionary(grouping: targets, by: { $0.hostKey }).values)
        var pending = groups
        let cap = 4

        await withTaskGroup(of: [(String, GitProbe)].self) { group in
            var running = 0
            func addNext() {
                guard let g = pending.popLast() else { return }
                group.addTask { await Self.probeGroup(g) }
                running += 1
            }
            for _ in 0..<min(cap, groups.count) { addNext() }
            while running > 0 {
                guard let results = await group.next() else { break }
                running -= 1
                if !Task.isCancelled {
                    let now = Date()
                    for (key, probe) in results {
                        // Never discard a good status for a transient failure.
                        if case .ok = probe {
                            statuses[key] = Cached(probe: probe, fetchedAt: now)
                        } else if statuses[key]?.probe == nil || !isTransient(probe) {
                            statuses[key] = Cached(probe: probe, fetchedAt: now)
                        } else {
                            // keep the cached .ok payload; just note we tried
                        }
                    }
                }
                addNext()
            }
        }
        isRefreshing = false
    }

    /// Transient failures keep the last good status visible (stale-but-useful).
    private func isTransient(_ probe: GitProbe) -> Bool {
        switch probe {
        case .timedOut, .unreachable: return true
        default: return false
        }
    }

    private static func probeGroup(_ targets: [Target]) async -> [(String, GitProbe)] {
        guard let first = targets.first else { return [] }
        let paths = targets.map { $0.path }
        let byPath: [String: GitProbe]
        switch first.location {
        case .local:
            #if os(macOS)
            byPath = await GitStatusReader.probeLocal(paths: paths)
            #else
            byPath = [:]
            #endif
        case .remote(let config):
            byPath = await GitStatusReader.probeRemote(config: config, paths: paths)
        }
        return targets.compactMap { t in byPath[t.path].map { (t.key, $0) } }
    }
}

extension ProjectStatusStore {
    /// Build refresh targets from the visible projects. `isLocalHost` is the
    /// platform's "this is my own machine" test (Mac: MacSelfHost.isThisMac;
    /// iOS: always false). Main-actor — reads SwiftData.
    static func targets(for projects: [Project], isLocalHost: (Host) -> Bool) -> [Target] {
        var out: [Target] = []
        for project in projects {
            for checkout in project.allCheckouts where !checkout.path.isEmpty {
                let host = checkout.host
                let key = StatusKey.make(host: host, path: checkout.path)
                if let host, !isLocalHost(host) {
                    out.append(Target(key: key, path: checkout.path,
                                      hostKey: "\(host.persistentModelID)",
                                      location: .remote(statusConfig(for: host))))
                } else {
                    out.append(Target(key: key, path: checkout.path,
                                      hostKey: "local", location: .local))
                }
            }
        }
        return out
    }

    /// Auth for status probes: `.systemKeys` matches Mac's interactive sessions
    /// and degrades to the Shio key on iOS (no ~/.ssh there), so it works on both.
    private static func statusConfig(for host: Host) -> SSHClient.Configuration {
        SSHClient.Configuration(
            host: host.hostname, port: host.port, username: host.username,
            authentication: .systemKeys, initialCols: 80, initialRows: 24
        )
    }
}
