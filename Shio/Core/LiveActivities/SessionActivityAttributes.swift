import ActivityKit
import Foundation

/// Attributes for an active SSH session Live Activity. Shared between
/// the main app (which starts/updates/ends the activity) and the
/// `ShioLiveActivities` widget extension (which renders it).
public struct ShioSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Coarse connection state — "connected", "reconnecting",
        /// "disconnected", "ended". Stringly typed because Codable +
        /// cross-target enum sharing in widget extensions has historically
        /// been finicky.
        public var connectionState: String
        /// Detected agent in this session ("Claude Code", "Codex", …), or nil.
        public var agentName: String?
        /// Agent activity — `AgentActivity.rawValue` ("running"/"waiting"/
        /// "finished"), or nil when no agent is detected. Stringly typed for
        /// the same cross-target reason as `connectionState`.
        public var agentActivity: String?

        public init(
            connectionState: String = "connected",
            agentName: String? = nil,
            agentActivity: String? = nil
        ) {
            self.connectionState = connectionState
            self.agentName = agentName
            self.agentActivity = agentActivity
        }
    }

    public var hostName: String
    /// When the session started, fixed for the activity's lifetime. Drives the
    /// live "Live · 12:34" timer on the lock screen / expanded island.
    public var startedAt: Date

    public init(hostName: String, startedAt: Date) {
        self.hostName = hostName
        self.startedAt = startedAt
    }
}
