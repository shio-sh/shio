import WidgetKit
import SwiftUI

@main
struct ShioWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ShioHostWidget()
    }
}

/// Home-screen widget showing the user's most-recently-connected host(s)
/// as tap-to-connect targets. Driven by `WidgetSharedState`: every connect
/// in the main app pushes the host into the App Group cache, the widget
/// reloads, and the tile shows the latest hosts.
struct ShioHostWidget: Widget {
    let kind: String = "sh.shio.app.widgets.host"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HostsProvider()) { entry in
            HostsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.157, green: 0.157, blue: 0.196),
                            Color(red: 0.055, green: 0.055, blue: 0.078),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Machines")
        .description("Tap to connect to a recent machine.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

private struct HostsEntry: TimelineEntry {
    let date: Date
    let hosts: [WidgetSharedState.WidgetHost]
}

private struct HostsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HostsEntry {
        HostsEntry(date: .now, hosts: sampleHosts)
    }

    func getSnapshot(in context: Context, completion: @escaping (HostsEntry) -> Void) {
        completion(HostsEntry(
            date: .now,
            hosts: context.isPreview ? sampleHosts : WidgetSharedState.readRecentHosts()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HostsEntry>) -> Void) {
        // No periodic refresh — the main app calls
        // `WidgetCenter.shared.reloadAllTimelines()` whenever the recent
        // host list changes.
        let entry = HostsEntry(date: .now, hosts: WidgetSharedState.readRecentHosts())
        completion(Timeline(entries: [entry], policy: .never))
    }

    private var sampleHosts: [WidgetSharedState.WidgetHost] {
        [
            .init(id: "preview-1", name: "studio", lastConnectedAt: .now),
            .init(id: "preview-2", name: "laptop", lastConnectedAt: .now.addingTimeInterval(-3600)),
        ]
    }
}

// MARK: - Views

private struct HostsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HostsEntry

    var body: some View {
        if entry.hosts.isEmpty {
            emptyState
        } else if family == .systemSmall {
            singleHostView(host: entry.hosts[0])
        } else {
            multiHostList
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("塩")
                .font(.custom("DotGothic16-Regular", size: 38))
                .foregroundStyle(Color(red: 0.957, green: 0.933, blue: 0.875))
            Text("Open Shio to add a machine")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func singleHostView(host: WidgetSharedState.WidgetHost) -> some View {
        Link(destination: URL(string: "shio://connect?host=\(host.id)")!) {
            VStack(alignment: .leading, spacing: 4) {
                Text("塩")
                    .font(.custom("DotGothic16-Regular", size: 32))
                    .foregroundStyle(Color(red: 0.957, green: 0.933, blue: 0.875))
                Spacer()
                Text(host.name)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Tap to connect")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var multiHostList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("塩")
                    .font(.custom("DotGothic16-Regular", size: 22))
                    .foregroundStyle(Color(red: 0.957, green: 0.933, blue: 0.875))
                Spacer()
                Text("machines")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            ForEach(entry.hosts.prefix(3)) { host in
                Link(destination: URL(string: "shio://connect?host=\(host.id)")!) {
                    HStack {
                        Circle()
                            .fill(.white.opacity(0.3))
                            .frame(width: 5, height: 5)
                        Text(host.name)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }
        }
    }
}
