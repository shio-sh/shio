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
        let host: Host
        if let existing = all.first(where: { $0.deviceID == id }) {
            host = existing
        } else {
            host = Host(name: computerName, hostname: reachableHost ?? computerName,
                        port: 22, username: NSUserName(), kind: .directSSH)
            host.deviceID = id
            context.insert(host)
        }
        host.name = computerName
        if let addr = reachableHost { host.hostname = addr }
        host.username = NSUserName()
        try? context.save()
        return host
    }

    /// Best-effort reachable IPv4 — prefer a Tailscale address (100.64/10, so
    /// the phone can reach the Mac off-LAN), else a private LAN address. Shared
    /// with the pairing payload so both advertise the same address.
    static var reachableHost: String? {
        var addrs: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
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
        return addrs.first(where: { $0.hasPrefix("100.") })
            ?? addrs.first(where: { $0.hasPrefix("192.168.") || $0.hasPrefix("10.") || $0.hasPrefix("172.") })
            ?? addrs.first
    }
}
