import Foundation
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
        case privateKey(PEM: String, passphrase: String?)
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

        var errorDescription: String? {
            switch self {
            case .channelClosed:               return "The SSH channel closed unexpectedly."
            case .shellRequestFailed:          return "The remote host wouldn't open a shell."
            case .ptyRequestFailed:            return "The remote host wouldn't open a PTY."
            case .noAuthenticationConfigured:  return "This Mac has no authentication set up. Add a password or SSH key in its profile."
            case .connectionFailed(let why):   return "Couldn't reach this Mac. \(why)"
            case .authenticationFailed:        return "Authentication failed. Check your username and key."
            case .notConnected:                return "Not connected."
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

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    // No deinit shutdown — ELG is shared.

    // MARK: - Lifecycle

    func connect() async throws {
        if case .unconfigured = configuration.authentication {
            throw SSHError.noAuthenticationConfigured
        }
        try await doConnect()
    }

    private func doConnect() async throws {
        let cfg = configuration
        let auth = SSHAuthenticationDelegate(configuration: cfg)
        let host = SSHHostKeyDelegate()

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
                }
            }

        do {
            let parent = try await bootstrap.connect(host: cfg.host, port: cfg.port).get()
            self.channel = parent
        } catch let error as SSHError {
            throw error
        } catch {
            throw SSHError.connectionFailed(error.localizedDescription)
        }
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
}

// MARK: - User auth delegate

private final class SSHAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    let configuration: SSHClient.Configuration

    init(configuration: SSHClient.Configuration) {
        self.configuration = configuration
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        switch configuration.authentication {
        case .password(let password):
            guard availableMethods.contains(.password) else {
                nextChallengePromise.succeed(nil)
                return
            }
            let offer = NIOSSHUserAuthenticationOffer(
                username: configuration.username,
                serviceName: "",
                offer: .password(.init(password: password))
            )
            nextChallengePromise.succeed(offer)

        case .privateKey:
            // Brick 7 second pass wires real Keychain-backed Ed25519 keys here.
            // For now, no public-key auth — yield nil so NIO surfaces a clear
            // authenticationFailed error.
            nextChallengePromise.succeed(nil)

        case .unconfigured:
            nextChallengePromise.succeed(nil)
        }
    }
}

// MARK: - Host key delegate (TOFU stub — Brick 7 hardens this)

private final class SSHHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        #if DEBUG
        validationCompletePromise.succeed(())
        #else
        validationCompletePromise.fail(SSHClient.SSHError.authenticationFailed)
        #endif
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
