import Foundation
import Observation

/// Drives a single host's SFTP browsing session: owns its own SSH connection
/// + SFTP channel (separate from any terminal session), tracks the current
/// directory, and exposes file operations the browser UI calls.
@Observable
@MainActor
final class FilesViewModel {

    enum State: Equatable {
        case connecting
        case browsing
        case failed(String)
    }

    let hostName: String
    private let configuration: SSHClient.Configuration
    private let startPath: String?

    private(set) var state: State = .connecting
    private(set) var path: String = "/"
    private(set) var entries: [SFTPFile] = []

    private var client: SSHClient?
    private var sftp: SFTPClient?

    init(host: Host, startPath: String? = nil) {
        self.hostName = host.name
        self.configuration = host.makeClientConfiguration()
        self.startPath = startPath
    }

    /// Connect, open SFTP, resolve the starting directory, and list it.
    func start() async {
        state = .connecting
        do {
            let client = SSHClient(configuration: configuration)
            try await client.connect()
            let sftp = try await client.openSFTP()
            self.client = client
            self.sftp = sftp
            let home = (try? await sftp.realpath(startPath ?? ".")) ?? (startPath ?? "/")
            try await load(home)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        await client?.disconnect()
        client = nil
        sftp = nil
    }

    // MARK: Navigation

    func open(_ file: SFTPFile) async {
        guard file.isDirectory else { return }
        await loadOrFail(join(path, file.name))
    }

    func goUp() async {
        guard path != "/" else { return }
        let parent = (path as NSString).deletingLastPathComponent
        await loadOrFail(parent.isEmpty ? "/" : parent)
    }

    func refresh() async {
        await loadOrFail(path)
    }

    var canGoUp: Bool { path != "/" && !path.isEmpty }

    // MARK: Mutations

    func makeDirectory(named name: String) async {
        await mutate { try await $0.makeDirectory(self.join(self.path, name)) }
    }

    func delete(_ file: SFTPFile) async {
        let full = join(path, file.name)
        await mutate {
            if file.isDirectory { try await $0.removeDirectory(full) }
            else { try await $0.removeFile(full) }
        }
    }

    func rename(_ file: SFTPFile, to newName: String) async {
        await mutate { try await $0.rename(self.join(self.path, file.name), to: self.join(self.path, newName)) }
    }

    /// Read a file fully into memory (for preview / download).
    func read(_ file: SFTPFile) async throws -> Data {
        guard let sftp else { throw SFTPClient.SFTPError.notReady }
        return try await sftp.readFile(join(path, file.name))
    }

    /// Upload data as a new file in the current directory.
    func upload(_ data: Data, name: String) async {
        await mutate { try await $0.writeFile(data, to: self.join(self.path, name)) }
    }

    // MARK: Internals

    private func load(_ p: String) async throws {
        guard let sftp else { throw SFTPClient.SFTPError.notReady }
        var list = try await sftp.listDirectory(p)
        list.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }   // dirs first
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        entries = list
        path = p
        state = .browsing
    }

    private func loadOrFail(_ p: String) async {
        do { try await load(p) } catch { state = .failed(error.localizedDescription) }
    }

    /// Run a mutating SFTP op, then refresh the listing. Surfaces failures in
    /// `state` without tearing down the session.
    private func mutate(_ op: @escaping (SFTPClient) async throws -> Void) async {
        guard let sftp else { return }
        do {
            try await op(sftp)
            try await load(path)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func join(_ dir: String, _ name: String) -> String {
        if dir == "/" { return "/" + name }
        if dir.hasSuffix("/") { return dir + name }
        return dir + "/" + name
    }
}
