import Foundation

// MARK: - 训练动作

struct Exercise: Identifiable, Codable, Hashable {
    let id: String          // 英文资源名，如 "dumbbell_press"
    let name: String        // 哑铃卧推
    let muscles: String     // 目标肌群
    let equipment: String   // 器械
    let sets: Int           // 建议组数
    let repRange: String    // 建议次数区间，如 "8–12"
    let imageName: String?  // Assets 图片名（腿举机无图为 nil）
    let steps: [String]     // 动作步骤
    let cues: [String]      // 动作要领
    let mistakes: [String]  // 常见错误
    let breathing: String   // 呼吸方法
}

// MARK: - 训练日（三分化）

struct WorkoutDay: Identifiable, Hashable {
    let id: String          // push / pull / legs
    let name: String        // 推日
    let subtitle: String    // 胸 · 肩 · 三头
    let emoji: String       // 💪 / 🔥 / 💡
    let defaultRest: Int    // 默认组间休息秒数
    let restRangeText: String // "60-90 秒"
    let warmupText: String  // "5-8 分钟"
    let durationText: String // "约 45 分钟"
    let exerciseIds: [String]

    var exercises: [Exercise] {
        exerciseIds.compactMap { TrainingData.exerciseMap[$0] }
    }

    /// 总组数（所有动作组数之和）
    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets }
    }
}

// MARK: - 拉伸动作

struct StretchMove: Identifiable, Codable, Hashable {
    let id: String
    let name: String        // 股四头肌拉伸
    let target: String      // 拉伸部位
    let group: String       // 下肢 / 上肢与躯干
    let how: [String]       // 做法要点
}

// MARK: - 训练记录

struct SetLog: Codable, Hashable {
    var weightKg: Double?   // 可选重量（kg）
    var reps: Int           // 次数
}

struct ExerciseLog: Codable, Hashable {
    let exerciseId: String
    var sets: [SetLog]
}

struct DayRecord: Codable, Identifiable, Hashable {
    var id: String { date + "_" + dayId + "_\(startTime)" }
    let date: String        // yyyy-MM-dd
    let dayId: String       // push / pull / legs
    let startTime: TimeInterval // 开始时间戳
    var durationSeconds: Int
    var entries: [ExerciseLog]

    var dayName: String {
        TrainingData.days.first { $0.id == dayId }?.name ?? dayId
    }

    var totalSets: Int {
        entries.reduce(0) { $0 + $1.sets.count }
    }
}
