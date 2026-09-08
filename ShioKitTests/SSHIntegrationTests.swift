import Testing
import Foundation
import NIOCore
@testable import Shio

/// End-to-end tests against a REAL sshd (see `EphemeralSSHD`), covering the
/// paths the rest of the suite can only test as pure functions: the handshake,
/// auth, exec channels, host-key pinning, and tmux session continuity.
///
/// Everything else in ShioKitTests parses fixtures. These actually connect, so
/// they are the only coverage that would notice SwiftNIO SSH changing behaviour
/// under a version bump, or a refactor breaking the wire path while every
/// parser still passes.
///
/// The server is loopback-only and disposable; nothing here touches the user's
/// `~/.ssh`, system SSH config, or any real host. Each test provisions and tears
/// down its own server so failures can't leak state into the next one.
@Suite(.serialized)
struct SSHIntegrationTests {

    /// Skip (rather than fail) where a real server can't be stood up: no sshd,
    /// no usable key, no free port.
    static var available: Bool {
        EphemeralSSHD.sshdPath != nil && EphemeralSSHD.usableUserKey != nil
    }

    private func config(_ server: EphemeralSSHD) -> SSHClient.Configuration {
        SSHClient.Configuration(host: "127.0.0.1", port: server.port,
                                username: server.username, authentication: .systemKeys,
                                initialCols: 80, initialRows: 24)
    }

    /// Pins accumulate in UserDefaults keyed by host:port; drop ours so a rerun
    /// starts from trust-on-first-use rather than a stale pin.
    private func forgetPin(_ server: EphemeralSSHD) {
        ShioKnownHosts.forget("127.0.0.1:\(server.port)")
    }

    // MARK: - connect + exec

    @Test(.enabled(if: available))
    func connectsAndRunsACommand() async throws {
        guard let server = EphemeralSSHD.start() else {
            Issue.record("preconditions were met but the test server failed to start")
            return
        }
        defer { server.stop(); forgetPin(server) }

        let client = SSHClient(configuration: config(server))
        try await client.connect()
        let out = try await client.exec("echo shio-integration-ok")
        await client.disconnect()

        #expect(out.contains("shio-integration-ok"))
    }

    /// `ExecResult` is what callers use to tell "succeeded" from "produced some
    /// output" — so stdout, stderr and the exit status must stay separate.
    @Test(.enabled(if: available))
    func execSeparatesStreamsAndReportsExitStatus() async throws {
        guard let server = EphemeralSSHD.start() else {
            Issue.record("preconditions were met but the test server failed to start")
            return
        }
        defer { server.stop(); forgetPin(server) }

        let client = SSHClient(configuration: config(server))
        try await client.connect()
        let result = try await client.execWithStatus(
            posixScript: "echo to-stdout; echo to-stderr 1>&2; exit 7")
        await client.disconnect()

        #expect(result.stdout.contains("to-stdout"))
        #expect(!result.stdout.contains("to-stderr"))
        #expect(result.stderr.contains("to-stderr"))
        #expect(result.exitStatus == 7)
    }

    /// POSIX scripts travel base64'd into `sh` precisely so a login shell of any
    /// flavour can't reinterpret them. Quoting the payload is the risk.
    @Test(.enabled(if: available))
    func posixScriptSurvivesAwkwardQuoting() async throws {
        guard let server = EphemeralSSHD.start() else {
            Issue.record("preconditions were met but the test server failed to start")
            return
        }
        defer { server.stop(); forgetPin(server) }

        let client = SSHClient(configuration: config(server))
        try await client.connect()
        let out = try await client.exec(
            posixScript: "printf '%s\\n' \"it's \\\"quoted\\\" | and piped\"")
        await client.disconnect()

        #expect(out.contains("it's \"quoted\" | and piped"))
    }

    // MARK: - host key pinning

    @Test(.enabled(if: available))
    func pinsTheHostKeyOnFirstConnect() async throws {
        guard let server = EphemeralSSHD.start() else {
            Issue.record("preconditions were met but the test server failed to start")
            return
        }
        defer { server.stop(); forgetPin(server) }
        forgetPin(server)

        let hostPort = "127.0.0.1:\(server.port)"
        #expect(ShioKnownHosts.fingerprint(for: hostPort) == nil)

        let client = SSHClient(configuration: config(server))
        try await client.connect()
        await client.disconnect()

        #expect(ShioKnownHosts.fingerprint(for: hostPort) != nil,
                "a successful first connect must pin the host key")
    }

    /// The security-critical one. A pinned host whose key changes must be
    /// refused — this is the whole point of the pin, and until now nothing
    /// exercised it against a server that actually changed its identity.
    @Test(.enabled(if: available))
    func refusesAHostWhoseKeyChanged() async throws {
        guard let server = EphemeralSSHD.start() else {
            Issue.record("preconditions were met but the test server failed to start")
            return
        }
        defer { server.stop(); forgetPin(server) }
        forgetPin(server)

        let hostPort = "127.0.0.1:\(server.port)"

        let first = SSHClient(configuration: config(server))
        try await first.connect()
        await first.disconnect()
        let pinned = ShioKnownHosts.fingerprint(for: hostPort)
        #expect(pinned != nil)

        #expect(server.rotateHostKey(), "test server should restart with a new identity")

        var refused = false
        let second = SSHClient(configuration: config(server))
        do {
            try await second.connect()
            await second.disconnect()
        } catch {
            refused = true
        }
        #expect(refused, "a changed host key must refuse the connection, not connect anyway")
        #expect(ShioKnownHosts.fingerprint(for: hostPort) == pinned,
                "a refused connection must not silently re-pin the new key")
    }

    /// Forgetting the pin is what "Trust new key" does; the next connect should
    /// then succeed and pin the new identity.
    @Test(.enabled(if: available))
    func trustingANewKeyLetsTheNextConnectSucceed() async throws {
        guard let server = EphemeralSSHD.start() else {
            Issue.record("preconditions were met but the test server failed to start")
            return
        }
        defer { server.stop(); forgetPin(server) }
        forgetPin(server)

        let hostPort = "127.0.0.1:\(server.port)"
        let first = SSHClient(configuration: config(server))
        try await first.connect()
        await first.disconnect()
        let original = ShioKnownHosts.fingerprint(for: hostPort)

        #expect(server.rotateHostKey())
        ShioKnownHosts.forget(hostPort)          // the user chose to re-trust

        let second = SSHClient(configuration: config(server))
        try await second.connect()
        await second.disconnect()

        let updated = ShioKnownHosts.fingerprint(for: hostPort)
        #expect(updated != nil)
        #expect(updated != original, "re-trusting should pin the NEW key, not the old one")
    }

    // MARK: - tmux continuity (the cross-device promise)

    /// The product claim is that a session outlives the connection and can be
    /// reattached from somewhere else. This is that claim, minus the second
    /// device: create a session, drop the connection entirely, reconnect, and
    /// confirm the session and its state are still there.
    @Test(.enabled(if: available && tmuxPath != nil))
    func tmuxSessionOutlivesTheConnectionAndReattaches() async throws {
        guard let server = EphemeralSSHD.start(), let tmux = Self.tmuxPath else {
            Issue.record("preconditions were met but the test server or tmux was unavailable")
            return
        }
        defer { server.stop(); forgetPin(server) }

        let name = "shio-itest-\(UUID().uuidString.prefix(8))"
        let q = SSHClient.shellQuotedPath(tmux)

        let first = SSHClient(configuration: config(server))
        try await first.connect()
        // Detached session, then leave a marker in a file only it could write.
        _ = try await first.exec(posixScript: "\(q) new-session -d -s \(name)")
        _ = try await first.exec(
            posixScript: "\(q) send-keys -t \(name) 'echo alive > \(NSTemporaryDirectory())\(name).marker' Enter")
        await first.disconnect()

        // A whole new connection — nothing is shared with the first.
        let second = SSHClient(configuration: config(server))
        try await second.connect()
        let sessions = try await second.exec(posixScript: "\(q) list-sessions -F '#{session_name}' 2>/dev/null")
        let marker = try await second.exec(
            posixScript: "cat \(NSTemporaryDirectory())\(name).marker 2>/dev/null")
        _ = try await second.exec(posixScript: "\(q) kill-session -t \(name) 2>/dev/null; true")
        _ = try await second.exec(posixScript: "rm -f \(NSTemporaryDirectory())\(name).marker")
        await second.disconnect()

        #expect(sessions.contains(name), "the tmux session must survive the connection that made it")
        #expect(marker.contains("alive"), "work done in the session must persist across the reconnect")
    }

    /// `resumeCommand` is attach-or-create, so running it twice must land in the
    /// same session rather than spawning a second one.
    @Test(.enabled(if: available && tmuxPath != nil))
    func resumeCommandAttachesInsteadOfDuplicating() async throws {
        guard let server = EphemeralSSHD.start(), let tmux = Self.tmuxPath else {
            Issue.record("preconditions were met but the test server or tmux was unavailable")
            return
        }
        defer { server.stop(); forgetPin(server) }

        let host = "itest-\(UUID().uuidString.prefix(6))"
        let name = TmuxResume.sessionName(for: host)
        let q = SSHClient.shellQuotedPath(tmux)

        let client = SSHClient(configuration: config(server))
        try await client.connect()
        _ = try await client.exec(posixScript: "\(q) new-session -d -s \(name)")
        _ = try await client.exec(posixScript: "\(q) new-session -A -d -s \(name)")
        let count = try await client.exec(
            posixScript: "\(q) list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^\(name)$'")
        _ = try await client.exec(posixScript: "\(q) kill-session -t \(name) 2>/dev/null; true")
        await client.disconnect()

        #expect(count.trimmingCharacters(in: .whitespacesAndNewlines) == "1",
                "attach-or-create must not create a second session with the same name")
    }

    // MARK: - the git engine, end to end

    /// `GitStatusParseTests` proves the porcelain parser against fixtures. This
    /// proves the whole round trip: a real repo, real git, over a real SSH exec,
    /// parsed into a real probe.
    @Test(.enabled(if: available))
    func gitProbeReadsARealRepositoryOverSSH() async throws {
        guard let server = EphemeralSSHD.start() else {
            Issue.record("preconditions were met but the test server failed to start")
            return
        }
        defer { server.stop(); forgetPin(server) }

        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("shio-itest-repo-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: repo) }
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        let setup = """
        cd \(SSHClient.shellQuotedPath(repo.path)) || exit 1
        git init -q -b integration 2>/dev/null || { git init -q; git checkout -q -b integration; }
        git config user.email itest@shio.local
        git config user.name  itest
        echo committed > tracked.txt
        git add tracked.txt
        git commit -qm "first"
        echo dirty >> tracked.txt
        echo new > untracked.txt
        """
        let client = SSHClient(configuration: config(server))
        try await client.connect()
        let setupResult = try await client.execWithStatus(posixScript: setup, timeout: .seconds(30))
        await client.disconnect()
        #expect(setupResult.exitStatus == 0, "repo setup failed: \(setupResult.stderr)")

        let probes = await GitStatusReader.probeRemote(config: config(server), paths: [repo.path])
        forgetPin(server)

        guard case .ok(let status)? = probes[repo.path] else {
            Issue.record("expected a parsed status, got \(String(describing: probes[repo.path]))")
            return
        }
        #expect(status.head == .branch("integration"))
        #expect(!status.isClean, "one modified and one untracked file is not clean")
        #expect(status.dirtyCount == 2)
    }

    /// A path that isn't a git repository must come back as `notARepo`, not as a
    /// timeout or a silent success — the dashboard renders those differently.
    @Test(.enabled(if: available))
    func gitProbeReportsANonRepositoryHonestly() async throws {
        guard let server = EphemeralSSHD.start() else {
            Issue.record("preconditions were met but the test server failed to start")
            return
        }
        defer { server.stop(); forgetPin(server) }

        let plain = FileManager.default.temporaryDirectory
            .appendingPathComponent("shio-itest-plain-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: plain) }
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

        let probes = await GitStatusReader.probeRemote(config: config(server), paths: [plain.path])
        forgetPin(server)

        if case .notARepo? = probes[plain.path] {} else {
            Issue.record("expected .notARepo, got \(String(describing: probes[plain.path]))")
        }
    }

    /// tmux is frequently absent from a non-interactive SSH `PATH`, which is why
    /// the app resolves it explicitly; find it the same way for these tests.
    static let tmuxPath: String? = {
        for candidate in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }()
}
