#if os(iOS)
import Foundation
import SwiftData
import UIKit

/// Registers THIS iPhone or iPad as a machine of yours.
///
/// A phone is a machine — you own it, you work on it, it belongs in the list
/// with everything else. What it cannot do is accept an incoming connection,
/// because iOS runs no SSH server. That is a fact about direction, not about
/// what counts as a machine, so the record is created with `kind: .clientOnly`
/// and every dial-out path filters on `Host.isConnectable`.
///
/// Without this, a phone actively driving your Mac was invisible from that Mac:
/// hosts were only ever things Shio connects INTO, so the device doing the
/// connecting existed nowhere. Mirrors `MacSelfHost` on the Mac side, minus
/// everything to do with being reachable — nothing ever dials this record.
enum DeviceSelfHost {

    private static let deviceIDKey = "shio.device.deviceID"

    /// Stable identity for THIS device, generated once and kept.
    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: deviceIDKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceIDKey)
        return id
    }

    /// What the user calls this device ("Amrith's iPhone").
    static var deviceName: String { UIDevice.current.name }

    static func isThisDevice(_ host: Host?) -> Bool {
        guard let id = host?.deviceID else { return false }
        return id == deviceID
    }

    /// Find-or-create this device's synced record. Idempotent; safe every launch.
    @MainActor
    @discardableResult
    static func ensure(in context: ModelContext) -> Host {
        let id = deviceID
        let all = (try? context.fetch(FetchDescriptor<Host>())) ?? []

        if let existing = all.first(where: { $0.deviceID == id }) {
            // Keep the name fresh (users rename their phones) and make sure an
            // older record created before this kind existed is corrected, or it
            // would still be offered as somewhere to connect.
            existing.name = deviceName
            if existing.kind != .clientOnly { existing.kind = .clientOnly }
            try? context.save()
            return existing
        }

        // hostname is deliberately the device name rather than an address:
        // nothing dials it, and storing a routable-looking address would invite
        // exactly the mistake this kind exists to prevent.
        let host = Host(name: deviceName, hostname: deviceName,
                        port: 22, username: "", kind: .clientOnly)
        host.deviceID = id
        host.lastConnectedAt = .now
        context.insert(host)
        try? context.save()
        return host
    }

    /// Stamp "this device was in use" so the machines list can show when each of
    /// your devices was last active, not just the ones you connect into.
    @MainActor
    static func touch(in context: ModelContext) {
        let host = ensure(in: context)
        host.lastConnectedAt = .now
        try? context.save()
    }
}
#endif
