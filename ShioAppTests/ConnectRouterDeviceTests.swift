import Testing
import Foundation
import SwiftData
@testable import Shio

/// The router is the single resolver behind every "jump in" entry point, so it
/// is where a device that cannot accept connections must be refused. A widget,
/// Siri phrase or deep link naming your iPhone has to resolve to nothing rather
/// than open a session that can never connect.
@MainActor
struct ConnectRouterDeviceTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(for: Shio.Host.self, Project.self, ProjectCheckout.self,
                           Repo.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Widgets, Siri and deep links all resolve through one router. Naming a
    /// device that cannot accept a connection must yield nothing rather than
    /// opening a session doomed to fail.
    @Test func theRouterWillNotRouteToADevice() throws {
        let container = try container()
        let ctx = container.mainContext
        let phone = Host(name: "iPhone", hostname: "iPhone", username: "", kind: .clientOnly)
        phone.deviceID = "phone-1"
        ctx.insert(phone)

        #expect(ConnectRouter.shared.resolveHost(ref: "phone-1", context: ctx) == nil)
        #expect(ConnectRouter.shared.resolveHost(ref: "iPhone", context: ctx) == nil)
    }

    /// …but a real machine still resolves, including when a device sits beside
    /// it in the store.
    @Test func theRouterStillResolvesRealMachines() throws {
        let container = try container()
        let ctx = container.mainContext
        let phone = Host(name: "iPhone", hostname: "iPhone", username: "", kind: .clientOnly)
        phone.deviceID = "phone-1"
        let mac = Host(name: "Studio", hostname: "studio.local", username: "am", kind: .directSSH)
        mac.deviceID = "mac-1"
        ctx.insert(phone); ctx.insert(mac)

        #expect(ConnectRouter.shared.resolveHost(ref: "mac-1", context: ctx) === mac)
        #expect(ConnectRouter.shared.resolveHost(ref: "studio.local", context: ctx) === mac)
    }
}
