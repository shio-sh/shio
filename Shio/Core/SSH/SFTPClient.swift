import Foundation
import NIOCore
import NIOSSH

/// A minimal SFTP v3 client implemented over a SwiftNIO-SSH child channel.
///
/// swift-nio-ssh ships no SFTP, so this speaks the wire protocol directly
/// (RFC draft-ietf-secsh-filexfer-02, the de-facto v3 everyone implements):
/// length-prefixed packets, a request id echoed in each response, and the
/// handle/attrs/name/data/status reply shapes.
///
/// Scope: realpath, directory listing, read, write, mkdir, rmdir, remove,
/// rename, stat. Enough for a Finder-grade browser; not a complete client.
///
/// RUNTIME NOTE: this compiles and is structurally complete, but the wire
/// protocol can only be validated against a live OpenSSH SFTP server. Treat
/// it as needing real-device verification (Phase 5 end-test).
final class SFTPClient: @unchecked Sendable {

    enum PacketType: UInt8 {
        case initialize = 1, version = 2, open = 3, close = 4, read = 5, write = 6
        case lstat = 7, fstat = 8, setstat = 9, fsetstat = 10, opendir = 11
        case readdir = 12, remove = 13, mkdir = 14, rmdir = 15, realpath = 16
        case stat = 17, rename = 18, readlink = 19, symlink = 20
        case status = 101, handle = 102, data = 103, name = 104, attrs = 105
    }

    struct OpenFlags {
        static let read: UInt32   = 0x00000001
        static let write: UInt32  = 0x00000002
        static let append: UInt32 = 0x00000004
        static let creat: UInt32  = 0x00000008
        static let trunc: UInt32  = 0x00000010
        static let excl: UInt32   = 0x00000020
    }

    enum SFTPError: LocalizedError {
        case notReady
        case unexpectedResponse
        case status(code: UInt32, message: String)

        var errorDescription: String? {
            switch self {
            case .notReady:            return "The file connection isn't ready."
            case .unexpectedResponse:  return "The server sent an unexpected SFTP response."
            case .status(let code, let message):
                if !message.isEmpty { return message }
                return "SFTP error (code \(code))."
            }
        }
    }

    private struct Response { let type: UInt8; var body: ByteBuffer }

    private var channel: (any Channel)?
    private var eventLoop: (any EventLoop)?
    private var nextID: UInt32 = 1
    private var pending: [UInt32: EventLoopPromise<Response>] = [:]
    private var versionPromise: EventLoopPromise<Void>?
    /// Bytes to pull per READ/WRITE. 32 KiB is comfortably under the
    /// 256 KiB per-packet limit most servers enforce.
    private let chunkSize: UInt32 = 32 * 1024

    fileprivate func attach(channel: any Channel) {
        self.channel = channel
        self.eventLoop = channel.eventLoop
    }

    // MARK: Inbound packet routing (runs on the child channel's event loop)

    fileprivate func handlePacket(type: UInt8, payload: ByteBuffer) {
        if type == PacketType.version.rawValue {
            versionPromise?.succeed(())
            versionPromise = nil
            return
        }
        var body = payload
        guard let id = body.readInteger(as: UInt32.self),
              let promise = pending.removeValue(forKey: id) else { return }
        promise.succeed(Response(type: type, body: body))
    }

    fileprivate func handleClose(_ error: (any Error)?) {
        let err = error ?? SFTPError.notReady
        versionPromise?.fail(err)
        versionPromise = nil
        for (_, promise) in pending { promise.fail(err) }
        pending.removeAll()
    }

    // MARK: Request plumbing

    fileprivate func initialize() -> EventLoopFuture<Void> {
        guard let eventLoop, let channel else {
            return SSHClient.sftpEventLoop.makeFailedFuture(SFTPError.notReady)
        }
        let promise = eventLoop.makePromise(of: Void.self)
        eventLoop.execute {
            self.versionPromise = promise
            var buf = channel.allocator.buffer(capacity: 9)
            buf.writeInteger(UInt32(0))                       // length placeholder
            buf.writeInteger(PacketType.initialize.rawValue)  // type
            buf.writeInteger(UInt32(3))                       // protocol version (NOT a request id)
            buf.setInteger(UInt32(buf.writerIndex - 4), at: 0, as: UInt32.self)
            channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buf)), promise: nil)
        }
        return promise.futureResult
    }

    private func request(_ type: PacketType, _ build: @escaping @Sendable (inout ByteBuffer) -> Void) -> EventLoopFuture<Response> {
        guard let eventLoop, let channel else {
            return SSHClient.sftpEventLoop.makeFailedFuture(SFTPError.notReady)
        }
        let promise = eventLoop.makePromise(of: Response.self)
        eventLoop.execute {
            let id = self.nextID
            self.nextID &+= 1
            self.pending[id] = promise
            var buf = channel.allocator.buffer(capacity: 64)
            buf.writeInteger(UInt32(0))         // length placeholder
            buf.writeInteger(type.rawValue)     // type
            buf.writeInteger(id)                // request id
            build(&buf)
            buf.setInteger(UInt32(buf.writerIndex - 4), at: 0, as: UInt32.self)
            channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buf)), promise: nil)
        }
        return promise.futureResult
    }

    /// Throw if a STATUS response is an error; otherwise return.
    private func expectOK(_ response: Response) throws {
        guard response.type == PacketType.status.rawValue else {
            throw SFTPError.unexpectedResponse
        }
        var body = response.body
        let code = body.readInteger(as: UInt32.self) ?? 4
        guard code == 0 else {
            throw SFTPError.status(code: code, message: body.readSFTPString() ?? "")
        }
    }

    // MARK: Public operations

    /// Resolve a (possibly relative or `~`) path to an absolute one.
    func realpath(_ path: String) async throws -> String {
        let resp = try await request(.realpath) { $0.writeSFTPString(path) }.get()
        guard resp.type == PacketType.name.rawValue else { try expectOK(resp); throw SFTPError.unexpectedResponse }
        var body = resp.body
        _ = body.readInteger(as: UInt32.self)               // count (always 1)
        guard let name = body.readSFTPString() else { throw SFTPError.unexpectedResponse }
        return name
    }

    /// List a directory. `.`/`..` are filtered out.
    func listDirectory(_ path: String) async throws -> [SFTPFile] {
        let openResp = try await request(.opendir) { $0.writeSFTPString(path) }.get()
        guard openResp.type == PacketType.handle.rawValue else { try expectOK(openResp); throw SFTPError.unexpectedResponse }
        var hb = openResp.body
        guard let handle = hb.readSFTPBytes() else { throw SFTPError.unexpectedResponse }
        defer { Task { try? await self.closeHandle(handle) } }

        var files: [SFTPFile] = []
        while true {
            let resp = try await request(.readdir) { $0.writeSFTPRawString(handle) }.get()
            if resp.type == PacketType.status.rawValue { break }   // EOF (or error → treat as end)
            guard resp.type == PacketType.name.rawValue else { throw SFTPError.unexpectedResponse }
            var body = resp.body
            let count = body.readInteger(as: UInt32.self) ?? 0
            for _ in 0..<count {
                guard let name = body.readSFTPString() else { break }
                _ = body.readSFTPString()                          // longname (unused)
                let attrs = body.readSFTPAttributes()
                if name == "." || name == ".." { continue }
                files.append(SFTPFile(name: name, attributes: attrs))
            }
        }
        return files
    }

    /// Read an entire file into memory. Intended for previewing/downloading
    /// reasonably sized files.
    func readFile(_ path: String) async throws -> Data {
        let openResp = try await request(.open) {
            $0.writeSFTPString(path)
            $0.writeInteger(OpenFlags.read)
            $0.writeInteger(UInt32(0))                            // empty attrs
        }.get()
        guard openResp.type == PacketType.handle.rawValue else { try expectOK(openResp); throw SFTPError.unexpectedResponse }
        var hb = openResp.body
        guard let handle = hb.readSFTPBytes() else { throw SFTPError.unexpectedResponse }
        defer { Task { try? await self.closeHandle(handle) } }

        var data = Data()
        var offset: UInt64 = 0
        while true {
            let readOffset = offset   // immutable copy for the @Sendable closure
            let resp = try await request(.read) {
                $0.writeSFTPRawString(handle)
                $0.writeInteger(readOffset)
                $0.writeInteger(self.chunkSize)
            }.get()
            if resp.type == PacketType.status.rawValue { break }  // EOF
            guard resp.type == PacketType.data.rawValue else { throw SFTPError.unexpectedResponse }
            var body = resp.body
            guard let chunk = body.readSFTPData(), !chunk.isEmpty else { break }  // empty DATA → treat as EOF (don't spin)
            data.append(chunk)
            offset += UInt64(chunk.count)
            // A short read (< chunkSize) is fine — keep going; the loop ends on
            // a STATUS(EOF) or a zero-length DATA, never on a partial chunk.
        }
        return data
    }

    /// Write (create/truncate) a file from memory.
    func writeFile(_ data: Data, to path: String) async throws {
        let openResp = try await request(.open) {
            $0.writeSFTPString(path)
            $0.writeInteger(OpenFlags.write | OpenFlags.creat | OpenFlags.trunc)
            $0.writeInteger(UInt32(0))                            // empty attrs
        }.get()
        guard openResp.type == PacketType.handle.rawValue else { try expectOK(openResp); throw SFTPError.unexpectedResponse }
        var hb = openResp.body
        guard let handle = hb.readSFTPBytes() else { throw SFTPError.unexpectedResponse }
        defer { Task { try? await self.closeHandle(handle) } }

        var offset: UInt64 = 0
        var index = 0
        while index < data.count {
            let end = min(index + Int(chunkSize), data.count)
            let slice = data.subdata(in: index..<end)
            let writeOffset = offset   // immutable copy for the @Sendable closure
            let resp = try await request(.write) {
                $0.writeSFTPRawString(handle)
                $0.writeInteger(writeOffset)
                $0.writeSFTPData(slice)
            }.get()
            try expectOK(resp)
            offset += UInt64(slice.count)
            index = end
        }
    }

    func makeDirectory(_ path: String) async throws {
        let resp = try await request(.mkdir) {
            $0.writeSFTPString(path)
            $0.writeInteger(UInt32(0))                            // empty attrs
        }.get()
        try expectOK(resp)
    }

    func removeDirectory(_ path: String) async throws {
        try expectOK(try await request(.rmdir) { $0.writeSFTPString(path) }.get())
    }

    func removeFile(_ path: String) async throws {
        try expectOK(try await request(.remove) { $0.writeSFTPString(path) }.get())
    }

    func rename(_ from: String, to: String) async throws {
        try expectOK(try await request(.rename) {
            $0.writeSFTPString(from)
            $0.writeSFTPString(to)
        }.get())
    }

    func stat(_ path: String) async throws -> SFTPFileAttributes {
        let resp = try await request(.stat) { $0.writeSFTPString(path) }.get()
        guard resp.type == PacketType.attrs.rawValue else { try expectOK(resp); throw SFTPError.unexpectedResponse }
        var body = resp.body
        return body.readSFTPAttributes()
    }

    private func closeHandle(_ handle: [UInt8]) async throws {
        _ = try? await request(.close) { $0.writeSFTPRawString(handle) }.get()
    }
}

// MARK: - File metadata

/// Parsed SFTP file attributes (the subset we use).
struct SFTPFileAttributes: Equatable, Hashable, Sendable {
    var size: UInt64?
    var permissions: UInt32?
    var mtime: UInt32?

    /// POSIX file-type bits live in the top of the mode word.
    var isDirectory: Bool { permissions.map { ($0 & 0o170000) == 0o040000 } ?? false }
    var isSymlink: Bool   { permissions.map { ($0 & 0o170000) == 0o120000 } ?? false }
}

/// A directory entry.
struct SFTPFile: Identifiable, Equatable, Hashable, Sendable {
    var name: String
    var attributes: SFTPFileAttributes
    var id: String { name }
    var isDirectory: Bool { attributes.isDirectory }
}

// MARK: - ByteBuffer SFTP helpers

private extension ByteBuffer {
    /// Write an SFTP "string": uint32 length + bytes.
    mutating func writeSFTPString(_ s: String) {
        let bytes = Array(s.utf8)
        writeInteger(UInt32(bytes.count))
        writeBytes(bytes)
    }
    /// Write raw bytes framed as an SFTP string (used for opaque handles).
    mutating func writeSFTPRawString(_ bytes: [UInt8]) {
        writeInteger(UInt32(bytes.count))
        writeBytes(bytes)
    }
    /// Write file data framed as an SFTP string.
    mutating func writeSFTPData(_ data: Data) {
        writeInteger(UInt32(data.count))
        writeBytes(data)
    }

    mutating func readSFTPString() -> String? {
        guard let len = readInteger(as: UInt32.self),
              let bytes = readBytes(length: Int(len)) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
    mutating func readSFTPBytes() -> [UInt8]? {
        guard let len = readInteger(as: UInt32.self),
              let bytes = readBytes(length: Int(len)) else { return nil }
        return bytes
    }
    mutating func readSFTPData() -> Data? {
        guard let len = readInteger(as: UInt32.self),
              let bytes = readBytes(length: Int(len)) else { return nil }
        return Data(bytes)
    }

    /// Read an SFTP ATTRS structure (v3 layout).
    mutating func readSFTPAttributes() -> SFTPFileAttributes {
        var attrs = SFTPFileAttributes()
        guard let flags = readInteger(as: UInt32.self) else { return attrs }
        if flags & 0x00000001 != 0 { attrs.size = readInteger(as: UInt64.self) }
        if flags & 0x00000002 != 0 { _ = readInteger(as: UInt32.self); _ = readInteger(as: UInt32.self) } // uid/gid
        if flags & 0x00000004 != 0 { attrs.permissions = readInteger(as: UInt32.self) }
        if flags & 0x00000008 != 0 { _ = readInteger(as: UInt32.self); attrs.mtime = readInteger(as: UInt32.self) } // atime/mtime
        if flags & 0x80000000 != 0 {                                  // extended attrs — skip
            let count = readInteger(as: UInt32.self) ?? 0
            for _ in 0..<count { _ = readSFTPString(); _ = readSFTPString() }
        }
        return attrs
    }
}

// MARK: - SSHClient integration

extension SSHClient {
    /// Open an SFTP subsystem channel on this connection and hand back a
    /// ready client (INIT/VERSION handshake completed).
    func openSFTP() async throws -> SFTPClient {
        guard let parent = sftpParentChannel else { throw SSHError.notConnected }

        let client = SFTPClient()
        let handler = SFTPInboundHandler(
            onPacket: { [weak client] type, buf in client?.handlePacket(type: type, payload: buf) },
            onClose:  { [weak client] err in client?.handleClose(err) }
        )

        let promise = parent.eventLoop.makePromise(of: (any Channel).self)
        try await parent.eventLoop.submit {
            let sshHandler = try parent.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
            sshHandler.createChannel(promise, channelType: .session) { childChannel, _ in
                childChannel.eventLoop.makeCompletedFuture {
                    try childChannel.pipeline.syncOperations.addHandler(handler)
                }
            }
        }.get()
        let child = try await promise.futureResult.get()

        let subsystem = SSHChannelRequestEvent.SubsystemRequest(subsystem: "sftp", wantReply: true)
        try await child.triggerUserOutboundEvent(subsystem)

        client.attach(channel: child)
        try await client.initialize().get()
        return client
    }
}

// MARK: - Inbound framing handler

/// Frames length-prefixed SFTP packets out of the SSH channel byte stream and
/// hands (type, payload-after-type) to the client.
private final class SFTPInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData

    private let onPacket: (UInt8, ByteBuffer) -> Void
    private let onClose: ((any Error)?) -> Void
    private var acc: ByteBuffer?

    init(onPacket: @escaping (UInt8, ByteBuffer) -> Void, onClose: @escaping ((any Error)?) -> Void) {
        self.onPacket = onPacket
        self.onClose = onClose
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard channelData.type == .channel,
              case .byteBuffer(var incoming) = channelData.data else { return }
        if acc == nil { acc = context.channel.allocator.buffer(capacity: incoming.readableBytes) }
        acc!.writeBuffer(&incoming)
        frame()
    }

    private func frame() {
        guard acc != nil else { return }
        while acc!.readableBytes >= 4 {
            let lenIndex = acc!.readerIndex
            guard let len = acc!.getInteger(at: lenIndex, as: UInt32.self), len >= 1 else { break }
            let total = 4 + Int(len)
            guard acc!.readableBytes >= total else { break }
            acc!.moveReaderIndex(forwardBy: 4)
            let type = acc!.readInteger(as: UInt8.self)!
            // Safe: we verified `readableBytes >= 4 + len` above, and consumed
            // 5 (length + type), so `len - 1` bytes remain to slice.
            let payload = acc!.readSlice(length: Int(len) - 1)!
            onPacket(type, payload)
        }
        acc!.discardReadBytes()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        onClose(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        onClose(nil)
    }
}
