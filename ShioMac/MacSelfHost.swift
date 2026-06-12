import Foundation
import SwiftData
import Darwin

/// "This Mac" as a real, synced Machine (Host record), so local Mac projects
/// belong to a machine that *other* devices can SSH into — that's continuity.
///
/// Each device stores a stable `deviceID`; the Mac stamps it on its own Host
/// record. A device recognizes its OWN host (deviceID match) and opens those
/// projects locally instead of SSHing to itself; everyone else connects over
/// SSH (the phone, once QR pairing has authorized its key).
enum MacSelfHost {
    private static let deviceIDKey = "shio.mac.deviceID"

    /// Stable identity for THIS Mac (generated once, persisted).
    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: deviceIDKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceIDKey)
        return id
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

    /// Find-or-create the synced Host record for this Mac, refreshing its
    /// reachable address + name (these can change between launches).
    @MainActor
    @discardableResult
    static func ensure(in context: ModelContext) -> Host {
        let id = deviceID
        let all = (try? context.fetch(FetchDescriptor<Host>())) ?? []

        // Every record that represents THIS Mac: our stamped id, OR an unstamped
        // record naming this Mac (pairing-created / pre-deviceID / a CloudKit
        // duplicate). There can be several — e.g. the self-host plus the host the
        // phone made when it QR-paired — and they sync to every device, so the
        // Mac shows up multiple times in Machines until we collapse them.
        let mine = all.filter {
            $0.deviceID == id
                || ($0.deviceID == nil
                    && $0.name.caseInsensitiveCompare(computerName) == .orderedSame
                    // A *different* Mac that happens to share this computer
                    // name (two "MacBook Pro"s) must not get claimed — require
                    // the login user to match too.
                    && $0.username == NSUserName())
        }

        let host: Host
        if let stamped = mine.first(where: { $0.deviceID == id }) {
            host = stamped
        } else if let first = mine.first {
            host = first                 // adopt an unstamped record …
            host.deviceID = id           // … by claiming it as ours
        } else {
            host = Host(name: computerName, hostname: reachableHost ?? computerName,
                        port: 22, username: NSUserName(), kind: .directSSH)
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
                let ctx = ShioModelContainer.shared.mainContext
                guard let host = try? ctx.fetch(
                    FetchDescriptor<Host>(predicate: #Predicate { $0.deviceID == id })).first,
                      host.hostname != name else { return }
                host.hostname = name
                try? ctx.save()
            }
        }
    }

    /// `tailscale status --json` → `Self.DNSName` (trailing dot stripped), only
    /// if it's a `.ts.net` name. nil if the CLI isn't installed or Tailscale is
    /// down. Blocking — call off the main thread.
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
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let selfNode = json["Self"] as? [String: Any],
                  var dns = selfNode["DNSName"] as? String, !dns.isEmpty else { return nil }
            if dns.hasSuffix(".") { dns.removeLast() }
            return dns.hasSuffix(".ts.net") ? dns : nil
        } catch {
            return nil
        }
    }
}
