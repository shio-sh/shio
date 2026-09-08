import Foundation

/// Parser for tmux **control mode** (`tmux -CC`).
///
/// In control mode tmux stops drawing a screen and instead speaks a line-based
/// protocol: every pane's bytes arrive tagged with a pane id, and structural
/// changes (windows added, renamed, closed; the active pane moving; layout
/// changes) arrive as explicit notifications. That is the difference between
/// *knowing* a session has three windows and guessing it by scraping a status
/// line — which is why iTerm2, cmux and rootshell all drive tmux this way.
///
/// This type is deliberately pure: bytes in, events out, no I/O and no UI. It
/// is not wired into the live terminal path yet; it exists so the protocol work
/// can be proven in isolation before anything depends on it.
///
/// Two properties matter for correctness over SSH:
///
/// 1. **Chunk-independence.** Bytes arrive in arbitrary pieces, so a
///    notification can be split across two reads. The parser buffers a partial
///    trailing line and resumes on the next `feed`.
/// 2. **Byte fidelity.** `%output` payloads are terminal bytes, not text — an
///    escape sequence can be cut mid-way and invalid UTF-8 is normal. Payloads
///    therefore decode to `[UInt8]` and are never round-tripped through `String`.
enum TmuxControl {

    /// One protocol event. Unrecognized notifications become `.unhandled`
    /// rather than being dropped or trapped: tmux adds notifications over time
    /// and an older client must degrade, not die.
    enum Event: Equatable {
        /// A pane produced output. `bytes` is already octal-unescaped.
        case output(pane: String, bytes: [UInt8])
        /// Start of a command's response block.
        case begin(time: Int, number: Int, flags: Int)
        /// End of a command's response block (`error: true` for `%error`).
        case end(time: Int, number: Int, flags: Int, error: Bool)
        /// A line of a command's response, between `%begin` and `%end`.
        case blockLine(String)

        case windowAdd(window: String)
        case windowClose(window: String)
        case windowRenamed(window: String, name: String)
        case windowPaneChanged(window: String, pane: String)
        case layoutChange(window: String, layout: String)
        case unlinkedWindowAdd(window: String)
        case unlinkedWindowClose(window: String)

        case sessionChanged(session: String, name: String)
        case sessionRenamed(name: String)
        case sessionWindowChanged(session: String, window: String)
        case sessionsChanged

        case clientDetached(client: String)
        case clientSessionChanged(client: String, session: String, name: String)

        case paneModeChanged(pane: String)
        case paused(pane: String)
        case continued(pane: String)

        case message(String)
        case configError(String)
        /// tmux is exiting; the session is over for this client.
        case exit(reason: String?)
        /// A notification this parser doesn't model. Carries the raw line.
        case unhandled(String)
    }

    /// Incremental, stream-safe parser. Feed it whatever arrives; it returns the
    /// events that are complete. Not thread-safe by itself — own it from one
    /// place (a session actor), as the SSH read loop already is.
    struct Parser {
        /// Bytes of a line not yet terminated by \n.
        private var pending: [UInt8] = []
        /// Inside a %begin…%end block, non-notification lines are block content.
        private var inBlock = false

        init() {}

        mutating func feed(_ incoming: [UInt8]) -> [Event] {
            var events: [Event] = []
            for byte in incoming {
                if byte == UInt8(ascii: "\n") {
                    events.append(contentsOf: consume(line: pending))
                    pending.removeAll(keepingCapacity: true)
                } else {
                    pending.append(byte)
                }
            }
            return events
        }

        mutating func feed(_ text: String) -> [Event] { feed(Array(text.utf8)) }

        // MARK: line handling

        private mutating func consume(line raw: [UInt8]) -> [Event] {
            // Trim a trailing CR so CRLF streams parse identically to LF.
            var bytes = raw
            if bytes.last == UInt8(ascii: "\r") { bytes.removeLast() }

            // Only a leading '%' can start a notification. Inside a block,
            // everything else is command output and must pass through
            // untouched — a `list-windows` line can legitimately contain '%'.
            guard bytes.first == UInt8(ascii: "%") else {
                return inBlock ? [.blockLine(Self.string(bytes))] : [.unhandled(Self.string(bytes))]
            }

            let line = Self.string(bytes)
            // %output is hot and byte-sensitive, so split it off the raw bytes
            // rather than the decoded String.
            if line.hasPrefix("%output ") || line.hasPrefix("%extended-output ") {
                return [parseOutput(bytes)].compactMap { $0 }
            }

            let parts = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard let verb = parts.first else { return [.unhandled(line)] }
            func arg(_ i: Int) -> String? { i < parts.count ? parts[i] : nil }
            func rest(from i: Int) -> String { parts.dropFirst(i).joined(separator: " ") }

            switch verb {
            case "%begin", "%end", "%error":
                let t = Int(arg(1) ?? "") ?? 0
                let n = Int(arg(2) ?? "") ?? 0
                let f = Int(arg(3) ?? "") ?? 0
                if verb == "%begin" {
                    inBlock = true
                    return [.begin(time: t, number: n, flags: f)]
                }
                inBlock = false
                return [.end(time: t, number: n, flags: f, error: verb == "%error")]

            case "%window-add":            return [.windowAdd(window: arg(1) ?? "")]
            case "%window-close":          return [.windowClose(window: arg(1) ?? "")]
            case "%window-renamed":        return [.windowRenamed(window: arg(1) ?? "", name: rest(from: 2))]
            case "%window-pane-changed":   return [.windowPaneChanged(window: arg(1) ?? "", pane: arg(2) ?? "")]
            case "%layout-change":         return [.layoutChange(window: arg(1) ?? "", layout: arg(2) ?? "")]
            case "%unlinked-window-add":   return [.unlinkedWindowAdd(window: arg(1) ?? "")]
            case "%unlinked-window-close": return [.unlinkedWindowClose(window: arg(1) ?? "")]

            case "%session-changed":        return [.sessionChanged(session: arg(1) ?? "", name: rest(from: 2))]
            case "%session-renamed":        return [.sessionRenamed(name: rest(from: 1))]
            case "%session-window-changed": return [.sessionWindowChanged(session: arg(1) ?? "", window: arg(2) ?? "")]
            case "%sessions-changed":       return [.sessionsChanged]

            case "%client-detached":        return [.clientDetached(client: arg(1) ?? "")]
            case "%client-session-changed": return [.clientSessionChanged(client: arg(1) ?? "",
                                                                          session: arg(2) ?? "",
                                                                          name: rest(from: 3))]

            case "%pane-mode-changed":     return [.paneModeChanged(pane: arg(1) ?? "")]
            case "%pause":                 return [.paused(pane: arg(1) ?? "")]
            case "%continue":              return [.continued(pane: arg(1) ?? "")]

            case "%message":               return [.message(rest(from: 1))]
            case "%config-error":          return [.configError(rest(from: 1))]
            case "%exit":
                let reason = rest(from: 1)
                return [.exit(reason: reason.isEmpty ? nil : reason)]

            default:                       return [.unhandled(line)]
            }
        }

        /// `%output %<pane> <escaped>` / `%extended-output %<pane> <age> … : <escaped>`.
        /// Operates on raw bytes so a payload that isn't valid UTF-8 survives.
        private func parseOutput(_ bytes: [UInt8]) -> Event? {
            let space = UInt8(ascii: " ")
            // verb
            guard let firstSpace = bytes.firstIndex(of: space) else { return nil }
            let verb = Self.string(Array(bytes[..<firstSpace]))
            // pane id
            let afterVerb = bytes.index(after: firstSpace)
            guard afterVerb < bytes.endIndex,
                  let secondSpace = bytes[afterVerb...].firstIndex(of: space)
            else { return nil }
            let pane = Self.string(Array(bytes[afterVerb..<secondSpace]))

            var payloadStart = bytes.index(after: secondSpace)
            if verb == "%extended-output" {
                // Skip the age and any future fields up to a lone ":" argument.
                var i = payloadStart
                var foundColon = false
                while i < bytes.endIndex {
                    guard let next = bytes[i...].firstIndex(of: space) else { break }
                    let token = Array(bytes[i..<next])
                    i = bytes.index(after: next)
                    if token == [UInt8(ascii: ":")] { foundColon = true; break }
                }
                guard foundColon else { return nil }
                payloadStart = i
            }
            guard payloadStart <= bytes.endIndex else { return nil }
            let payload = Array(bytes[payloadStart...])
            return .output(pane: pane, bytes: Self.unescapeOctal(payload))
        }

        // MARK: helpers

        /// tmux escapes non-printables *and* backslash as `\ooo` octal. Anything
        /// that isn't a well-formed triple stays literal, so a stray backslash
        /// can't eat the following bytes.
        static func unescapeOctal(_ bytes: [UInt8]) -> [UInt8] {
            var out: [UInt8] = []
            out.reserveCapacity(bytes.count)
            var i = bytes.startIndex
            let backslash = UInt8(ascii: "\\")
            func isOctal(_ b: UInt8) -> Bool { b >= UInt8(ascii: "0") && b <= UInt8(ascii: "7") }
            while i < bytes.endIndex {
                if bytes[i] == backslash, i + 3 < bytes.count,
                   isOctal(bytes[i + 1]), isOctal(bytes[i + 2]), isOctal(bytes[i + 3]) {
                    let value = (Int(bytes[i + 1] - 48) << 6)
                              | (Int(bytes[i + 2] - 48) << 3)
                              |  Int(bytes[i + 3] - 48)
                    out.append(UInt8(truncatingIfNeeded: value))
                    i += 4
                } else {
                    out.append(bytes[i])
                    i += 1
                }
            }
            return out
        }

        /// Lossy on purpose: protocol *metadata* is ASCII, and a malformed byte
        /// in a notification must not discard the line.
        fileprivate static func string(_ bytes: [UInt8]) -> String {
            String(decoding: bytes, as: UTF8.self)
        }
    }

    /// The attach command for control mode. `-C` twice (`-CC`) is control mode
    /// with echo disabled, which is what a programmatic client wants.
    static func attachCommand(session: String) -> String {
        "tmux -CC new-session -A -s \(session)\n"
    }
}
