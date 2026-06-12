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
    private init() { loadDiskCache() }

    struct Cached: Codable, Equatable {
        var probe: GitProbe
        var fetchedAt: Date
    }

    /// Last-known-good lives in the App Group so the dashboard paints the moment
    /// it appears — branch, ahead/behind, dirty counts — before a single byte of
    /// SSH. A refresh then upgrades it in place. Only `.ok` probes are persisted
    /// (we never want to cold-launch into a stale failure), and entries older
    /// than a week are dropped on load.
    private static let cacheURL: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: ShioModelContainer.appGroup)?
        .appendingPathComponent("git-status-cache.json")

    private func loadDiskCache() {
        guard let url = Self.cacheURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Cached].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        statuses = decoded.filter { $0.value.fetchedAt > cutoff }
    }

    private func saveDiskCache() {
        guard let url = Self.cacheURL else { return }
        let okOnly = statuses.filter { if case .ok = $0.value.probe { return true } else { return false } }
        guard let data = try? JSONEncoder().encode(okOnly) else { return }
        Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
    }

    /// A cached status counts as stale once it's older than this; surfaces decide
    /// how loudly to say so (a dimmed dot, a "·· " prefix).
    func isStale(_ cached: Cached, maxAge: TimeInterval = 90) -> Bool {
        Date().timeIntervalSince(cached.fetchedAt) > maxAge
    }

    /// Where a checkout lives, pre-resolved on the main actor so the fan-out
    /// never touches SwiftData off-main.
    struct Target {
        let key: String
        let path: String
        let hostKey: String        // groups checkouts that share one connection
        enum Location { case local; case remote(SSHClient.Configuration) }
        let location: Location
        /// The Host model behind a remote target, so a successful probe can
        /// stamp `lastConnectedAt` (the warm-gating signal) back on it.
        var hostID: PersistentIdentifier? = nil
    }

    private(set) var statuses: [String: Cached] = [:]
    /// Remote agents detected during the status fetch, keyed by host then tmux
    /// session name (`shio-<scrubbed repo>`). Local agents come from the Mac's
    /// own `MacProjectAgentMonitor`; this covers machines you aren't viewing.
    private(set) var remoteAgents: [String: [String: AgentSnapshot]] = [:]
    private(set) var isRefreshing = false
    /// Checkout keys currently being probed — a new refresh skips these
    /// instead of cancelling the work (the old cancel-everything behavior let
    /// the narrow warm-only timer kill a full on-appear refresh and silently
    /// drop the cold-host results it was about to deliver).
    private var inFlightKeys: Set<String> = []
    private var activeRefreshes = 0

    func status(forKey key: String) -> Cached? { statuses[key] }

    func status(forHost host: Host?, path: String) -> Cached? {
        statuses[StatusKey.make(host: host, path: path)]
    }

    /// A remote agent for a repo by name on a given host, if one was detected.
    /// Indexed sessions (`shio-<repo>-2`, a second terminal on the same repo)
    /// match by prefix; one that needs you wins over one that's merely running.
    func remoteAgent(host: Host, repoName: String) -> AgentSnapshot? {
        guard let byTmux = remoteAgents["\(host.persistentModelID)"] else { return nil }
        let base = "shio-\(TmuxResume.scrubName(repoName))"
        if let exact = byTmux[base] { return exact }
        let indexed = byTmux.filter { $0.key.hasPrefix("\(base)-") }.map(\.value)
        return indexed.first { $0.activity == .waiting } ?? indexed.first
    }

    /// Open PRs per checkout (via the machine's `gh`), keyed like `statuses`.
    private(set) var prs: [String: [PullRequest]] = [:]
    private var prTask: Task<Void, Never>?

    func prList(forHost host: Host?, path: String) -> [PullRequest] {
        prs[StatusKey.make(host: host, path: path)] ?? []
    }

    /// Fetch open PRs for the given checkouts (rides each machine's `gh`).
    /// Separate from the git refresh — `gh` is slower, so it never blocks the
    /// status fan-out. Cheap and advisory; failures just yield no PRs.
    func refreshPRs(_ targets: [Target]) {
        prTask?.cancel()
        guard !targets.isEmpty else { return }
        prTask = Task { [weak self] in await self?.runPRs(targets) }
    }

    private func runPRs(_ targets: [Target]) async {
        await withTaskGroup(of: (String, [PullRequest]).self) { group in
            let cap = 4
            var pending = targets
            var running = 0
            func addNext() {
                guard let t = pending.popLast() else { return }
                group.addTask { (t.key, await Self.fetchPRs(t)) }
                running += 1
            }
            for _ in 0..<min(cap, targets.count) { addNext() }
            while running > 0 {
                guard let (key, list) = await group.next() else { break }
                running -= 1
                if !Task.isCancelled { prs[key] = list }
                addNext()
            }
        }
    }

    private static func fetchPRs(_ t: Target) async -> [PullRequest] {
        switch t.location {
        case .local:
            #if os(macOS)
            return await GitHubReader.prsLocal(path: t.path)
            #else
            return []
            #endif
        case .remote(let config):
            return await GitHubReader.prsRemote(config: config, path: t.path)
        }
    }

    /// Refresh the given checkouts. Targets already being probed are skipped
    /// (their in-flight result is on the way); everything else fans out
    /// concurrently with whatever is running.
    func refresh(_ targets: [Target]) {
        let fresh = targets.filter { !inFlightKeys.contains($0.key) }
        guard !fresh.isEmpty else { return }
        for t in fresh { inFlightKeys.insert(t.key) }
        isRefreshing = true
        activeRefreshes += 1
        Task { [weak self] in
            await self?.run(fresh)
            guard let self else { return }
            for t in fresh { self.inFlightKeys.remove(t.key) }
            self.activeRefreshes -= 1
            if self.activeRefreshes == 0 { self.isRefreshing = false }
        }
    }

    private func run(_ targets: [Target]) async {
        let groups = Array(Dictionary(grouping: targets, by: { $0.hostKey }).values)
        var pending = groups
        let cap = 4

        await withTaskGroup(of: GroupResult.self) { group in
            var running = 0
            func addNext() {
                guard let g = pending.popLast() else { return }
                group.addTask { await Self.probeGroup(g) }
                running += 1
            }
            for _ in 0..<min(cap, groups.count) { addNext() }
            while running > 0 {
                guard let result = await group.next() else { break }
                running -= 1
                if !Task.isCancelled {
                    let now = Date()
                    if let hostKey = result.hostKey {
                        // Replace so a genuinely-finished agent clears — but
                        // not when the whole probe failed (a transient timeout
                        // must not wipe a real needs-you signal while the git
                        // statuses next to it are kept).
                        let probeFailed = !result.git.isEmpty
                            && result.git.allSatisfy { isTransient($0.1) }
                        if !probeFailed {
                            remoteAgents[hostKey] = result.agents
                        }
                    }
                    // A host that answered a probe is awake — stamp it warm so
                    // the timer refresh keeps including it. (Without this, a
                    // device that never opens terminals to a host — or iOS
                    // before its first session — reads it as permanently
                    // asleep and the warmOnly timer skips it forever.)
                    if let hostID = result.hostID,
                       result.git.contains(where: { if case .ok = $0.1 { return true } else { return false } }),
                       let host = ShioModelContainer.shared.mainContext.model(for: hostID) as? Host {
                        host.lastConnectedAt = now
                    }
                    for (key, probe) in result.git {
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
        if !Task.isCancelled { saveDiskCache() }
    }

    /// Transient failures keep the last good status visible (stale-but-useful).
    private func isTransient(_ probe: GitProbe) -> Bool {
        switch probe {
        case .timedOut, .unreachable: return true
        default: return false
        }
    }

    /// Result of probing one host's group: git per checkout, plus any remote
    /// agents (nil hostKey = the local group, which has no remote agents).
    private struct GroupResult {
        var git: [(String, GitProbe)]
        var hostKey: String?
        var hostID: PersistentIdentifier?
        var agents: [String: AgentSnapshot]
    }

    private static func probeGroup(_ targets: [Target]) async -> GroupResult {
        guard let first = targets.first else { return GroupResult(git: [], hostKey: nil, hostID: nil, agents: [:]) }
        let paths = targets.map { $0.path }
        let byPath: [String: GitProbe]
        var agents: [String: AgentSnapshot] = [:]
        var hostKey: String? = nil
        switch first.location {
        case .local:
            #if os(macOS)
            byPath = await GitStatusReader.probeLocal(paths: paths)
            #else
            byPath = [:]
            #endif
        case .remote(let config):
            let r = await GitStatusReader.probeRemoteWithAgents(config: config, paths: paths)
            byPath = r.git
            agents = r.agents
            hostKey = first.hostKey
        }
        let git = targets.compactMap { t in byPath[t.path].map { (t.key, $0) } }
        return GroupResult(git: git, hostKey: hostKey, hostID: first.hostID, agents: agents)
    }
}

extension ProjectStatusStore {
    /// Build refresh targets from the visible projects. `isLocalHost` is the
    /// platform's "this is my own machine" test (Mac: MacSelfHost.isThisMac;
    /// iOS: always false). Main-actor — reads SwiftData.
    /// `warmOnly` skips remote machines that haven't been reached recently — so a
    /// background/timer refresh never wakes a sleeping Pi every few seconds. The
    /// local machine and on-appear/manual refreshes always go through.
    static func targets(for projects: [Project], isLocalHost: (Host) -> Bool,
                        warmOnly: Bool = false) -> [Target] {
        var out: [Target] = []
        for project in projects {
            for checkout in project.allCheckouts where !checkout.path.isEmpty {
                let host = checkout.host
                let key = StatusKey.make(host: host, path: checkout.path)
                if let host, !isLocalHost(host) {
                    if warmOnly && !isWarm(host) { continue }
                    out.append(Target(key: key, path: checkout.path,
                                      hostKey: "\(host.persistentModelID)",
                                      location: .remote(statusConfig(for: host)),
                                      hostID: host.persistentModelID))
                } else {
                    out.append(Target(key: key, path: checkout.path,
                                      hostKey: "local", location: .local))
                }
            }
        }
        return out
    }

    /// A machine is "warm" if it was connected in the last 10 minutes — a cheap
    /// proxy for "awake and reachable" without a live probe.
    private static func isWarm(_ host: Host) -> Bool {
        guard let last = host.lastConnectedAt else { return false }
        return last.timeIntervalSinceNow > -600
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
