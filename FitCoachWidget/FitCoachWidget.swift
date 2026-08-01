import WidgetKit
import SwiftUI
import ActivityKit

/// 训练实况活动：锁屏横幅 + 灵动岛（结构同护眼项目 EyeCareWidget）
@main
struct FitCoachWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FitnessAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.phase == "resting" ? "😮‍💨" : "🏋️")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.phase == "resting" {
                        Text(timeString(from: context.state.timeRemaining))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundColor(.orange)
                    } else {
                        Text("\(context.state.completedCount)/\(context.state.totalCount) 组")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.phase == "resting" ? "组间休息" : context.state.exerciseName)
                            .font(.subheadline)
                        Spacer()
                        Text("第 \(context.state.setNumber)/\(context.state.totalSets) 组")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } compactLeading: {
                Text(context.state.phase == "resting" ? "😮‍💨" : "🏋️")
                    .font(.system(size: 14))
            } compactTrailing: {
                if context.state.phase == "resting" {
                    Text(timeString(from: context.state.timeRemaining))
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                } else {
                    Text("\(context.state.completedCount)/\(context.state.totalCount)")
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                }
            } minimal: {
                Text(context.state.phase == "resting" ? "😮‍💨" : "🏋️")
                    .font(.system(size: 14))
            }
        }
    }

    private func timeString(from seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct LockScreenView: View {
    let context: ActivityViewContext<FitnessAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(context.state.phase == "resting" ? "😮‍💨" : "🏋️")
                    Text(context.state.phase == "resting" ? "组间休息" : context.state.exerciseName)
                        .font(.headline)
                }
                if context.state.phase == "resting" {
                    Text(timeString(from: context.state.timeRemaining))
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                } else {
                    Text("第 \(context.state.setNumber)/\(context.state.totalSets) 组")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(context.state.completedCount)/\(context.state.totalCount) 组")
                    .font(.caption)
                ProgressView(value: progressValue)
                    .frame(width: 60)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.2))
    }

    private var progressValue: Double {
        context.state.totalCount > 0
            ? Double(context.state.completedCount) / Double(context.state.totalCount)
            : 0
    }

    private func timeString(from seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
