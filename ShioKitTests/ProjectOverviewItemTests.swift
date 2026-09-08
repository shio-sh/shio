import Testing
import Foundation
import SwiftData
@testable import Shio

/// The overview card's model, shared by the Mac and iPad zoomed-out dashboard
/// and showing the same facts as the iPhone's Home.
///
/// It is worth pinning because it is the one place three platforms agree. If a
/// project reads "clean" in the overview and "5 uncommitted" inside it, the
/// overview stops being trustworthy at a glance, which is its only job.
@MainActor
struct ProjectOverviewItemTests {

    /// The caller MUST hold this for the test's lifetime. A dropped container
    /// deallocates the mainContext out from under SwiftData and the test host
    /// crashes rather than failing — which is exactly what happened here.
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Shio.Host.self, Project.self, ProjectCheckout.self,
                           Repo.self, Skill.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func project(_ name: String, in ctx: ModelContext) -> Project {
        let p = Project(name: name, path: "")
        ctx.insert(p)
        return p
    }

    private func entry(_ path: String) -> GitStatus.Entry {
        GitStatus.Entry(path: path, origPath: nil, change: .modified)
    }

    private func row(_ name: String, machines: String, git: GitProbe?,
                     placed: Bool = true, in ctx: ModelContext, project: Project) -> RepoRowVM {
        let repo = project.addRepo(name: name, path: "/x/\(name)", host: nil,
                                   cloneURL: nil, in: ctx)
        return RepoRowVM(id: repo.persistentModelID, repo: repo, name: name,
                         machines: machines, git: git, isPlaced: placed)
    }

    @Test func aCleanProjectSaysSo() throws {
        let box = try container()
        let ctx = box.mainContext
        let p = project("Infer", in: ctx)
        let probe = GitProbe.ok(GitStatus(head: .branch("main"), upstream: "origin/main",
                                          ahead: 0, behind: 0, staged: [], unstaged: [],
                                          untracked: [], conflicted: []))
        let item = ProjectOverviewItem.make(project: p,
                                            rows: [row("infer", machines: "this mac",
                                                       git: probe, in: ctx, project: p)])
        #expect(item.headline == "⎇ main · clean")
        #expect(item.detail == "1 repo · this mac")
    }

    /// Uncommitted work is the reason to look at the overview at all, so it has
    /// to be in the headline rather than inferred from a dot.
    @Test func uncommittedWorkLeadsTheHeadline() throws {
        let box = try container()
        let ctx = box.mainContext
        let p = project("Shio", in: ctx)
        let probe = GitProbe.ok(GitStatus(head: .branch("beta-fixes"), upstream: nil,
                                          ahead: 0, behind: 0, staged: [entry("a")],
                                          unstaged: [entry("b")], untracked: ["c"], conflicted: []))
        let item = ProjectOverviewItem.make(project: p,
                                            rows: [row("shio", machines: "this mac",
                                                       git: probe, in: ctx, project: p)])
        #expect(item.headline.contains("beta-fixes"))
        #expect(item.headline.contains("uncommitted"))
        #expect(item.glance.changes == 3)
    }

    @Test func aProjectWithNoReposSaysSo() throws {
        let box = try container()
        let ctx = box.mainContext
        let p = project("Fresh", in: ctx)
        let item = ProjectOverviewItem.make(project: p, rows: [])
        #expect(item.headline == "no repos yet")
    }

    /// A repo that exists but lives nowhere must not read as a git failure.
    @Test func anUnplacedRepoSaysItIsNotOnAMachine() throws {
        let box = try container()
        let ctx = box.mainContext
        let p = project("Synced", in: ctx)
        let item = ProjectOverviewItem.make(
            project: p,
            rows: [row("synced", machines: "", git: nil, placed: false, in: ctx, project: p)])
        #expect(item.headline == "not on any machine")
    }

    /// Machines are deduplicated across repos: three repos on one Mac is one
    /// machine, not three.
    @Test func collapsesRepeatedMachineNames() throws {
        let box = try container()
        let ctx = box.mainContext
        let p = project("Shio", in: ctx)
        let rows = [
            row("app", machines: "this mac", git: nil, in: ctx, project: p),
            row("site", machines: "this mac", git: nil, in: ctx, project: p),
            row("worker", machines: "this mac · tulsi", git: nil, in: ctx, project: p),
        ]
        let item = ProjectOverviewItem.make(project: p, rows: rows)
        #expect(item.detail == "3 repos · this mac · tulsi")
    }

    @Test func countsSummedAcrossEveryRepo() throws {
        let box = try container()
        let ctx = box.mainContext
        let p = project("Multi", in: ctx)
        func dirty(_ n: Int) -> GitProbe {
            .ok(GitStatus(head: .branch("main"), upstream: nil, ahead: 0, behind: 0,
                          staged: (0..<n).map { entry("s\($0)") }, unstaged: [],
                          untracked: [], conflicted: []))
        }
        let rows = [
            row("a", machines: "this mac", git: dirty(2), in: ctx, project: p),
            row("b", machines: "this mac", git: dirty(3), in: ctx, project: p),
        ]
        let item = ProjectOverviewItem.make(project: p, rows: rows)
        #expect(item.glance.changes == 5)
        #expect(item.glance.repoCount == 2)
    }
}
