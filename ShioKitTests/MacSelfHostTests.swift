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

    // MARK: Recognising a record this Mac wrote under an identity it has lost

    /// The bug this guards. The Mac's stored id lived in UserDefaults, so
    /// wiping the app's defaults gave it a new one — and the record carrying
    /// the old id was then orphaned, synced everywhere, and the Mac appeared
    /// twice with nothing able to merge the two.
    ///
    /// The first attempt at healing compared the record's hostname against the
    /// single address `reachableHost` returns, which prefers the tailnet IP.
    /// Records this Mac writes hold its MagicDNS *name*, so the comparison
    /// never matched and the duplicate survived the fix. Matching against every
    /// address the Mac answers to is the point.
    private let addresses: Set<String> = [
        "192.168.1.240", "100.105.49.4", "amriths-macbook-pro.tail397c05.ts.net",
    ]

    private func isPreviousSelf(name: String = "amriths-macbook-pro",
                                user: String = "amrith",
                                hostname: String = "amriths-macbook-pro.tail397c05.ts.net",
                                deviceID: String? = "071FA875-BC5E-40D4-993F-E71B63202680",
                                addresses: Set<String>? = nil) -> Bool {
        MacSelfHost.isPreviousSelf(
            recordName: name, recordUser: user, recordHostname: hostname,
            recordDeviceID: deviceID, computerName: "amriths-macbook-pro",
            loginName: "amrith", myDeviceID: "57E558E8-6D27-4AD5-9418-E0B898A945EE",
            addresses: addresses ?? self.addresses)
    }

    @Test func claimsARecordHoldingOurTailnetName() {
        #expect(isPreviousSelf())
    }

    @Test func claimsARecordHoldingAnyAddressWeAnswerTo() {
        #expect(isPreviousSelf(hostname: "192.168.1.240"))
        #expect(isPreviousSelf(hostname: "100.105.49.4"))
        #expect(isPreviousSelf(hostname: "AMRITHS-MacBook-Pro.tail397c05.ts.net"))
    }

    /// The whole reason the address is in the test at all: two people can each
    /// have a Mac named "MacBook-Pro", and claiming the other one would hand
    /// this Mac someone else's machine and delete their record.
    @Test func refusesADifferentMacAtAnotherAddress() {
        #expect(!isPreviousSelf(hostname: "other-mac.tail397c05.ts.net"))
    }

    @Test func refusesADifferentComputerName() {
        #expect(!isPreviousSelf(name: "work-macbook"))
    }

    @Test func refusesADifferentLoginUser() {
        #expect(!isPreviousSelf(user: "someone-else"))
    }

    /// Our own record is handled by the id match, not by this.
    @Test func refusesOurOwnCurrentRecord() {
        #expect(!isPreviousSelf(deviceID: "57E558E8-6D27-4AD5-9418-E0B898A945EE"))
    }

    /// Unstamped records are adopted by a different branch, which does not need
    /// the address. Letting this one claim them too would only hide which rule
    /// actually fired.
    @Test func refusesUnstampedRecords() {
        #expect(!isPreviousSelf(deviceID: nil))
    }

    /// A Mac with no network has no addresses, and every record would otherwise
    /// have to be judged on name and login alone.
    @Test func claimsNothingWhenWeKnowNoAddresses() {
        #expect(!isPreviousSelf(addresses: []))
        #expect(!isPreviousSelf(hostname: "", addresses: [""]))
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
