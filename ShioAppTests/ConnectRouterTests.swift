import Testing
import Foundation
import SwiftData
@testable import Shio

/// ConnectRouter is the single resolver behind every "jump in" entry point
/// (push tap, widget, Siri, Handoff, shio://). These tests pin the identity
/// precedence and the tmux-session → (project, checkout) mapping over an
/// in-memory container — no CloudKit, no SSH.
@MainActor
struct ConnectRouterTests {

    /// The caller must hold the returned container for the test's lifetime —
    /// it owns the mainContext (a dropped container deallocates the context
    /// out from under SwiftData).
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Host.self, Project.self, ProjectCheckout.self, Repo.self,
            configurations: config)
    }

    // MARK: Host resolution precedence

    @Test func deviceIDWinsOverEverything() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let studio = Host(name: "Studio", hostname: "studio.local", username: "am")
        ctx.insert(studio)
        studio.deviceID = "dev-A"
        // A decoy whose *name* is the other host's deviceID — deviceID still wins.
        let decoy = Host(name: "dev-A", hostname: "decoy.local", username: "am")
        ctx.insert(decoy)
        #expect(ConnectRouter.shared.resolveHost(ref: "dev-A", context: ctx) === studio)
    }

    @Test func persistentModelIDResolvesWidgetLinks() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let a = Host(name: "Studio", hostname: "studio.local", username: "am")
        let b = Host(name: "MBP", hostname: "mbp.local", username: "am")
        ctx.insert(a); ctx.insert(b)
        #expect(ConnectRouter.shared.resolveHost(ref: "\(b.persistentModelID)", context: ctx) === b)
    }

    @Test func hostnameResolvesCaseInsensitively() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let b = Host(name: "MBP", hostname: "mbp.local", username: "am")
        ctx.insert(b)
        #expect(ConnectRouter.shared.resolveHost(ref: "MBP.LOCAL", context: ctx) === b)
    }

    @Test func displayNameIsTheLastResort() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let a = Host(name: "Studio", hostname: "studio.local", username: "am")
        ctx.insert(a)
        #expect(ConnectRouter.shared.resolveHost(ref: "studio", context: ctx) === a)
    }

    @Test func unknownRefResolvesToNothing() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(Host(name: "Studio", hostname: "studio.local", username: "am"))
        #expect(ConnectRouter.shared.resolveHost(ref: "nope", context: ctx) == nil)
    }

    // MARK: tmux session → (project, checkout)

    /// Insert first, relate second — SwiftData wants models in a context
    /// before their relationships are wired.
    private func seedProject(on host: Host, in ctx: ModelContext,
                             repoName: String) -> (Project, Repo, ProjectCheckout) {
        let project = Project(name: "Shio", path: "~/Code/shio")
        ctx.insert(project)
        let repo = Repo(name: repoName)
        ctx.insert(repo)
        repo.project = project
        let checkout = ProjectCheckout(path: "~/Code/shio")
        ctx.insert(checkout)
        checkout.project = project
        checkout.host = host
        checkout.repo = repo
        return (project, repo, checkout)
    }

    @Test func tmuxSessionMapsBackToItsCheckout() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let host = Host(name: "Studio", hostname: "studio.local", username: "am")
        ctx.insert(host)
        let (project, _, checkout) = seedProject(on: host, in: ctx, repoName: "My App")

        let hit = ConnectRouter.shared.checkout(forTmuxSession: "shio-My-App", on: host)
        #expect(hit?.0 === project)
        #expect(hit?.1 === checkout)
    }

    @Test func indexedSessionsRouteToThePrimaryCheckout() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let host = Host(name: "Studio", hostname: "studio.local", username: "am")
        ctx.insert(host)
        let (_, _, checkout) = seedProject(on: host, in: ctx, repoName: "My App")
        let hit = ConnectRouter.shared.checkout(forTmuxSession: "shio-My-App-2", on: host)
        #expect(hit?.1 === checkout)
    }

    @Test func unknownSessionsAndForeignPrefixesMissCleanly() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let host = Host(name: "Studio", hostname: "studio.local", username: "am")
        ctx.insert(host)
        _ = seedProject(on: host, in: ctx, repoName: "My App")
        #expect(ConnectRouter.shared.checkout(forTmuxSession: "shio-Other", on: host) == nil)
        #expect(ConnectRouter.shared.checkout(forTmuxSession: "tmux-My-App", on: host) == nil)
    }
}
