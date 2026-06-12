import Foundation
import CryptoKit
import NIOCore
import NIOPosix
import NIOSSH

/// High-level async SSH client wrapping SwiftNIO SSH.
///
/// Architecture notes:
/// - **One shared `EventLoopGroup`** for the lifetime of the app. NIO requires
///   `syncShutdownGracefully()` before an ELG deallocates, but calling that
///   from a per-client `deinit` on `MainActor` deadlocks the main thread.
///   A shared ELG is the idiomatic NIO pattern for clients.
/// - **`@unchecked Sendable`, not `@MainActor`** — networking lives off the
///   main thread. Callbacks hop back to MainActor at the call site.
/// - **No `fatalError` paths**: every failure becomes a thrown
///   `SSHError` that the caller can surface to the user.
final class SSHClient: @unchecked Sendable {

    struct Configuration: Sendable {
        var host: String
        var port: Int = 22
        var username: String
        var authentication: Authentication
        var initialCols: Int = 80
        var initialRows: Int = 24
        /// TCP connection timeout. Soft-fails the connect with a clear error
        /// instead of hanging the UI on unreachable hosts.
        var connectTimeoutSeconds: Int = 10
    }

    enum Authentication: Sendable {
        case password(String)
        /// Authenticate using Shio's device-bound Ed25519 key (from KeyManager).
        /// This is the default for all hosts created through onboarding on iOS.
        case shioKey
        /// Mac-native: offer the user's existing `~/.ssh` keys first (so Shio
        /// connects with the keys their servers already trust, like Terminal),
        /// then fall back to the Shio key. On iOS there are no `~/.ssh` keys, so
        /// this degrades to just the Shio key.
        case systemKeys
        /// No authentication is configured. SSHClient will surface a clear
        /// error rather than attempting an impossible handshake.
        case unconfigured
    }

    enum SSHError: LocalizedError {
        case channelClosed
        case shellRequestFailed
        case ptyRequestFailed
        case noAuthenticationConfigured
        case connectionFailed(String)
        case authenticationFailed
        case notConnected
        case keychainUnavailable(String)
        case keychainFailed(String)
        case sshKeyMissing
        case noUsableKey([String])
        case passphraseRequired([String])
        case hostKeyChanged

        var errorDescription: String? {
            switch self {
            case .channelClosed:               return "The SSH channel closed unexpectedly."
            case .shellRequestFailed:          return "The remote host wouldn't open a shell."
            case .ptyRequestFailed:            return "The remote host wouldn't open a PTY."
            case .noAuthenticationConfigured:  return "This Mac has no authentication set up. Add a password or SSH key in its profile."
            case .connectionFailed(let why):   return "Couldn't reach this Mac. \(why)"
            case .authenticationFailed:        return "Authentication failed — the server rejected the key(s) and password offered. Make sure this device's key is in the host's ~/.ssh/authorized_keys."
            case .notConnected:                return "Not connected."
            case .keychainUnavailable(let why):return "Couldn't read your SSH key — \(why)"
            case .keychainFailed(let why):     return "Keychain error — \(why)"
            case .sshKeyMissing:               return "No SSH key has been generated yet. Open Settings → SSH Key to set one up."
            case .noUsableKey(let skipped):
                let detail = skipped.isEmpty ? "" : " (" + skipped.joined(separator: "; ") + ")"
                return "No usable SSH key found in ~/.ssh\(detail). Add an ed25519 key, or set a password for this host."
            case .passphraseRequired(let names):
                let which = names.first.map { " for \($0)" } ?? ""
                return "Your SSH key\(which) is passphrase-protected. Enter its passphrase to unlock it."
            case .hostKeyChanged:
                return "This server's host key changed since you last connected. That can mean it was reinstalled — or that the connection is being intercepted. Refused for safety. Remove the host and re-add it if you trust the change."
            }
        }
    }

    /// Called whenever the remote shell produces output. Already dispatches
    /// onto the main actor before invocation.
    var onOutput:     (@Sendable (Data) -> Void)?
    /// Called when the session closes (cleanly or otherwise).
    var onDisconnect: (@Sendable ((any Error)?) -> Void)?

    // Shared event loop group — initialized once, lives forever. NIO clients
    // are expected to use a shared group; per-client ELGs deadlock on deinit.
    private static let sharedGroup: any EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    private var channel:      (any Channel)?
    private var childChannel: (any Channel)?
    private let configuration: Configuration
    /// The SSH keys resolved at connect() time (in preference order), so the
    /// auth delegate never touches Keychain or the filesystem on the NIO event
    /// loop. The delegate offers each in turn until one is accepted.
    private var resolvedKeys: [NIOSSHPrivateKey] = []

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    // No deinit shutdown — ELG is shared.

    // MARK: - Lifecycle

    func connect() async throws {
        // Map config → typed errors before any network I/O. This is also
        // where we pre-resolve the Keychain-backed key — Keychain access
        // happens off the NIO event loop (audit finding #6) and surfaces
        // distinct error states instead of collapsing into "auth failed"
        // (audit finding #3).
        switch configuration.authentication {
        case .unconfigured:
            throw SSHError.noAuthenticationConfigured
        case .password:
            break
        case .shioKey:
            try resolveShioKey()
        case .systemKeys:
            try resolveSystemKeys()
        }
        try await doConnect()
    }

    /// Loads Shio's Ed25519 key from Keychain and wraps it as a
    /// `NIOSSHPrivateKey`. Called on the caller's thread (typically a
    /// background Task in SessionViewModel.start), not on NIO's event loop.
    private func resolveShioKey() throws {
        do {
            var keys: [NIOSSHPrivateKey] = []
            // Opt-in Secure Enclave key first (preferred), Ed25519 as fallback
            // so a host authorized for either still connects (#36).
            // Best-effort: an Enclave read failure (key invalidated, biometry
            // changed) must not abort the connect — the Ed25519 key below is
            // still valid on its own.
            if KeyManager.useEnclaveKey, let se = try? KeyManager.existingEnclaveKey() {
                keys.append(NIOSSHPrivateKey(secureEnclaveP256Key: se))
            }
            if let pk = try KeyManager.existingKey() {
                keys.append(NIOSSHPrivateKey(ed25519Key: pk))
            }
            guard !keys.isEmpty else { throw SSHError.sshKeyMissing }
            resolvedKeys = keys
        } catch let e as KeyManager.KeyError {
            if e.isAvailabilityIssue {
                throw SSHError.keychainUnavailable(e.localizedDescription)
            }
            throw SSHError.keychainFailed(e.localizedDescription)
        } catch {
            throw error
        }
    }

    /// Mac-native auth: offer the user's existing `~/.ssh` keys first, then the
    /// Shio key if one exists. Best-effort — keys that can't be parsed are
    /// skipped. Throws only when nothing usable is found, with the reasons.
    private func resolveSystemKeys() throws {
        let loaded = SystemSSHKeys.load()
        // If the user's only ~/.ssh identity is an encrypted key, ask them to
        // unlock it rather than silently falling back to a Shio key the host
        // won't trust. The caller (Mac session) prompts and retries.
        if loaded.keys.isEmpty && !loaded.encryptedNeedingPassphrase.isEmpty {
            throw SSHError.passphraseRequired(loaded.encryptedNeedingPassphrase)
        }
        var keys = loaded.keys
        if KeyManager.useEnclaveKey, let se = try? KeyManager.existingEnclaveKey() {
            keys.append(NIOSSHPrivateKey(secureEnclaveP256Key: se))
        }
        if let pk = try? KeyManager.existingKey() {
            keys.append(NIOSSHPrivateKey(ed25519Key: pk))
        }
        guard !keys.isEmpty else {
            throw SSHError.noUsableKey(loaded.skipped)
        }
        resolvedKeys = keys
    }

    private func doConnect() async throws {
        let cfg = configuration
        // The handshake gate: connect() must mean *authenticated*, not "TCP is
        // up". Without it, a rejected key/password never surfaces — NIOSSH
        // goes quiet on auth exhaustion and the connection idles until the
        // server's LoginGraceTime (~2 min) kills it as a generic eof.
        let gate = HandshakeGate(on: SSHClient.sharedGroup.next())
        let auth = SSHAuthenticationDelegate(configuration: cfg, resolvedKeys: resolvedKeys) {
            gate.fail(SSHError.authenticationFailed)
        }
        let host = SSHHostKeyDelegate(hostPort: "\(cfg.host):\(cfg.port)")

        let bootstrap = ClientBootstrap(group: SSHClient.sharedGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .connectTimeout(.seconds(Int64(cfg.connectTimeoutSeconds)))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let clientConfig = SSHClientConfiguration(
                        userAuthDelegate: auth,
                        serverAuthDelegate: host
                    )
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSHHandler(
                            role: .client(clientConfig),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        )
                    )
                    try channel.pipeline.syncOperations.addHandler(
                        HandshakeGateHandler(gate: gate)
                    )
                }
            }

        let parent: any Channel
        do {
            parent = try await bootstrap.connect(host: cfg.host, port: cfg.port).get()
        } catch let error as SSHError {
            gate.fail(error)   // complete the gate so the promise never leaks
            throw error
        } catch {
            gate.fail(error)
            throw SSHError.connectionFailed(translateConnectError(error, host: cfg.host, port: cfg.port))
        }

        // Deadline for the whole SSH handshake (version exchange → KEX → host
        // key → user auth), so a post-TCP stall can't hang the UI.
        let deadline = parent.eventLoop.scheduleTask(in: .seconds(Int64(cfg.connectTimeoutSeconds) + 5)) {
            gate.fail(SSHError.connectionFailed("The SSH handshake timed out."))
        }
        do {
            try await gate.future.get()
            deadline.cancel()
            self.channel = parent
        } catch {
            deadline.cancel()
            // Close eagerly — on auth exhaustion the server would otherwise
            // hold the half-open connection until its grace timeout.
            try? await parent.close()
            if let sshError = error as? SSHError { throw sshError }
            throw SSHError.connectionFailed(translateConnectError(error, host: cfg.host, port: cfg.port))
        }
    }

    /// Delegates to the shared `ConnectErrorTranslator` so both the SSH
    /// client and the Tailscale diagnostic engine surface identical copy
    /// for the same underlying problem.
    private func translateConnectError(_ error: any Error, host: String, port: Int) -> String {
        ConnectErrorTranslator.translate(
            error,
            host: host,
            port: port,
            connectTimeoutSeconds: configuration.connectTimeoutSeconds
        )
    }

    /// Open a shell channel with a PTY.
    func requestShell() async throws {
        guard let parent = channel else { throw SSHError.notConnected }

        let dataHandler = ShellDataHandler { [weak self] data in
            self?.onOutput?(data)
        } onClose: { [weak self] error in
            self?.onDisconnect?(error)
        }

        let promise = parent.eventLoop.makePromise(of: (any Channel).self)
        try await parent.eventLoop.submit {
            let sshHandler = try parent.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
            sshHandler.createChannel(promise, channelType: .session) { childChannel, _ in
                childChannel.eventLoop.makeCompletedFuture {
                    try childChannel.pipeline.syncOperations.addHandler(dataHandler)
                }
            }
        }.get()
        let child = try await promise.futureResult.get()
        self.childChannel = child

        let ptyReq = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: configuration.initialCols,
            terminalRowHeight: configuration.initialRows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        try await child.triggerUserOutboundEvent(ptyReq)

        let shellReq = SSHChannelRequestEvent.ShellRequest(wantReply: true)
        try await child.triggerUserOutboundEvent(shellReq)
    }

    /// Result of a headless exec with integrity info the bare string can't
    /// carry: stdout and stderr separately, the remote exit status (nil when
    /// the channel closed without reporting one), and whether the timeout cut
    /// the command off. Callers that mutate remote state (GitWriter, skills)
    /// use this to distinguish "succeeded" from "produced some output".
    struct ExecResult: Sendable {
        var stdout: String
        var stderr: String
        var exitStatus: Int?
        var timedOut: Bool
    }

    /// Run a single command on the host (no PTY) and return its stdout. Opens
    /// its own exec channel, collects stdout to EOF, and closes. Used for
    /// best-effort headless reads — cross-machine file search (`find`/`fd`),
    /// status probes. A timeout closes the channel so a hung command returns
    /// what it produced rather than blocking forever; use `execWithStatus`
    /// when "timed out" or "failed" must not read as success.
    func exec(_ command: String, timeout: TimeAmount = .seconds(20)) async throws -> String {
        try await execWithStatus(command, timeout: timeout).stdout
    }

    /// Run a POSIX script on the host regardless of the user's login shell.
    /// SSH exec hands the command line to that shell — fish or csh would choke
    /// on POSIX syntax *silently* (every probe reads as timed out, skills
    /// never materialize) — so the script travels as base64 (safe in every
    /// shell's quoting rules) and is piped into `sh`. `--decode` rather than
    /// `-d` so it decodes on BSD/macOS of any vintage and GNU alike.
    func exec(posixScript: String, timeout: TimeAmount = .seconds(20)) async throws -> String {
        try await exec(Self.posixWrapper(posixScript), timeout: timeout)
    }

    /// `exec(posixScript:)` with the full `ExecResult` (the pipe's exit
    /// status is `sh`'s — i.e. the script's own).
    func execWithStatus(posixScript: String, timeout: TimeAmount = .seconds(20)) async throws -> ExecResult {
        try await execWithStatus(Self.posixWrapper(posixScript), timeout: timeout)
    }

    private static func posixWrapper(_ script: String) -> String {
        "printf '%s' \(Data(script.utf8).base64EncodedString()) | base64 --decode | sh"
    }

    /// `exec` with the full result: separate stderr, the command's exit
    /// status, and an explicit timed-out marker.
    func execWithStatus(_ command: String, timeout: TimeAmount = .seconds(20)) async throws -> ExecResult {
        guard let parent = channel else { throw SSHError.notConnected }

        let resultPromise = parent.eventLoop.makePromise(of: ExecResult.self)
        let collector = ExecCollector(promise: resultPromise)

        let chPromise = parent.eventLoop.makePromise(of: (any Channel).self)
        try await parent.eventLoop.submit {
            let sshHandler = try parent.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
            sshHandler.createChannel(chPromise, channelType: .session) { childChannel, _ in
                childChannel.eventLoop.makeCompletedFuture {
                    try childChannel.pipeline.syncOperations.addHandler(collector)
                }
            }
        }.get()
        let child = try await chPromise.futureResult.get()

        // Timeout marks the result, then closes the channel → EOF → the
        // collector resolves with whatever arrived (no double-resolve). The
        // task runs on the same event loop as the handler, so the flag write
        // is race-free.
        let timeoutTask = parent.eventLoop.scheduleTask(in: timeout) {
            collector.markTimedOut()
            child.close(promise: nil)
        }
        resultPromise.futureResult.whenComplete { _ in timeoutTask.cancel() }

        let execReq = SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
        try await child.triggerUserOutboundEvent(execReq)

        return try await resultPromise.futureResult.get()
    }

    /// Whether the underlying transport is still up. iOS kills sockets during
    /// suspension while the caller's state may still say "connected" — the
    /// foreground reconnect check uses this to detect the lie.
    var isTransportActive: Bool { channel?.isActive ?? false }

    func write(_ data: Data) {
        guard let child = childChannel else { return }
        var buf = child.allocator.buffer(capacity: data.count)
        buf.writeBytes(data)
        let ioData = SSHChannelData(type: .channel, data: .byteBuffer(buf))
        child.writeAndFlush(ioData, promise: nil)
    }

    func write(_ string: String) {
        write(Data(string.utf8))
    }

    func resize(cols: Int, rows: Int) {
        guard let child = childChannel else { return }
        let event = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        child.triggerUserOutboundEvent(event, promise: nil)
    }

    func disconnect() async {
        if let child = childChannel { try? await child.close() }
        if let parent = channel { try? await parent.close() }
        channel = nil
        childChannel = nil
    }

    // MARK: - SFTP support hooks (used by SFTPClient.swift)

    /// The parent connection channel, exposed so the SFTP subsystem can open
    /// its own child channel on the same connection.
    var sftpParentChannel: (any Channel)? { channel }
    /// An event loop from the shared group, for constructing failed futures
    /// off the connection path.
    static var sftpEventLoop: any EventLoop { sharedGroup.next() }
    /// The shared event loop group, for local-forward server bootstraps.
    static var sharedEventLoopGroup: any EventLoopGroup { sharedGroup }
}

// MARK: - Handshake gate

/// One-shot wrapper around the handshake promise. The gate can be completed
/// from several places (auth-success event, pipeline error, auth exhaustion,
/// deadline, channel close) and NIO promises trap on double-completion, so
/// only the first outcome wins.
private final class HandshakeGate: @unchecked Sendable {
    private let promise: EventLoopPromise<Void>
    private let lock = NSLock()
    private var completed = false

    init(on loop: any EventLoop) {
        promise = loop.makePromise(of: Void.self)
    }

    var future: EventLoopFuture<Void> { promise.futureResult }

    func succeed() { complete { $0.succeed(()) } }
    func fail(_ error: any Error) { complete { $0.fail(error) } }

    private func complete(_ body: (EventLoopPromise<Void>) -> Void) {
        lock.lock()
        let first = !completed
        completed = true
        lock.unlock()
        if first { body(promise) }
    }
}

/// Watches the parent SSH pipeline during connect: succeeds the gate when
/// user auth completes, fails it on any handshake error — a host-key mismatch
/// arrives here as the original `SSHError.hostKeyChanged`, since NIOSSH fires
/// the delegate's validation error down the pipeline verbatim — or when the
/// server closes mid-handshake. Inert after the gate resolves.
private final class HandshakeGateHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any

    private let gate: HandshakeGate
    init(gate: HandshakeGate) { self.gate = gate }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent { gate.succeed() }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        gate.fail(error)
        context.fireErrorCaught(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        gate.fail(SSHClient.SSHError.connectionFailed("The server closed the connection during the SSH handshake."))
        context.fireChannelInactive()
    }
}

// MARK: - User auth delegate

private final class SSHAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    let configuration: SSHClient.Configuration
    /// Pre-resolved by SSHClient.connect() so this delegate never touches
    /// Keychain on the NIO event loop.
    let resolvedKeys: [NIOSSHPrivateKey]
    /// Called when we run out of credentials to offer (or the server doesn't
    /// accept our method at all). NIOSSH treats a nil offer as "do nothing",
    /// which stalls the connection silently — this lets SSHClient fail fast
    /// with `.authenticationFailed` instead.
    private let onExhausted: @Sendable () -> Void
    /// Tracks which methods we've already tried this session so NIO doesn't
    /// loop us into the same offer when the server rejects it.
    private var attempted: Set<String> = []
    /// Index of the next key to offer — we walk the list so the server can
    /// reject one and we try the next (system keys, then the Shio key).
    private var keyIndex = 0

    init(
        configuration: SSHClient.Configuration,
        resolvedKeys: [NIOSSHPrivateKey],
        onExhausted: @escaping @Sendable () -> Void
    ) {
        self.configuration = configuration
        self.resolvedKeys = resolvedKeys
        self.onExhausted = onExhausted
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        switch configuration.authentication {
        case .password(let password):
            guard availableMethods.contains(.password), !attempted.contains("password") else {
                nextChallengePromise.succeed(nil)
                onExhausted()
                return
            }
            attempted.insert("password")
            let offer = NIOSSHUserAuthenticationOffer(
                username: configuration.username,
                serviceName: "",
                offer: .password(.init(password: password))
            )
            nextChallengePromise.succeed(offer)

        case .shioKey, .systemKeys:
            // Offer each resolved key in turn; NIO calls us again when the
            // server rejects one, so we advance to the next key in the list.
            guard availableMethods.contains(.publicKey), keyIndex < resolvedKeys.count else {
                nextChallengePromise.succeed(nil)
                onExhausted()
                return
            }
            let key = resolvedKeys[keyIndex]
            keyIndex += 1
            let offer = NIOSSHUserAuthenticationOffer(
                username: configuration.username,
                serviceName: "",
                offer: .privateKey(.init(privateKey: key))
            )
            nextChallengePromise.succeed(offer)

        case .unconfigured:
            nextChallengePromise.succeed(nil)
            onExhausted()
        }
    }
}

// MARK: - Host key pinning (trust-on-first-use)

/// Shio's own known-hosts pin store: `host:port` → host-key fingerprint, so a
/// host key that *changes* between connects (a potential MITM, or a reinstalled
/// box) is caught. Persisted in UserDefaults — fingerprints are public, not
/// secret, same as `~/.ssh/known_hosts`.
enum ShioKnownHosts {
    private static let storeKey = "shio.knownHosts.v1"
    private static let lock = NSLock()

    static func fingerprint(for hostPort: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String])?[hostPort]
    }

    static func pin(_ fingerprint: String, for hostPort: String) {
        lock.lock(); defer { lock.unlock() }
        var map = (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String]) ?? [:]
        map[hostPort] = fingerprint
        UserDefaults.standard.set(map, forKey: storeKey)
    }

    /// Forget a host's pin (e.g. user chose to re-trust a changed key).
    static func forget(_ hostPort: String) {
        lock.lock(); defer { lock.unlock() }
        var map = (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String]) ?? [:]
        map[hostPort] = nil
        UserDefaults.standard.set(map, forKey: storeKey)
    }
}

/// A stable fingerprint for a host key. swift-nio-ssh exposes no public
/// serializer for `NIOSSHPublicKey`, but it wraps a plain CryptoKit key whose
/// `rawRepresentation` *is* stable — so reflect to it and SHA-256 that. Returns
/// nil if NIOSSH ever restructures its internals (or for certified keys), in
/// which case the caller accepts without pinning rather than breaking.
private func hostKeyFingerprint(_ key: NIOSSHPublicKey) -> String? {
    guard let backing = Mirror(reflecting: key).children.first(where: { $0.label == "backingKey" })?.value,
          let assoc = Mirror(reflecting: backing).children.first else { return nil }
    let raw: Data
    switch assoc.value {
    case let k as Curve25519.Signing.PublicKey: raw = k.rawRepresentation
    case let k as P256.Signing.PublicKey:        raw = k.rawRepresentation
    case let k as P384.Signing.PublicKey:        raw = k.rawRepresentation
    case let k as P521.Signing.PublicKey:        raw = k.rawRepresentation
    default: return nil   // certified / unknown key type → no pin
    }
    var hasher = SHA256()
    hasher.update(data: Data((assoc.label ?? "").utf8))   // key-type tag, so types can't collide
    hasher.update(data: raw)
    return "v1:" + Data(hasher.finalize()).base64EncodedString()
}

/// Validates the server's host key with trust-on-first-use: pin the key the
/// first time we see a `host:port`, accept it unchanged thereafter, and refuse
/// if it changes (MITM / reinstall — surfaced as `.hostKeyChanged`).
///
/// NOTE: this used to hardcode `.fail` in Release (accept only in DEBUG), which
/// rejected EVERY host key in every shipped build — no Release build could
/// connect to anything. That was the launch blocker.
private final class SSHHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let hostPort: String
    init(hostPort: String) { self.hostPort = hostPort }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        guard let fp = hostKeyFingerprint(hostKey) else {
            validationCompletePromise.succeed(())   // can't fingerprint → accept, don't break
            return
        }
        if let pinned = ShioKnownHosts.fingerprint(for: hostPort) {
            if pinned == fp {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(SSHClient.SSHError.hostKeyChanged)
            }
        } else {
            ShioKnownHosts.pin(fp, for: hostPort)    // trust on first use
            validationCompletePromise.succeed(())
        }
    }
}

// MARK: - Shell data handler

private final class ShellDataHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData

    private let onData: @Sendable (Data) -> Void
    private let onClose: @Sendable ((any Error)?) -> Void

    init(
        onData: @escaping @Sendable (Data) -> Void,
        onClose: @escaping @Sendable ((any Error)?) -> Void
    ) {
        self.onData = onData
        self.onClose = onClose
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = channelData.data else { return }
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
        onData(Data(bytes))
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        onClose(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        onClose(nil)
    }
}

/// Collects an exec channel's stdout + stderr and the command's exit status
/// until EOF/close, then resolves a promise with the full `ExecResult`. All
/// state is touched only on the channel's event loop.
private final class ExecCollector: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData

    private var stdout = Data()
    private var stderr = Data()
    private var exitStatus: Int?
    private var timedOut = false
    private let promise: EventLoopPromise<SSHClient.ExecResult>
    private var resolved = false

    init(promise: EventLoopPromise<SSHClient.ExecResult>) { self.promise = promise }

    /// Called by the exec timeout (scheduled on this channel's event loop)
    /// just before it force-closes the channel.
    func markTimedOut() { timedOut = true }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)
        guard case .byteBuffer(var buf) = channelData.data,
              let bytes = buf.readBytes(length: buf.readableBytes) else { return }
        switch channelData.type {
        case .channel: stdout.append(contentsOf: bytes)
        case .stdErr:  stderr.append(contentsOf: bytes)
        default:       break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let status = event as? SSHChannelRequestEvent.ExitStatus {
            exitStatus = status.exitStatus
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !resolved {
            resolved = true
            promise.succeed(SSHClient.ExecResult(
                stdout: String(decoding: stdout, as: UTF8.self),
                stderr: String(decoding: stderr, as: UTF8.self),
                exitStatus: exitStatus,
                timedOut: timedOut
            ))
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        if !resolved { resolved = true; promise.fail(error) }
        context.close(promise: nil)
    }
}
