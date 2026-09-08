import Foundation

/// A throwaway `sshd` on a loopback high port, for tests that need a REAL SSH
/// server rather than a mock.
///
/// Everything it needs lives in one temp directory that is deleted on teardown:
/// its own host key, its own `authorized_keys`, its own config. It never reads
/// or writes the user's `~/.ssh`, never touches system SSH config, and never
/// listens on anything but 127.0.0.1.
///
/// Auth is the user's existing `~/.ssh/id_ed25519` *public* key, copied into the
/// throwaway `authorized_keys`. That lets `SSHClient` authenticate with
/// `.systemKeys` — the same code path the Mac app uses against real hosts —
/// without provisioning anything on the machine.
///
/// `start()` returns nil when the environment can't support it (no sshd, no
/// usable key, no free port). Tests skip rather than fail in that case, so a
/// machine without these preconditions doesn't turn into a red suite.
final class EphemeralSSHD {

    let port: Int
    let username: String
    private let dir: URL
    private var process: Process?

    private init(port: Int, username: String, dir: URL) {
        self.port = port
        self.username = username
        self.dir = dir
    }

    /// The user's public key, which we authorize. Nil (→ skip) if absent, or if
    /// the matching private key is passphrase-protected: `SSHClient` would need
    /// a passphrase we don't have, and prompting has no place in a test.
    static var usableUserKey: (publicKey: String, privatePath: String)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let priv = home.appendingPathComponent(".ssh/id_ed25519")
        let pub = home.appendingPathComponent(".ssh/id_ed25519.pub")
        guard let pubText = try? String(contentsOf: pub, encoding: .utf8),
              let privText = try? String(contentsOf: priv, encoding: .utf8),
              !privText.contains("ENCRYPTED")
        else { return nil }
        return (pubText, priv.path)
    }

    static var sshdPath: String? {
        let p = "/usr/sbin/sshd"
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    /// Boot a server, or nil if the environment can't host one.
    static func start() -> EphemeralSSHD? {
        guard let sshd = sshdPath, let key = usableUserKey, let port = freePort() else { return nil }

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("shio-itest-\(UUID().uuidString)")
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

        let hostKey = dir.appendingPathComponent("host_key")
        guard runToCompletion("/usr/bin/ssh-keygen",
                              ["-q", "-t", "ed25519", "-f", hostKey.path, "-N", "", "-C", "shio-itest"])
        else { cleanup(dir); return nil }

        let authorized = dir.appendingPathComponent("authorized_keys")
        guard (try? key.publicKey.write(to: authorized, atomically: true, encoding: .utf8)) != nil
        else { cleanup(dir); return nil }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authorized.path)

        let username = NSUserName()
        // StrictModes off because the temp dir isn't under the user's home;
        // password/keyboard-interactive off so a key failure fails fast instead
        // of hanging on a prompt.
        let config = """
        Port \(port)
        ListenAddress 127.0.0.1
        HostKey \(hostKey.path)
        AuthorizedKeysFile \(authorized.path)
        PidFile \(dir.appendingPathComponent("sshd.pid").path)
        StrictModes no
        UsePAM no
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PubkeyAuthentication yes
        AllowUsers \(username)
        """
        let configURL = dir.appendingPathComponent("sshd_config")
        guard (try? config.write(to: configURL, atomically: true, encoding: .utf8)) != nil
        else { cleanup(dir); return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: sshd)
        // -D keeps it in the foreground so this Process owns its lifetime and
        // teardown is a terminate() rather than hunting a pid file.
        proc.arguments = ["-D", "-f", configURL.path, "-E", dir.appendingPathComponent("sshd.log").path]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { cleanup(dir); return nil }

        let server = EphemeralSSHD(port: port, username: username, dir: dir)
        server.process = proc
        guard server.waitUntilAccepting(timeout: 10) else { server.stop(); return nil }
        return server
    }

    /// Replace the host key and restart on the SAME port — the "this server's
    /// identity changed" case that host-key pinning exists to catch.
    func rotateHostKey() -> Bool {
        process?.terminate()
        process?.waitUntilExit()
        let hostKey = dir.appendingPathComponent("host_key")
        try? FileManager.default.removeItem(at: hostKey)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("host_key.pub"))
        guard Self.runToCompletion("/usr/bin/ssh-keygen",
                                   ["-q", "-t", "ed25519", "-f", hostKey.path, "-N", "", "-C", "rotated"])
        else { return false }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.sshdPath ?? "/usr/sbin/sshd")
        proc.arguments = ["-D", "-f", dir.appendingPathComponent("sshd_config").path,
                          "-E", dir.appendingPathComponent("sshd.log").path]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return false }
        process = proc
        return waitUntilAccepting(timeout: 10)
    }

    func stop() {
        process?.terminate()
        process?.waitUntilExit()
        process = nil
        Self.cleanup(dir)
    }

    // MARK: - plumbing

    private func waitUntilAccepting(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Self.canConnect(port: port) { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return false
    }

    /// Bind port 0, read what the kernel assigned, release it. A short race with
    /// another process is possible but vanishingly unlikely on loopback.
    private static func freePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var bound = false
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bound = bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard bound else { return nil }
        var out = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var got = false
        withUnsafeMutablePointer(to: &out) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                got = getsockname(fd, $0, &len) == 0
            }
        }
        guard got else { return nil }
        return Int(UInt16(bigEndian: out.sin_port))
    }

    private static func canConnect(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var ok = false
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                ok = connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        return ok
    }

    @discardableResult
    private static func runToCompletion(_ bin: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private static func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}
