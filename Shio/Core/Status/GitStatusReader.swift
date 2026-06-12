import Foundation

/// Reads git status for checkouts. One batched script per host amortizes a
/// single SSH handshake across all that host's checkouts (the
/// `CrossMachineFileSearcher` connect → exec → disconnect template); this Mac's
/// own checkouts run locally via `Process`. Every git call is hardened so a
/// misconfigured host can't prompt, page, or hang.
enum GitStatusReader {

    /// Markers chosen so they never collide with git's (NUL-delimited) output.
    private static let ckMarker = "__SHIO_CK__"
    private static let bodyMarker = "__SHIO_BODY__"
    private static let exMarker = "__SHIO_EX__"
    private static let errMarker = "__SHIO_ERR__"
    private static let endMarker = "__SHIO_END__"
    private static let noGitMarker = "__SHIO_NOGIT__"
    // Agent-capture markers (a separate block appended to the same round trip).
    private static let agMarker = "__SHIO_AG__"
    private static let agBodyMarker = "__SHIO_AGB__"
    private static let agEndMarker = "__SHIO_AGE__"

    private static let gitFlags =
        "--no-optional-locks -c core.pager=cat -c color.ui=false"
    private static let gitArgs =
        ["--no-optional-locks", "-c", "core.pager=cat", "-c", "color.ui=false",
         "status", "--porcelain=v2", "--branch", "-z"]

    // MARK: - Remote (one connection, many checkouts)

    /// Probe every `path` on one host over a single SSH connection. Returns a
    /// probe per path; a path missing from the parse (truncation) → `.timedOut`.
    static func probeRemote(config: SSHClient.Configuration, paths: [String]) async -> [String: GitProbe] {
        await probeRemoteWithAgents(config: config, paths: paths).git
    }

    /// Same single round trip, but also captures any `shio-*` tmux panes on the
    /// host and classifies them — so an agent working on a machine you're *not*
    /// viewing still surfaces. Keyed by tmux session name (`shio-<scrubbed>`).
    static func probeRemoteWithAgents(config: SSHClient.Configuration, paths: [String])
    async -> (git: [String: GitProbe], agents: [String: AgentSnapshot]) {
        guard !paths.isEmpty else { return ([:], [:]) }
        let client = SSHClient(configuration: config)
        do {
            try await client.connect()
            let out = try await client.exec(posixScript: remoteScript(paths: paths), timeout: .seconds(8))
            await client.disconnect()
            let agents = parseAgents(combined: out)
            if out.contains(noGitMarker) {
                return (Dictionary(uniqueKeysWithValues: paths.map { ($0, GitProbe.gitMissing) }), agents)
            }
            var parsed = parse(combined: out)
            for p in paths where parsed[p] == nil { parsed[p] = .timedOut }
            return (parsed, agents)
        } catch {
            await client.disconnect()
            let why = error.localizedDescription
            return (Dictionary(uniqueKeysWithValues: paths.map { ($0, GitProbe.unreachable(why)) }), [:])
        }
    }

    private static func remoteScript(paths: [String]) -> String {
        // stderr's first line rides back per path so a non-zero exit can be
        // classified ("not a git repository" vs "dubious ownership" vs …)
        // instead of mapping every 128 to "not a repo".
        let blocks = paths.map { path -> String in
            let q = SSHClient.shellQuotedPath(path)
            return """
            printf '\(ckMarker)%s\(bodyMarker)' \(q)
            GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 git -C \(q) \(gitFlags) status --porcelain=v2 --branch -z 2>"$SHIO_E"
            printf '\(exMarker)%d\(errMarker)' "$?"
            head -c 160 "$SHIO_E" 2>/dev/null | tr -d '\\n\\0'
            printf '\(endMarker)'
            """
        }.joined(separator: "\n")
        let gitPart = "SHIO_E=\"${TMPDIR:-/tmp}/shio-probe-err.$$\"\n"
            + "command -v git >/dev/null 2>&1 || { printf '\(noGitMarker)'; }\n"
            + blocks + "\nrm -f \"$SHIO_E\"\n"
        // Agent capture: base64 each shio-* pane so arbitrary terminal bytes can
        // never collide with our markers. tmux absent → silently no agents.
        let agentPart = """
        if command -v tmux >/dev/null 2>&1; then
        tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^shio-' | while IFS= read -r s; do
        printf '\(agMarker)%s\(agBodyMarker)' "$s"
        tmux capture-pane -p -t "$s" 2>/dev/null | base64 | tr -d '\\n'
        printf '\(agEndMarker)'
        done
        fi
        """
        return gitPart + agentPart + "\n"
    }

    /// Pull the base64 pane captures back out and classify each via AgentDetector.
    private static func parseAgents(combined out: String) -> [String: AgentSnapshot] {
        var result: [String: AgentSnapshot] = [:]
        for chunk in out.components(separatedBy: agMarker).dropFirst() {
            guard let bR = chunk.range(of: agBodyMarker) else { continue }
            let session = String(chunk[..<bR.lowerBound])
            let after = chunk[bR.upperBound...]
            let b64 = after.components(separatedBy: agEndMarker).first ?? ""
            guard let data = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let pane = String(data: data, encoding: .utf8), !pane.isEmpty else { continue }
            let snap = AgentDetector.classify(cleanTail: AgentDetector.strip(pane))
            if snap.activity != .none { result[session] = snap }
        }
        return result
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Split the combined output into per-path probes by our markers.
    private static func parse(combined out: String) -> [String: GitProbe] {
        var result: [String: GitProbe] = [:]
        for chunk in out.components(separatedBy: ckMarker).dropFirst() {
            guard let bodyR = chunk.range(of: bodyMarker) else { continue }
            let path = String(chunk[..<bodyR.lowerBound])
            let afterBody = chunk[bodyR.upperBound...]
            guard let exR = afterBody.range(of: exMarker) else { continue }
            let body = String(afterBody[..<exR.lowerBound])
            let tail = afterBody[exR.upperBound...]
            let exitStr: String
            let stderrTail: String
            if let errR = tail.range(of: errMarker) {
                exitStr = String(tail[..<errR.lowerBound])
                stderrTail = String(tail[errR.upperBound...].components(separatedBy: endMarker).first ?? "")
            } else {
                exitStr = tail.components(separatedBy: endMarker).first ?? ""
                stderrTail = ""
            }
            let exit = Int32(exitStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
            result[path] = probe(exit: exit, body: body, stderr: stderrTail)
        }
        return result
    }

    private static func probe(exit: Int32, body: String, stderr: String = "") -> GitProbe {
        switch exit {
        case 0:
            return .ok(GitStatus.parse(porcelainV2: body))
        case 128 where stderr.isEmpty || stderr.contains("not a git repository"):
            // The common 128. Other fatals (dubious ownership, bad config)
            // also exit 128 but say so on stderr — those report as failed,
            // not as "not a repo".
            return .notARepo
        default:
            return .failed(exit: exit, stderrTail: String(stderr.prefix(160)))
        }
    }

    // MARK: - Local (this Mac), via Process — macOS only (no Process on iOS)

    #if os(macOS)
    static func probeLocal(paths: [String]) async -> [String: GitProbe] {
        var out: [String: GitProbe] = [:]
        for path in paths { out[path] = await runLocalGit(at: path) }
        return out
    }

    private static func runLocalGit(at path: String) async -> GitProbe {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: runLocalGitSync(at: path))
            }
        }
    }

    private static func runLocalGitSync(at path: String) -> GitProbe {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", path] + gitArgs
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = env
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return .gitMissing   // env/git not launchable
        }
        // Deadline: one wedged repo (hung filesystem, network mount) must not
        // stall every local status behind it forever.
        let killer = DispatchWorkItem { process.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: killer)
        // Drain BOTH pipes (stderr in parallel — an unread pipe that fills up
        // blocks git, which blocks the stdout read, which is a deadlock).
        final class ErrBox: @unchecked Sendable { var data = Data() }
        let errBox = ErrBox()
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
            drained.leave()
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        drained.wait()
        killer.cancel()
        if process.terminationReason == .uncaughtSignal {
            return .timedOut
        }
        let exit = process.terminationStatus
        let body = String(decoding: data, as: UTF8.self)
        let err = String(decoding: errBox.data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return probe(exit: exit, body: body, stderr: err)
    }
    #endif
}
