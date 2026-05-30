import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// A live SSH local port forward: the phone listens on `127.0.0.1:<localPort>`
/// and tunnels each accepted connection through the existing SSH connection to
/// `<remoteHost>:<remotePort>` on the server (an SSH `direct-tcpip` channel).
///
/// Built for the away-from-laptop OAuth case: a CLI on the host (`claude
/// /login`, `gh auth login`) starts a loopback callback server on the host and
/// prints an auth URL whose `redirect_uri` targets `http://localhost:<port>`.
/// Forwarding that port to the phone lets the in-app browser's redirect reach
/// the host's callback server and complete the login.
final class SSHPortForward: @unchecked Sendable {
    private let serverChannel: any Channel
    let localPort: Int

    init(serverChannel: any Channel, localPort: Int) {
        self.serverChannel = serverChannel
        self.localPort = localPort
    }

    /// Stop listening and tear the forward down. Open tunnels close with it.
    func close() async {
        try? await serverChannel.close()
    }
}

extension SSHClient {
    /// Open a local forward `127.0.0.1:localPort` (phone) → `remoteHost:remotePort`
    /// (reached from the server). `remoteHost` defaults to `localhost`, tunneling
    /// to the server's own loopback — the OAuth-callback case.
    func openLocalForward(localPort: Int, remoteHost: String = "localhost", remotePort: Int) async throws -> SSHPortForward {
        guard sftpParentChannel != nil else { throw SSHError.notConnected }

        let bootstrap = ServerBootstrap(group: SSHClient.sharedEventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .childChannelInitializer { [self] localChannel in
                self.bridge(localChannel: localChannel, remoteHost: remoteHost, remotePort: remotePort)
            }

        let server = try await bootstrap.bind(host: "127.0.0.1", port: localPort).get()
        return SSHPortForward(serverChannel: server, localPort: localPort)
    }

    /// Wire one accepted local connection to a fresh `direct-tcpip` SSH channel,
    /// then glue the two so bytes flow both ways.
    private func bridge(localChannel: any Channel, remoteHost: String, remotePort: Int) -> EventLoopFuture<Void> {
        guard let parent = sftpParentChannel,
              let originator = try? SocketAddress(ipAddress: "127.0.0.1", port: 0) else {
            localChannel.close(promise: nil)
            return localChannel.eventLoop.makeFailedFuture(SSHError.notConnected)
        }

        let channelType = SSHChannelType.directTCPIP(.init(
            targetHost: remoteHost,
            targetPort: remotePort,
            originatorAddress: originator
        ))

        let promise = localChannel.eventLoop.makePromise(of: (any Channel).self)
        // createChannel must run on the parent connection's event loop.
        parent.eventLoop.execute {
            do {
                let handler = try parent.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                handler.createChannel(promise, channelType: channelType) { sshChannel, _ in
                    sshChannel.eventLoop.makeCompletedFuture {
                        try sshChannel.pipeline.syncOperations.addHandler(SSHToLocalGlue(peer: localChannel))
                    }
                }
            } catch {
                promise.fail(error)
            }
        }

        return promise.futureResult.flatMap { sshChannel in
            localChannel.pipeline.addHandler(LocalToSSHGlue(peer: sshChannel))
        }.flatMapError { error in
            localChannel.close(promise: nil)
            return localChannel.eventLoop.makeFailedFuture(error)
        }
    }
}

// MARK: - Glue handlers

/// Phone-side socket → SSH channel: wrap raw bytes as channel data.
private final class LocalToSSHGlue: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    private let peer: any Channel
    init(peer: any Channel) { self.peer = peer }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        peer.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer)), promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) { peer.close(promise: nil) }
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        context.close(promise: nil)
        peer.close(promise: nil)
    }
}

/// SSH channel → phone-side socket: unwrap channel data to raw bytes.
private final class SSHToLocalGlue: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    private let peer: any Channel
    init(peer: any Channel) { self.peer = peer }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard channelData.type == .channel,
              case .byteBuffer(let buffer) = channelData.data else { return }
        peer.writeAndFlush(buffer, promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) { peer.close(promise: nil) }
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        context.close(promise: nil)
        peer.close(promise: nil)
    }
}
