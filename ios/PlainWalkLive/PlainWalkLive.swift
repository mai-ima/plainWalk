import ActivityKit
import WidgetKit
import SwiftUI

@main struct PlainWalkWidgetBundle: WidgetBundle {
    var body: some Widget { PlainWalkLiveActivity() }
}
struct PlainWalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: "figure.walk").font(.title2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.state.paused ? "さんぽを一時停止中" : "歩いた道が、地図になる。").font(.caption)
                    Text(String(format: "%.2f km", context.state.distance / 1000)).font(.title2.bold()).monospacedDigit()
                }
                Spacer()
                if context.state.paused { Text("一時停止").font(.caption) } else { Text(context.attributes.start, style: .timer).font(.caption).monospacedDigit() }
            }.padding(20).activityBackgroundTint(Color(white: 0.97)).activitySystemActionForegroundColor(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "figure.walk") }
                DynamicIslandExpandedRegion(.trailing) { Text(String(format: "%.2f km", context.state.distance / 1000)).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.paused ? "一時停止中 · タップして戻る" : "PlainWalk · さんぽを記録中").font(.caption)
                }
            } compactLeading: { Image(systemName: "figure.walk") }
              compactTrailing: { Text(String(format: "%.1f", context.state.distance / 1000)).font(.caption).monospacedDigit() }
              minimal: { Image(systemName: "figure.walk") }
              .widgetURL(URL(string: "plainwalkweb://record"))
        }
    }
}
