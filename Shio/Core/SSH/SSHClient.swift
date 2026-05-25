import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// High-level async SSH client. Hides the NIO event-loop plumbing behind a
/// simple `connect`/`requestShell`/`write`/`disconnect` interface.
///
/// Per the plan, this is the foundation for Brick 3 — Brick 5 (tmux), Brick 7
/// (Pro Mode with ProxyJump) and Brick 13 (Mosh) layer additional behavior on
/// top of (or alongside) this client.
@MainActor
final class SSHClient {

    struct Configuration: Sendable {
        var host: String
        var port: Int = 22
        var username: String
        var authentication: Authentication
        /// Initial PTY size — kept in sync via `resize(cols:rows:)`.
        var initialCols: Int = 80
        var initialRows: Int = 24
    }

    enum Authentication: Sendable {
        case password(String)
        case privateKey(PEM: String, passphrase: String?)
    }

    enum SSHError: Error {
        case channelClosed
        case shellRequestFailed
        case ptyRequestFailed
        case authenticationFailed
        case notConnected
    }

    /// Called whenever the remote shell produces output.
    var onOutput: ((Data) -> Void)?
    /// Called when the session closes (cleanly or otherwise).
    var onDisconnect: (((any Error)?) -> Void)?

    private let eventLoopGroup: any EventLoopGroup
    private var channel: (any Channel)?
    private var childChannel: (any Channel)?
    private let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    // MARK: - Lifecycle

    func connect() async throws {
        let cfg = configuration
        let auth = SSHAuthenticationDelegate(configuration: cfg)
        let host = SSHHostKeyDelegate()    // TOFU stub — Brick 7 hardens this

        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                let clientConfig = SSHClientConfiguration(
                    userAuthDelegate: auth,
                    serverAuthDelegate: host
                )
                return channel.pipeline.addHandlers([
                    NIOSSHHandler(role: .client(clientConfig),
                                  allocator: channel.allocator,
                                  inboundChildChannelInitializer: nil)
                ])
            }

        do {
            let parent = try await bootstrap.connect(host: cfg.host, port: cfg.port).get()
            self.channel = parent
        } catch {
            throw SSHError.authenticationFailed
        }
    }

    /// Open a shell channel with a PTY. The remote shell's stdout/stderr stream
    /// to `onOutput` and `write(_:)` sends bytes to stdin.
    func requestShell() async throws {
        guard let parent = channel else { throw SSHError.notConnected }

        let dataHandler = ShellDataHandler { [weak self] data in
            self?.onOutput?(data)
        } onClose: { [weak self] error in
            self?.onDisconnect?(error)
        }

        let promise = parent.eventLoop.makePromise(of: (any Channel).self)
        let handler = try await parent.pipeline.handler(type: NIOSSHHandler.self).get()
        handler.createChannel(promise, channelType: .session) { childChannel, _ in
            childChannel.pipeline.addHandlers([
                dataHandler
            ])
        }
        let child = try await promise.futureResult.get()
        self.childChannel = child

        // Request a PTY.
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

        // Request a shell.
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

    /// Update the PTY size when the terminal resizes.
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

        case .privateKey(let pem, _):
            guard availableMethods.contains(.publicKey) else {
                nextChallengePromise.succeed(nil)
                return
            }
            // TODO(Brick 7): proper PEM/Keychain integration; Brick 3 stub.
            // For now we error out; tests use password auth.
            _ = pem
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
        // Brick 7 will prompt the user on first connect (TOFU), persist the
        // fingerprint, and reject mismatches thereafter. For Brick 3 we
        // accept all keys — but only in debug builds; release-mode users
        // will not reach this code path without the Brick 7 logic in place.
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

    private let onData: (Data) -> Void
    private let onClose: ((any Error)?) -> Void

    init(onData: @escaping (Data) -> Void, onClose: @escaping ((any Error)?) -> Void) {
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
