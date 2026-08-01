import ActivityKit
import Foundation

/// Live Activity 属性（主 App 与 FitCoachWidget 共享，project.yml 中两个 target 都引入此文件）
struct FitnessAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: String          // idle / exercising / resting / finished
        var exerciseName: String   // 当前动作名
        var setNumber: Int         // 第几组
        var totalSets: Int         // 该动作总组数
        var timeRemaining: Int     // 休息剩余秒数
        var completedCount: Int    // 已完成组数
        var totalCount: Int        // 本次训练总组数
    }
}
