import Testing
@testable import Shio

/// `GitStatus.parse` against real `git status --porcelain=v2 --branch -z`
/// shapes. In `-z` mode EVERY record is NUL-terminated, headers included —
/// these fixtures mirror that exactly.
struct GitStatusParseTests {

    /// Join records the way `-z` emits them: each one NUL-terminated.
    private func z(_ records: [String]) -> String {
        records.map { $0 + "\0" }.joined()
    }

    @Test func cleanRepoOnBranch() {
        let s = GitStatus.parse(porcelainV2: z([
            "# branch.oid 4ae22cbf9f6d4a4d9a8f0b7a3c2d1e0f4ae22cbf",
            "# branch.head main",
            "# branch.upstream origin/main",
            "# branch.ab +0 -0",
        ]))
        #expect(s.isClean)
        #expect(s.branchName == "main")
        #expect(s.upstream == "origin/main")
        #expect(s.ahead == 0)
        #expect(s.behind == 0)
    }

    @Test func aheadBehindCounts() {
        let s = GitStatus.parse(porcelainV2: z([
            "# branch.oid 4ae22cbf9f6d4a4d9a8f0b7a3c2d1e0f4ae22cbf",
            "# branch.head feature/x",
            "# branch.upstream origin/feature/x",
            "# branch.ab +3 -7",
        ]))
        #expect(s.ahead == 3)
        #expect(s.behind == 7)
    }

    @Test func stagedAndUnstagedSidesOfOneEntry() {
        // XY = "MM": modified in the index AND modified again in the worktree.
        let s = GitStatus.parse(porcelainV2: z([
            "# branch.head main",
            "1 MM N... 100644 100644 100644 aaaa bbbb Sources/App.swift",
        ]))
        #expect(s.staged == [.init(path: "Sources/App.swift", origPath: nil, change: .modified)])
        #expect(s.unstaged == [.init(path: "Sources/App.swift", origPath: nil, change: .modified)])
        #expect(s.dirtyCount == 2)
    }

    @Test func stagedOnlyAndWorktreeOnly() {
        let s = GitStatus.parse(porcelainV2: z([
            "# branch.head main",
            "1 A. N... 000000 100644 100644 0000 aaaa Added.swift",
            "1 .D N... 100644 100644 000000 bbbb cccc Deleted.swift",
        ]))
        #expect(s.staged == [.init(path: "Added.swift", origPath: nil, change: .added)])
        #expect(s.unstaged == [.init(path: "Deleted.swift", origPath: nil, change: .deleted)])
    }

    @Test func pathsWithSpacesSurviveFieldSplitting() {
        let s = GitStatus.parse(porcelainV2: z([
            "# branch.head main",
            "1 .M N... 100644 100644 100644 aaaa bbbb My File With Spaces.swift",
            "? untracked file.txt",
        ]))
        #expect(s.unstaged.first?.path == "My File With Spaces.swift")
        #expect(s.untracked == ["untracked file.txt"])
    }

    @Test func renameCarriesTheSourcePath() {
        // A `2` record's source path is its own NUL-separated token.
        let s = GitStatus.parse(porcelainV2: z([
            "# branch.head main",
            "2 R. N... 100644 100644 100644 aaaa bbbb R100 New.swift",
            "Old.swift",
        ]))
        #expect(s.staged == [.init(path: "New.swift", origPath: "Old.swift", change: .renamed)])
        #expect(s.unstaged.isEmpty)
    }

    @Test func conflictsAreFirstClass() {
        let s = GitStatus.parse(porcelainV2: z([
            "# branch.head main",
            "u UU N... 100644 100644 100644 100644 aaaa bbbb cccc Conflicted.swift",
        ]))
        #expect(s.conflicted == ["Conflicted.swift"])
        #expect(s.dirtyCount == 1)
    }

    @Test func detachedHeadCarriesShortOid() {
        let s = GitStatus.parse(porcelainV2: z([
            "# branch.oid 0123456789abcdef0123456789abcdef01234567",
            "# branch.head (detached)",
        ]))
        #expect(s.head == .detached("01234567"))
        #expect(s.branchName == nil)
    }

    @Test func unbornRepoIsUnborn() {
        // Fresh `git init`: no commits yet. branch.head still names the target.
        let s = GitStatus.parse(porcelainV2: z([
            "# branch.oid (initial)",
            "# branch.head main",
            "? README.md",
        ]))
        #expect(s.head == .unborn)
        #expect(s.untracked == ["README.md"])
    }

    @Test func unknownRecordsAreSkippedNotFatal() {
        // The parser is total: ignored (`!`) and future record types don't throw
        // or corrupt the entries around them.
        let s = GitStatus.parse(porcelainV2: z([
            "# branch.head main",
            "! ignored-dir/",
            "x some-future-record type",
            "1 .M N... 100644 100644 100644 aaaa bbbb Real.swift",
        ]))
        #expect(s.unstaged.count == 1)
        #expect(s.unstaged.first?.path == "Real.swift")
    }
}
