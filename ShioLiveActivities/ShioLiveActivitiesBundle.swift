import WidgetKit
import SwiftUI
import ActivityKit

@main
struct ShioLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        ShioSessionLiveActivity()
    }
}

private let shioCream = Color(red: 0.957, green: 0.933, blue: 0.875)

/// Live Activity for an active SSH session.
///
/// Design intent:
///   - Lock screen: rich view — host, live state, and the agent glance.
///   - Dynamic Island compact / minimal: deliberately just the brand kanji in
///     cream. iOS reserves green and orange in this region for the system's
///     camera / microphone privacy indicators; any colored status dot here
///     would mimic those, mislead about hardware state, and risk App Review.
///     Kanji only there.
///   - Dynamic Island expanded (long-press): a richer glance is fine — it's a
///     popover, not the privacy-indicator pill — so it carries the same
///     state + agent line as the lock screen (still no green/orange dot).
struct ShioSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShioSessionAttributes.self) { context in
            // Lock screen / banner view (rich).
            HStack(spacing: 12) {
                Text("塩")
                    .font(.custom("DotGothic16-Regular", size: 28))
                    .foregroundStyle(shioCream)
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLine(host: context.attributes.hostName, state: context.state.connectionState))
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    secondaryLine(
                        state: context.state.connectionState,
                        agentName: context.state.agentName,
                        agentActivity: context.state.agentActivity,
                        startedAt: context.attributes.startedAt
                    )
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(statusColor(for: context.state.connectionState))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color(red: 0.157, green: 0.157, blue: 0.196))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("塩")
                        .font(.custom("DotGothic16-Regular", size: 20))
                        .foregroundStyle(shioCream)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(primaryLine(host: context.attributes.hostName, state: context.state.connectionState))
                            .font(.system(.subheadline, design: .monospaced).weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        secondaryLine(
                            state: context.state.connectionState,
                            agentName: context.state.agentName,
                            agentActivity: context.state.agentActivity,
                            startedAt: context.attributes.startedAt
                        )
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                // Kanji only — never green/orange here (privacy indicators).
                Text("塩")
                    .font(.custom("DotGothic16-Regular", size: 14))
                    .foregroundStyle(shioCream)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Text("塩")
                    .font(.custom("DotGothic16-Regular", size: 14))
                    .foregroundStyle(shioCream)
            }
        }
    }

    /// Primary line — host-anchored and state-aware, so it never claims
    /// "Connected" while disconnected.
    private func primaryLine(host: String, state: String) -> String {
        switch state {
        case "connected":    return "Connected to \(host)"
        case "reconnecting": return "Reconnecting to \(host)…"
        case "disconnected": return "Lost connection to \(host)"
        case "ended":        return "Session on \(host) ended"
        default:             return "Connected to \(host)"
        }
    }

    /// Secondary line. Connection trouble takes priority over agent state —
    /// a stale "waiting on you" during a drop would mislead. When connected,
    /// show the agent glance if there is one, else a live session timer.
    @ViewBuilder
    private func secondaryLine(state: String, agentName: String?, agentActivity: String?, startedAt: Date) -> some View {
        switch state {
        case "reconnecting":
            Text("Hang tight, picking the session back up…")
        case "disconnected":
            Text("Tap to reconnect — your session is waiting.")
        case "ended":
            Text("Disconnected.")
        default:
            if let line = agentStatusText(name: agentName, activity: agentActivity) {
                Text(line)
            } else {
                Text("Live · ") + Text(startedAt, style: .timer)
            }
        }
    }

    /// Agent glance, e.g. "Claude Code · waiting on you", or nil when idle.
    private func agentStatusText(name: String?, activity: String?) -> String? {
        guard let activity, !activity.isEmpty else { return nil }
        let label: String
        switch activity {
        case "waiting":  label = "waiting on you"
        case "running":  label = "working…"
        case "finished": label = "finished — your turn"
        default:         return nil
        }
        if let name { return "\(name) · \(label)" }
        return "Agent \(label)"
    }

    /// Status dot — lock screen / expanded only, never the compact pill.
    private func statusColor(for state: String) -> Color {
        switch state {
        case "connected":    return .green
        case "reconnecting": return .yellow
        case "disconnected": return .red
        case "ended":        return .gray
        default:             return .green
        }
    }
}

// ShioSessionAttributes is shared with the main app — see
// Shio/Core/LiveActivities/SessionActivityAttributes.swift. Added to
// both targets via project.yml.
