import ActivityKit
import SwiftUI
import WidgetKit

/// Widget extension that renders the cron-job Live Activity on the
/// Lock Screen and Dynamic Island.
@main
struct CronActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        CronActivityWidget()
    }
}

struct CronActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CronActivityAttributes.self) { context in
            // Lock Screen / banner presentation
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.runningJobCount)")
                        .font(.title2.bold())
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.statusText)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("iClaw Background Tasks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "clock.arrow.2.circlepath")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text("\(context.state.runningJobCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            } minimal: {
                Image(systemName: "clock.arrow.2.circlepath")
                    .foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<CronActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.statusText)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(context.state.runningJobCount) job(s) running")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }
}
