import Foundation

/// Tiny App Group-backed cache of recently-used hosts, written by the
/// main app and read by `ShioWidgets`. The widget can't query SwiftData
/// reliably across processes, so we serialize a small list to UserDefaults
/// — name + a string-encoded persistent ID is plenty for "tap to connect."
enum WidgetSharedState {

    /// App Group identifier. Duplicated as a literal so this file can be
    /// added to the widget extension target without dragging in SwiftData
    /// and `ShioModelContainer`. Keep in sync with `HostStore.appGroup`.
    static let appGroup = "group.sh.shio.app"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    private static let recentHostsKey = "shio.widgets.recentHosts"
    private static let maxRecent = 4

    /// Lightweight host record stored across the App Group boundary.
    struct WidgetHost: Codable, Hashable, Identifiable {
        /// String-encoded PersistentIdentifier. Stable enough for the
        /// widget's "tap to connect" deep link; the main app re-resolves
        /// to a live `Host` via `FetchDescriptor`.
        var id: String
        var name: String
        var lastConnectedAt: Date
    }

    /// Push a host record to the front of the recent list. Idempotent:
    /// hitting the same id moves it to the top rather than duplicating.
    /// Takes raw fields (rather than `Host`) so the widget target can
    /// link against this file without dragging in SwiftData.
    static func recordConnect(id: String, name: String) {
        guard let defaults else { return }
        let entry = WidgetHost(id: id, name: name, lastConnectedAt: .now)
        var current = readRecentHosts()
        current.removeAll { $0.id == entry.id }
        current.insert(entry, at: 0)
        if current.count > maxRecent { current = Array(current.prefix(maxRecent)) }
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: recentHostsKey)
        }
    }

    /// Read the cached host list. Returns empty if the App Group isn't
    /// available or nothing has been recorded yet.
    static func readRecentHosts() -> [WidgetHost] {
        guard let defaults,
              let data = defaults.data(forKey: recentHostsKey),
              let list = try? JSONDecoder().decode([WidgetHost].self, from: data)
        else { return [] }
        return list
    }
}
