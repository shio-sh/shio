import WidgetKit
import SwiftUI

@main
struct ShioWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ShioHostWidget()
    }
}

/// Home screen widget: tap to connect to a saved host.
/// Brick 10 fills this in. Brick 1 ships an empty shell that compiles.
struct ShioHostWidget: Widget {
    let kind: String = "sh.shio.app.widgets.host"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { entry in
            PlaceholderEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Host")
        .description("Tap to connect to a saved Mac.")
        .supportedFamilies([.systemSmall])
    }
}

private struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

private struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: .now)
    }
    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}

private struct PlaceholderEntryView: View {
    let entry: PlaceholderEntry
    var body: some View {
        Text("塩")
            .font(.custom("DotGothic16-Regular", size: 32))
    }
}
