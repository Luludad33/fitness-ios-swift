import ActivityKit
import Foundation

/// 灵动岛 / 锁屏实况活动管理（单例，4 秒节流更新，同护眼项目 EyeCareLiveActivityManager）
@MainActor
class FitnessLiveActivityManager {
    static let shared = FitnessLiveActivityManager()
    private var activity: Activity<FitnessAttributes>?
    private var lastUpdateTime: Date = .distantPast
    private let updateInterval: TimeInterval = 4

    func startOrUpdate(phase: String, exerciseName: String, setNumber: Int,
                       totalSets: Int, timeRemaining: Int,
                       completedCount: Int, totalCount: Int) {
        guard phase != "idle" && phase != "finished" else { end(); return }
        let now = Date()
        if activity != nil, now.timeIntervalSince(lastUpdateTime) < updateInterval { return }
        lastUpdateTime = now

        let state = FitnessAttributes.ContentState(
            phase: phase,
            exerciseName: exerciseName,
            setNumber: setNumber,
            totalSets: totalSets,
            timeRemaining: timeRemaining,
            completedCount: completedCount,
            totalCount: totalCount
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity {
            Task { await activity.update(content) }
        } else {
            let attr = FitnessAttributes()
            do {
                activity = try Activity.request(attributes: attr, content: content, pushType: nil)
            } catch {
                print("Live Activity start failed: \(error)")
            }
        }
    }

    func end() {
        Task {
            await activity?.end(dismissalPolicy: .immediate)
            activity = nil
        }
        lastUpdateTime = .distantPast
    }
}
