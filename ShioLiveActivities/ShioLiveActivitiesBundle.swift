import WidgetKit
import SwiftUI
import ActivityKit

@main
struct ShioLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        ShioSessionLiveActivity()
    }
}

/// Live Activity for an active SSH session. Brick 9 fills this in.
/// Brick 1 ships an empty shell that compiles.
struct ShioSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShioSessionAttributes.self) { context in
            // Lock screen view
            HStack {
                Text("塩")
                    .font(.system(size: 20))
                VStack(alignment: .leading) {
                    Text(context.attributes.hostName)
                        .font(.headline)
                    Text(context.state.lastCommand ?? "Connected")
                        .font(.caption)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("塩")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.hostName)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let cmd = context.state.lastCommand {
                        Text(cmd)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Text("塩")
            } compactTrailing: {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            } minimal: {
                Text("塩")
            }
        }
    }
}

public struct ShioSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var lastCommand: String?
        public var duration: TimeInterval
        public var connectionState: String

        public init(lastCommand: String? = nil, duration: TimeInterval = 0, connectionState: String = "connected") {
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
