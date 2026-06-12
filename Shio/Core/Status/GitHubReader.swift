import Foundation

/// Open pull requests for a checkout — read by riding the **machine's own `gh`**,
/// the same way `GitStatusReader` rides the machine's `git`. No in-app GitHub
/// auth, no token storage: `gh` is already logged in on the user's machines, so
/// `gh pr list` just works over the exec layer (local `Process` on the Mac, SSH
/// on a remote). Graceful everywhere — `gh` missing / not a GitHub repo / not
/// authed all degrade to "no PRs", never an error.
struct PullRequest: Codable, Equatable, Sendable, Identifiable {
    var number: Int
    var title: String
    var state: String
    var isDraft: Bool
    var headRefName: String
    var id: Int { number }
}

enum GitHubReader {
    private static let fields = "number,title,state,isDraft,headRefName"

    // MARK: Remote (SSH)

    static func prsRemote(config: SSHClient.Configuration, path: String) async -> [PullRequest] {
        let q = SSHClient.shellQuotedPath(path)
        let script = "command -v gh >/dev/null 2>&1 || exit 0; cd \(q) 2>/dev/null && gh pr list --json \(fields) --limit 20 2>/dev/null || true"
        let client = SSHClient(configuration: config)
        do {
            try await client.connect()
            let out = try await client.exec(posixScript: script, timeout: .seconds(8))
            await client.disconnect()
            return decode(out)
        } catch {
            await client.disconnect()
            return []
        }
    }

    // MARK: Local (this Mac), via Process — macOS only

    #if os(macOS)
    static func prsLocal(path: String) async -> [PullRequest] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: runLocal(path: path))
            }
        }
    }

    private static func runLocal(path: String) -> [PullRequest] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "pr", "list", "--json", fields, "--limit", "20"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return decode(String(decoding: data, as: UTF8.self))
    }
    #endif

    // MARK: Parse

    private static func decode(_ raw: String) -> [PullRequest] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PullRequest].self, from: data)) ?? []
    }
}
