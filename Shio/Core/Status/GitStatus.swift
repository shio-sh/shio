import Foundation

/// Parsed `git status --porcelain=v2 --branch -z` for one checkout. Pure value
/// type + a total parser (never throws; unknown records are skipped) so it can be
/// unit-tested without git or a network. See `GitStatusReader` for the commands.
struct GitStatus: Codable, Equatable, Sendable {

    enum HeadState: Codable, Equatable, Sendable {
        case branch(String)     // # branch.head <name>
        case detached(String)   // # branch.head (detached) — carries the short oid
        case unborn             // # branch.oid (initial) — fresh repo, no commits
    }

    struct Entry: Codable, Equatable, Sendable {
        enum Change: String, Codable, Sendable {
            case added, modified, deleted, renamed, copied, typeChanged, unmerged, unknown
        }
        var path: String
        var origPath: String?   // rename/copy source
        var change: Change
    }

    var head: HeadState
    var upstream: String?       // nil = no upstream tracking branch
    var ahead: Int
    var behind: Int
    var staged: [Entry]         // index-side (X) changes
    var unstaged: [Entry]       // worktree-side (Y) changes
    var untracked: [String]
    var conflicted: [String]

    var dirtyCount: Int { staged.count + unstaged.count + untracked.count + conflicted.count }
    var isClean: Bool { dirtyCount == 0 }

    /// The branch name when on a branch, else nil (detached / unborn).
    var branchName: String? {
        if case .branch(let n) = head { return n }
        return nil
    }
}

extension GitStatus {

    /// Parse the NUL-delimited output of `status --porcelain=v2 --branch -z`.
    /// In `-z` mode EVERY record is NUL-terminated, including the `# branch.*`
    /// headers (verified against real git output) — so we split the whole stream
    /// on NUL. Rename/copy (`2`) entries consume a second token for the source path.
    static func parse(porcelainV2 raw: String) -> GitStatus {
        var headName: String?
        var detachedOid: String?
        var unborn = false
        var upstream: String?
        var ahead = 0, behind = 0
        var staged: [Entry] = [], unstaged: [Entry] = []
        var untracked: [String] = [], conflicted: [String] = []

        let tokens = raw.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var i = 0
        while i < tokens.count {
            let t = tokens[i]; i += 1

            if t.hasPrefix("# ") {
                let kv = t.dropFirst(2).split(separator: " ", maxSplits: 1).map(String.init)
                guard let key = kv.first else { continue }
                let val = kv.count > 1 ? kv[1] : ""
                switch key {
                case "branch.oid":
                    if val == "(initial)" { unborn = true }
                    else { detachedOid = String(val.prefix(8)) }
                case "branch.head":
                    if val == "(detached)" { headName = nil }
                    else { headName = val }
                case "branch.upstream":
                    upstream = val.isEmpty ? nil : val
                case "branch.ab":
                    for f in val.split(separator: " ") {
                        if f.hasPrefix("+") { ahead = Int(f.dropFirst()) ?? 0 }
                        else if f.hasPrefix("-") { behind = Int(f.dropFirst()) ?? 0 }
                    }
                default:
                    break
                }
                continue
            }

            switch t.first {
            case "1":
                // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
                let f = t.split(separator: " ", maxSplits: 8).map(String.init)
                guard f.count >= 9 else { break }
                addEntry(xy: f[1], path: f[8], origPath: nil, &staged, &unstaged)
            case "2":
                // 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <score> <path> \0 <origPath>
                let f = t.split(separator: " ", maxSplits: 9).map(String.init)
                guard f.count >= 10 else { break }
                var orig: String?
                if i < tokens.count { orig = tokens[i]; i += 1 }
                addEntry(xy: f[1], path: f[9], origPath: orig, &staged, &unstaged)
            case "u":
                // u <xy> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
                let f = t.split(separator: " ", maxSplits: 10).map(String.init)
                if f.count >= 11 { conflicted.append(f[10]) }
            case "?":
                untracked.append(String(t.dropFirst(2)))
            default:
                break // "!" ignored, anything else skipped
            }
        }

        let head: HeadState
        if unborn { head = .unborn }
        else if let name = headName { head = .branch(name) }
        else { head = .detached(detachedOid ?? "") }

        return GitStatus(head: head, upstream: upstream, ahead: ahead, behind: behind,
                         staged: staged, unstaged: unstaged,
                         untracked: untracked, conflicted: conflicted)
    }

    private static func addEntry(xy: String, path: String, origPath: String?,
                                 _ staged: inout [Entry], _ unstaged: inout [Entry]) {
        let chars = Array(xy)
        guard chars.count == 2 else { return }
        if chars[0] != "." {
            staged.append(Entry(path: path, origPath: origPath, change: change(chars[0])))
        }
        if chars[1] != "." {
            unstaged.append(Entry(path: path, origPath: origPath, change: change(chars[1])))
        }
    }

    private static func change(_ c: Character) -> Entry.Change {
        switch c {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "T": return .typeChanged
        case "U": return .unmerged
        default:  return .unknown
        }
    }
}

/// The result of probing one checkout — every failure is first-class so the UI
/// degrades gracefully instead of guessing.
enum GitProbe: Equatable, Sendable {
    case ok(GitStatus)
    case notARepo
    case gitMissing
    case timedOut
    case failed(exit: Int32, stderrTail: String)
    case unreachable(String)
}
