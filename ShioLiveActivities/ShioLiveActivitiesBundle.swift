import WidgetKit
import SwiftUI
import ActivityKit

@main
struct ShioLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        ShioSessionLiveActivity()
    }
}

/// Live Activity for an active SSH session.
///
/// Design intent:
///   - Lock screen: rich view. The user glances at their lock screen
///     and sees "you have a live session on <host>" — a useful reminder
///     so they know to disconnect before bed, etc.
///   - Dynamic Island: deliberately minimal — just the brand kanji in
///     cream. iOS reserves green and orange in this region for the
///     system's camera / microphone privacy indicators; rendering any
///     colored status dot here would mimic those, misleading users
///     about hardware state and inviting App Review rejection. Kanji
///     only.
struct ShioSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShioSessionAttributes.self) { context in
            // Lock screen / banner view (rich).
            HStack(spacing: 12) {
                Text("塩")
                    .font(.custom("DotGothic16-Regular", size: 28))
                    .foregroundStyle(Color(red: 0.957, green: 0.933, blue: 0.875))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected to \(context.attributes.hostName)")
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(statusText(for: context.state.connectionState))
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
                // Expanded view (shown on long-press of the pill). Kept
                // empty by design — we don't want this to be a content
                // surface for a terminal app.
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
            } compactLeading: {
                // CRITICAL: never use green or orange in the Dynamic
                // Island. iOS reserves green (camera) and orange (mic)
                // for system privacy indicators in this region — painting
                // either color here mimics those indicators and risks App
                // Review rejection AND, worse, misleads the user into
                // thinking their hardware is in use. Only the kanji,
                // only in our brand cream.
                Text("塩")
                    .font(.custom("DotGothic16-Regular", size: 14))
                    .foregroundStyle(Color(red: 0.957, green: 0.933, blue: 0.875))
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Text("塩")
                    .font(.custom("DotGothic16-Regular", size: 14))
                    .foregroundStyle(Color(red: 0.957, green: 0.933, blue: 0.875))
            }
        }
    }

    private func statusText(for state: String) -> String {
        switch state {
        case "connected":    return "Live"
        case "reconnecting": return "Reconnecting…"
        case "disconnected": return "Disconnected"
        case "ended":        return "Ended"
        default:             return state
        }
    }

    /// Status color used ONLY in the lock-screen banner — never in the
    /// Dynamic Island. The lock screen is far from the camera/mic
    /// privacy indicators, so a small colored dot here doesn't mimic
    /// system semantics.
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
