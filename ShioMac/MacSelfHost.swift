import Foundation
import SwiftData
import Darwin
import IOKit

/// "This Mac" as a real, synced Machine (Host record), so local Mac projects
/// belong to a machine that *other* devices can SSH into — that's continuity.
///
/// Each device stores a stable `deviceID`; the Mac stamps it on its own Host
/// record. A device recognizes its OWN host (deviceID match) and opens those
/// projects locally instead of SSHing to itself; everyone else connects over
/// SSH (the phone, once QR pairing has authorized its key).
enum MacSelfHost {
    private static let deviceIDKey = "shio.mac.deviceID"

    /// Stable identity for THIS Mac.
    ///
    /// This used to be a random UUID living only in UserDefaults, which meant
    /// the Mac's identity was as durable as a preferences file. Deleting the
    /// app's defaults, resetting it, or restoring the Mac from a backup gave it
    /// a brand new id, and `ensure` below only ever adopts records with NO id —
    /// so the old record survived, synced to every device, and the Mac appeared
    /// twice forever with nothing able to merge the two.
    ///
    /// It is derived from the hardware now, which survives all of that. An
    /// existing stored value still wins, so installs that already have an
    /// identity keep it rather than forking once on upgrade.
    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: deviceIDKey) { return id }
        let id = hardwareUUID() ?? UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceIDKey)
        return id
    }

    /// The Mac's IOPlatformUUID: stable across reinstalls, defaults wipes and
    /// restores, and different on every machine.
    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(
            service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        return cf.takeRetainedValue() as? String
    }

    private static let magicDNSKey = "shio.mac.magicDNSName"

    /// The MagicDNS name this Mac last resolved for itself, remembered across
    /// launches. Resolving it shells out to `tailscale`, which is far too slow
    /// to do while deciding which records are ours, so the async upgrade below
    /// writes it here and the decision reads it from here.
    private static var cachedMagicDNSName: String? {
        get { UserDefaults.standard.string(forKey: magicDNSKey) }
        set { UserDefaults.standard.set(newValue, forKey: magicDNSKey) }
    }

    /// Every address this Mac answers to: its live IPv4 addresses plus the
    /// MagicDNS name above.
    ///
    /// Recognising a record this Mac wrote on an earlier launch takes the whole
    /// set, not one address. `reachableHost` prefers the tailnet IP, while the
    /// MagicDNS upgrade rewrites the stored hostname to the tailnet *name*, so
    /// a record this Mac wrote itself normally holds an address `reachableHost`
    /// does not return. Comparing against that single address matched nothing,
    /// and the duplicate this was meant to heal survived anyway.
    static var selfAddresses: Set<String> {
        var addrs = Set(localIPv4Addresses().map { $0.lowercased() })
        if let name = cachedMagicDNSName, !name.isEmpty { addrs.insert(name.lowercased()) }
        return addrs
    }

    /// Is this record THIS Mac, under an identity it no longer has?
    ///
    /// Pure and separated from the fetch so it can be tested. The three
    /// conditions only mean anything together: the computer name alone
    /// collides (two Macs both called "MacBook-Pro"), name plus login user
    /// still collides across two people's identically named Macs, and the
    /// address is what makes it specific. A record holding an address we
    /// currently answer to, under our computer name and our login, was written
    /// by us.
    nonisolated static func isPreviousSelf(recordName: String, recordUser: String,
                                          recordHostname: String, recordDeviceID: String?,
                                          computerName: String, loginName: String,
                                          myDeviceID: String,
                                          addresses: Set<String>) -> Bool {
        guard let recordDeviceID, recordDeviceID != myDeviceID else { return false }
        guard recordName.caseInsensitiveCompare(computerName) == .orderedSame else { return false }
        guard recordUser == loginName else { return false }
        let hostname = recordHostname.lowercased()
        return !hostname.isEmpty && addresses.contains(hostname)
    }

    /// Identity is the stamped `deviceID` ONLY — never the computer name, which
    /// collides (two Macs both default to "MacBook-Pro" and would each see the
    /// other as "this Mac", mis-routing remote projects to a local PTY and
    /// hiding the real remote machine). A remote Mac keeps its OWN deviceID, so
    /// it is correctly never us. Unstamped same-named self records (legacy /
    /// pairing-created) are consolidated by `ensure()`'s merge, which stamps the
    /// canonical record + re-points its projects — so by the time a project
    /// opens, a genuine self-record carries our deviceID.
    static func isThisMac(_ host: Host?) -> Bool {
        guard let id = host?.deviceID else { return false }
        return id == deviceID
    }

    static var computerName: String {
        ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
    }

    /// Find-or-create the one Host record that is this Mac, folding every other
    /// record that is also this Mac into it.
    ///
    /// Runs twice per launch: once from `ensure`, and again once the tailnet
    /// name resolves. The second pass is not redundant — the first cannot
    /// recognise a record stored under this Mac's MagicDNS name on a launch
    /// where that name has not been resolved yet, which is exactly the state a
    /// fresh install is in.
    @MainActor
    private static func consolidate(id: String, in context: ModelContext) -> Host {
        let all = (try? context.fetch(FetchDescriptor<Host>())) ?? []
        let loginName = NSUserName()
        // Walks the interface list, so it is computed once rather than per record.
        let addresses = selfAddresses

        // Every record that represents THIS Mac: our stamped id, OR an unstamped
        // record naming this Mac (pairing-created / pre-deviceID / a CloudKit
        // duplicate), OR one left behind by a previous identity of this Mac.
        // There can be several — e.g. the self-host plus the host the phone made
        // when it QR-paired — and they sync to every device, so the Mac shows up
        // multiple times in Machines until we collapse them.
        let mine = all.filter {
            $0.deviceID == id
                || ($0.deviceID == nil
                    && $0.name.caseInsensitiveCompare(computerName) == .orderedSame
                    // A *different* Mac that happens to share this computer
                    // name (two "MacBook Pro"s) must not get claimed — require
                    // the login user to match too.
                    && $0.username == loginName)
                || isPreviousSelf(recordName: $0.name, recordUser: $0.username,
                                  recordHostname: $0.hostname, recordDeviceID: $0.deviceID,
                                  computerName: computerName, loginName: loginName,
                                  myDeviceID: id, addresses: addresses)
        }

        let host: Host
        if let stamped = mine.first(where: { $0.deviceID == id }) {
            host = stamped
        } else if let first = mine.first {
            host = first                 // adopt an unstamped or orphaned record …
            host.deviceID = id           // … by claiming it as ours
        } else {
            host = Host(name: computerName, hostname: reachableHost ?? computerName,
                        port: 22, username: loginName, kind: .directSSH)
            host.deviceID = id
            context.insert(host)
        }

        // Collapse the rest into the canonical record: move their projects over,
        // then delete them. The deletes sync, so other devices stop showing the
        // Mac more than once.
        for dup in mine where dup !== host {
            for project in dup.projects ?? [] { project.host = host }      // legacy inverse
            for checkout in dup.checkouts ?? [] { checkout.host = host }    // project-first inverse
            context.delete(dup)
        }
        return host
    }

    /// Find-or-create the synced Host record for this Mac, refreshing its
    /// reachable address + name (these can change between launches).
    @MainActor
    @discardableResult
    static func ensure(in context: ModelContext) -> Host {
        let id = deviceID
        let host = consolidate(id: id, in: context)

        // Adopt legacy host-less checkouts that verifiably live on THIS Mac's
        // disk (pre-self-host local projects). Unadopted, they're unreachable
        // from every other device — an iPhone tap on such a repo is a silent
        // no-op. Once stamped they ride the normal path (local here, SSH from
        // elsewhere). A path this Mac doesn't have stays untouched: it may be
        // another Mac's legacy data, and guessing would mis-route it.
        let orphans = ((try? context.fetch(FetchDescriptor<ProjectCheckout>())) ?? [])
            .filter { $0.host == nil }
        for orphan in orphans {
            let expanded = (orphan.path as NSString).expandingTildeInPath
            if !expanded.isEmpty, FileManager.default.fileExists(atPath: expanded) {
                orphan.host = host
            }
        }

        host.name = computerName
        if let addr = reachableHost { host.hostname = addr }
        host.username = NSUserName()
        try? context.save()

        // Best-effort: upgrade to the stable Tailscale MagicDNS *name* (resolved
        // off-main via the tailscale CLI). The name survives tailnet IP changes
        // and is the network-independent identity; if Tailscale/CLI isn't
        // present this no-ops and the IP stands.
        upgradeToMagicDNSName()
        return host
    }

    /// Best-effort reachable IPv4 — prefer a Tailscale address (CGNAT 100.64/10,
    /// reachable off-LAN), else a private LAN address. Shared with the pairing
    /// payload so both advertise the same address.
    static var reachableHost: String? {
        let addrs = localIPv4Addresses()
        return addrs.first(where: isTailscaleIP)
            ?? addrs.first(where: isPrivateLAN)
            ?? addrs.first
    }

    /// All non-loopback IPv4 addresses on up interfaces.
    private static func localIPv4Addresses() -> [String] {
        var addrs: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buf, socklen_t(buf.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if !ip.isEmpty && ip != "127.0.0.1" { addrs.append(ip) }
            }
        }
        return addrs
    }

    /// Tailscale's CGNAT range is 100.64.0.0 – 100.127.255.255 (NOT all `100.*`,
    /// which would falsely match public/CGNAT addresses outside the tailnet).
    private static func isTailscaleIP(_ ip: String) -> Bool {
        let octets = ip.split(separator: ".").compactMap { Int($0) }
        return octets.count == 4 && octets[0] == 100 && (64...127).contains(octets[1])
    }

    private static func isPrivateLAN(_ ip: String) -> Bool {
        ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.")
    }

    /// Resolve this Mac's MagicDNS name (e.g. `mac.tail-abcd.ts.net`) and, if
    /// found, store it as the self-host's hostname. Runs off the main thread
    /// (it shells out to `tailscale`); re-fetches the host by deviceID on the
    /// main actor to stay Sendable-clean.
    @MainActor
    private static func upgradeToMagicDNSName() {
        let id = deviceID
        Task.detached {
            guard let name = tailscaleMagicDNSName() else { return }
            await MainActor.run {
                cachedMagicDNSName = name
                let ctx = ShioModelContainer.shared.mainContext
                // Consolidate again now the name is known. Records this Mac
                // wrote under its tailnet name were invisible to the pass in
                // `ensure`, which only had the interface addresses to go on —
                // so a Mac that had changed identity stayed duplicated until
                // this ran.
                let host = consolidate(id: id, in: ctx)
                if host.hostname != name { host.hostname = name }
                try? ctx.save()
            }
        }
    }

    /// `tailscale status --json` → `Self.DNSName` (trailing dot stripped), only
    /// if it's a `.ts.net` name AND the tailnet is actually up. Blocking — call
    /// off the main thread.
    ///
    /// The state check is the whole point. A stopped Tailscale still reports its
    /// cached `Self.DNSName`, so parsing the name alone let this overwrite a
    /// perfectly good LAN address with a name nothing can resolve — the Mac then
    /// advertised an unreachable host to every other device, on the same wifi,
    /// with a working address sitting right there.
    /// The decision, split out from the process plumbing so it can be tested:
    /// a MagicDNS name is only usable when the backend is Running *and* this
    /// node is Online. Either being false means the name will not resolve.
    nonisolated static func magicDNSName(fromStatus json: [String: Any]) -> String? {
        guard (json["BackendState"] as? String) == "Running" else { return nil }
        guard let selfNode = json["Self"] as? [String: Any],
              (selfNode["Online"] as? Bool) == true,
              var dns = selfNode["DNSName"] as? String, !dns.isEmpty else { return nil }
        if dns.hasSuffix(".") { dns.removeLast() }
        return dns.hasSuffix(".ts.net") ? dns : nil
    }

    nonisolated private static func tailscaleMagicDNSName() -> String? {
        let candidates = [
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        ]
        guard let bin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["status", "--json"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return magicDNSName(fromStatus: json)
        } catch {
            return nil
        }
    }
}
