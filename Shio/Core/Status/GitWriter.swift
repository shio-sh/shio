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
        return "git -C \(p) add -A && git -C \(p) commit -m \(shellQuote(message)) && git -C \(p) push"
    }

    /// Run stage→commit→push on the checkout. Remote over SSH, local via Process.
    static func commitAndPush(path: String, config: SSHClient.Configuration?, message: String) async -> Outcome {
        let cmd = command(path: path, message: message)
        if let config {
            let client = SSHClient(configuration: config)
            do {
                try await client.connect()
                let result = try await client.execWithStatus(cmd, timeout: .seconds(40))
                await client.disconnect()
                return interpret(stdout: result.stdout, stderr: result.stderr,
                                 exitStatus: result.exitStatus, timedOut: result.timedOut)
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

    /// Verdict comes from the exit status, never from grepping the transcript
    /// — a commit message containing "error:" must not read as failure, and a
    /// timed-out or rejected push must never read as success.
    private static func interpret(stdout: String, stderr: String, exitStatus: Int?, timedOut: Bool) -> Outcome {
        let transcript = [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if timedOut {
            return .failed(transcript.isEmpty
                ? "Timed out — the push may not have completed."
                : "Timed out — the push may not have completed.\n\(transcript)")
        }
        guard let exitStatus else {
            return .failed(transcript.isEmpty
                ? "The connection closed before git finished."
                : "The connection closed before git finished.\n\(transcript)")
        }
        guard exitStatus == 0 else {
            if transcript.lowercased().contains("nothing to commit") {
                return .failed("Nothing to commit — working tree clean.")
            }
            return .failed(transcript.isEmpty ? "git exited with status \(exitStatus)." : transcript)
        }
        return .ok(transcript.isEmpty ? "Committed and pushed." : transcript)
    }

    #if os(macOS)
    private static func runLocal(_ cmd: String) async -> Outcome {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-c", cmd]
                let out = Pipe()
                let err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch { return cont.resume(returning: .failed(error.localizedDescription)) }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: interpret(
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self),
                    exitStatus: Int(p.terminationStatus),
                    timedOut: false
                ))
            }
        }
    }
    #endif

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
