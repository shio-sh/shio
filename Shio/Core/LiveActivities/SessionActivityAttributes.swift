import ActivityKit
import Foundation

/// Attributes for an active SSH session Live Activity. Shared between
/// the main app (which starts/updates/ends the activity) and the
/// `ShioLiveActivities` widget extension (which renders it).
public struct ShioSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Most-recently-issued shell line, truncated. Surfaces on the
        /// lock screen and in the Dynamic Island expanded view.
        public var lastCommand: String?
        /// Seconds the session has been live. Drives the duration label.
        public var duration: TimeInterval
        /// Coarse connection state — "connected", "reconnecting",
        /// "disconnected". Stringly typed because Codable + cross-target
        /// enum sharing in widget extensions has historically been finicky.
        public var connectionState: String

        public init(
            lastCommand: String? = nil,
            duration: TimeInterval = 0,
            connectionState: String = "connected"
        ) {
            self.lastCommand = lastCommand
            self.duration = duration
            self.connectionState = connectionState
        }
    }

    public var hostName: String

    public init(hostName: String) {
        self.hostName = hostName
    }
}
