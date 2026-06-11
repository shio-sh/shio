import Foundation

/// Stage + commit + push a checkout — the write side of the git engine, run the
/// same way as the reads (local `Process` on the Mac, SSH on a remote). Every
/// call is built from one explicit command string that the UI shows the user
/// *before* running it, so a push is never a surprise.
enum GitWriter {
    enum Outcome: Equatable {
        case ok(String)        // trailing output (e.g. the push summary)
        case failed(String)    // stderr / reason
    }

    /// A human-readable preview of what will run (shown in the confirm sheet).
    static func previewCommand(message: String) -> String {
        "git add -A && git commit -m \(shellQuote(message)) && git push"
    }

    /// The actual command, scoped to `path` with `git -C`.
    private static func command(path: String, message: String) -> String {
        let p = shellQuote(path)
        return "git -C \(p) add -A && git -C \(p) commit -m \(shellQuote(message)) && git -C \(p) push 2>&1"
    }

    /// Run stage→commit→push on the checkout. Remote over SSH, local via Process.
    static func commitAndPush(path: String, config: SSHClient.Configuration?, message: String) async -> Outcome {
        let cmd = command(path: path, message: message)
        if let config {
            let client = SSHClient(configuration: config)
            do {
                try await client.connect()
                let out = try await client.exec(cmd, timeout: .seconds(40))
                await client.disconnect()
                return interpret(out)
            } catch {
                await client.disconnect()
                return .failed(error.localizedDescription)
            }
        } else {
            #if os(macOS)
            return await runLocal(cmd)
            #else
            return .failed("No local shell on this device.")
            #endif
        }
    }

    /// `git push` exits 0 on success; we surfaced 2>&1, so a clean run still
    /// carries useful text. Heuristic failure detection for the common cases.
    private static func interpret(_ out: String) -> Outcome {
        let t = out.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if lower.contains("nothing to commit") {
            return .failed("Nothing to commit — working tree clean.")
        }
        if lower.contains("fatal:") || lower.contains("error:") || lower.contains("rejected") {
            return .failed(t.isEmpty ? "git reported an error." : t)
        }
        return .ok(t.isEmpty ? "Committed and pushed." : t)
    }

    #if os(macOS)
    private static func runLocal(_ cmd: String) async -> Outcome {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-c", cmd]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do { try p.run() } catch { return cont.resume(returning: .failed(error.localizedDescription)) }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: interpret(String(decoding: data, as: UTF8.self)))
            }
        }
    }
    #endif

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
