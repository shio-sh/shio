import Testing
import Foundation
@testable import Shio

/// The Mac advertises one address to every other device, so choosing it wrongly
/// makes the Mac unreachable from the phone even when both sit on the same wifi.
///
/// That is not hypothetical: a stopped Tailscale still reports its cached
/// `Self.DNSName`, and the old code parsed that name without checking whether
/// the tailnet was up. The Mac then overwrote a working LAN address with a name
/// nothing could resolve, and the iPhone showed "Couldn't reach this Mac".
struct MacSelfHostTests {

    /// The exact shape `tailscale status --json` returns while stopped: the name
    /// is still there, and it is useless.
    private func status(backend: String, online: Bool,
                        dns: String = "amriths-macbook-pro.tail397c05.ts.net.") -> [String: Any] {
        ["BackendState": backend, "Self": ["Online": online, "DNSName": dns]]
    }

    @Test func acceptsTheNameOnlyWhenTheTailnetIsUp() {
        #expect(MacSelfHost.magicDNSName(fromStatus: status(backend: "Running", online: true))
                == "amriths-macbook-pro.tail397c05.ts.net")
    }

    /// The regression. Stopped, but the CLI still knows the name.
    @Test func refusesTheNameWhenTailscaleIsStopped() {
        #expect(MacSelfHost.magicDNSName(fromStatus: status(backend: "Stopped", online: false)) == nil)
    }

    /// Running but this node is not online (signed out, key expired, no route).
    @Test func refusesTheNameWhenTheNodeIsOffline() {
        #expect(MacSelfHost.magicDNSName(fromStatus: status(backend: "Running", online: false)) == nil)
    }

    @Test func refusesEveryOtherBackendState() {
        for state in ["Stopped", "NeedsLogin", "NeedsMachineAuth", "Starting", "NoState"] {
            #expect(MacSelfHost.magicDNSName(fromStatus: status(backend: state, online: true)) == nil,
                    "\(state) must not yield a usable name")
        }
    }

    @Test func stripsTheTrailingDot() {
        let name = MacSelfHost.magicDNSName(fromStatus: status(backend: "Running", online: true))
        #expect(name?.hasSuffix(".") == false)
    }

    /// Only a real tailnet name qualifies; anything else would be a LAN or
    /// search-domain name that the stored hostname already covers.
    @Test func refusesNamesThatAreNotTailnetNames() {
        #expect(MacSelfHost.magicDNSName(
            fromStatus: status(backend: "Running", online: true, dns: "amriths-macbook-pro.local.")) == nil)
    }

    @Test func survivesMissingOrMalformedFields() {
        #expect(MacSelfHost.magicDNSName(fromStatus: [:]) == nil)
        #expect(MacSelfHost.magicDNSName(fromStatus: ["BackendState": "Running"]) == nil)
        #expect(MacSelfHost.magicDNSName(
            fromStatus: ["BackendState": "Running", "Self": ["Online": true]]) == nil)
        #expect(MacSelfHost.magicDNSName(
            fromStatus: ["BackendState": "Running", "Self": ["Online": true, "DNSName": ""]]) == nil)
    }
}
