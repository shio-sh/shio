import Testing
import Foundation
import SwiftData
@testable import Shio

/// Machines are all your devices; only some can be dialled.
///
/// An iPhone is a machine — you own it, it belongs in the list — but iOS runs
/// no SSH server, so nothing may ever try to connect to it. The distinction is
/// direction, not importance, and it lives in exactly one predicate. These tests
/// pin that predicate and the filter every dial-out path goes through, because
/// the failure they prevent is silent: a phone offered as somewhere to put a
/// repo, or probed for git status, hangs until timeout and then reports
/// "unreachable", which is a lie.
@MainActor
struct ConnectableHostTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(for: Shio.Host.self, Project.self, ProjectCheckout.self, Repo.self, Skill.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func aPhoneIsAMachineButNotADialTarget() {
        let phone = Host(name: "Amrith's iPhone", hostname: "Amrith's iPhone",
                         username: "", kind: .clientOnly)
        #expect(phone.isConnectable == false)
    }

    @Test func everyOtherKindStaysDialable() {
        for kind in [Host.Kind.tailscale, .directSSH] {
            let host = Host(name: "box", hostname: "box.local", username: "am", kind: kind)
            #expect(host.isConnectable, "\(kind) must remain connectable")
        }
    }

    /// The kind survives a round trip through the stored string, which is what
    /// syncs. If it didn't, a phone would arrive on another device as the
    /// default kind and be treated as dialable.
    @Test func theKindSurvivesTheStoredRawValue() throws {
        let container = try container()
        let ctx = container.mainContext
        let phone = Host(name: "iPad", hostname: "iPad", username: "", kind: .clientOnly)
        ctx.insert(phone)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Shio.Host>()).first
        #expect(fetched?.kind == .clientOnly)
        #expect(fetched?.isConnectable == false)
    }

    @Test func connectableFiltersDevicesOutOfAList() {
        let mac = Host(name: "Studio", hostname: "studio.local", username: "am", kind: .directSSH)
        let phone = Host(name: "iPhone", hostname: "iPhone", username: "", kind: .clientOnly)
        let pi = Host(name: "Pi", hostname: "pi.local", username: "am", kind: .tailscale)

        let connectable = [mac, phone, pi].connectable
        #expect(connectable.count == 2)
        #expect(!connectable.contains { $0.kind == .clientOnly })
    }

    /// A checkout placed on a device must not become a status-probe target.
    @Test func theStatusProbeSkipsCheckoutsOnDevices() throws {
        let container = try container()
        let ctx = container.mainContext
        let phone = Host(name: "iPhone", hostname: "iPhone", username: "", kind: .clientOnly)
        let mac = Host(name: "Studio", hostname: "studio.local", username: "am", kind: .directSSH)
        ctx.insert(phone); ctx.insert(mac)

        let project = Project(name: "Shio", path: "")
        ctx.insert(project)
        let repo = project.addRepo(name: "shio", path: "/Users/am/shio", host: mac,
                                   cloneURL: nil, in: ctx)
        let stray = ProjectCheckout(path: "/var/mobile/shio", project: project, host: phone)
        stray.repo = repo
        ctx.insert(stray)
        try ctx.save()

        let targets = ProjectStatusStore.targets(for: [project], isLocalHost: { _ in false })
        #expect(!targets.contains { $0.path == "/var/mobile/shio" },
                "a checkout on a device must never be probed")
        #expect(targets.contains { $0.path == "/Users/am/shio" },
                "the real machine's checkout must still be probed")
    }
}
