import Foundation
import SwiftUI
import UserNotifications
import UIKit

/// 训练流程的唯一数据源（对应护眼项目的 TimerManager）。
/// 状态机：idle（选训练日）→ exercising（做动作，逐组确认）→ resting（组间休息倒计时）→ … → finished
@MainActor
class WorkoutManager: ObservableObject {

    enum Phase: String, Codable {
        case idle, exercising, resting, finished
    }

    // MARK: - Published state

    @Published var phase: Phase = .idle
    @Published var currentDayId: String?
    @Published var exerciseIndex = 0
    @Published var setNumber = 1                 // 当前动作的第几组（1 起）
    @Published var timeRemaining: TimeInterval = 0
    @Published var restSeconds = 75              // 组间休息时长（可调）
    @Published var logs: [ExerciseLog] = []      // 本次训练已完成记录
    @Published var darkMode = false { didSet { defaults.set(darkMode, forKey: "fitDarkMode") } }
    @Published var lastRecord: DayRecord?        // 最近一次完成的记录（庆祝页用）
    @Published var sessionStart: Date?

    var currentDay: WorkoutDay? {
        TrainingData.days.first { $0.id == currentDayId }
    }

    var currentExercise: Exercise? {
        guard let exs = currentDay?.exercises, exerciseIndex < exs.count else { return nil }
        return exs[exerciseIndex]
    }

    /// 下一动作预览（休息遮罩用）；最后一个动作时为 nil
    var nextExercise: Exercise? {
        guard let exs = currentDay?.exercises, exerciseIndex + 1 < exs.count else { return nil }
        return exs[exerciseIndex + 1]
    }

    var totalSets: Int { currentDay?.totalSets ?? 0 }

    var completedSets: Int {
        logs.reduce(0) { $0 + $1.sets.count }
    }

    /// 休息倒计时进度 0…1
    var restProgress: Double {
        restSeconds > 0 ? timeRemaining / TimeInterval(restSeconds) : 1.0
    }

    /// 本次训练总时长（秒）
    var elapsedSeconds: Int {
        guard let sessionStart else { return 0 }
        return Int(Date().timeIntervalSince(sessionStart))
    }

    private var deadline: Date?
    private var tickTimer: Timer?
    private let defaults = UserDefaults.standard

    // MARK: - Init

    init() {
        requestNotificationPermission()
        darkMode = defaults.bool(forKey: "fitDarkMode")
        let savedRest = defaults.integer(forKey: "fitRestSeconds")
        if savedRest > 0 { restSeconds = savedRest }
        loadSession()
    }

    // MARK: - Lifecycle（前后台切换，同护眼项目模式）

    func handleScenePhaseChange(to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            if phase == .resting {
                if let deadline, deadline < Date() {
                    // 休息已在后台结束 → 直接进入下一组
                    stopTicking()
                    cancelWorkoutNotifications()
                    advanceAfterRest()
                } else if let deadline {
                    timeRemaining = deadline.timeIntervalSince(Date())
                    startTicking()
                    scheduleRestEndNotification()
                }
            }
        case .background:
            if phase == .resting {
                stopTicking()          // 休息结束靠已排程的本地通知提醒
                saveSession()
            } else if phase == .exercising {
                saveSession()
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Public API

    /// 开始一个训练日
    func startWorkout(day: WorkoutDay) {
        currentDayId = day.id
        restSeconds = day.defaultRest
        defaults.set(restSeconds, forKey: "fitRestSeconds")
        exerciseIndex = 0
        setNumber = 1
        logs = [ExerciseLog(exerciseId: day.exercises[0].id, sets: [])]
        phase = .exercising
        sessionStart = Date()
        lastRecord = nil
        saveSession()
        updateLiveActivity()
    }

    /// 本组完成（录入次数与可选重量）→ 休息或完成
    func completeSet(reps: Int, weightKg: Double?) {
        guard phase == .exercising, let day = currentDay, let exercise = currentExercise else { return }

        // 记录本组
        if logs.isEmpty || logs[logs.count - 1].exerciseId != exercise.id {
            logs.append(ExerciseLog(exerciseId: exercise.id, sets: []))
        }
        logs[logs.count - 1].sets.append(SetLog(weightKg: weightKg, reps: reps))

        let isLastSetOfExercise = setNumber >= exercise.sets
        let isLastExercise = exerciseIndex >= day.exerciseIds.count - 1

        if isLastSetOfExercise && isLastExercise {
            finishWorkout()
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // 进入组间休息
        let duration = TimeInterval(restSeconds)
        deadline = Date().addingTimeInterval(duration)
        timeRemaining = duration
        phase = .resting
        saveSession()
        scheduleRestEndNotification()
        startTicking()
        updateLiveActivity()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// 跳过休息 → 直接下一组
    func skipRest() {
        guard phase == .resting else { return }
        stopTicking()
        cancelWorkoutNotifications()
        advanceAfterRest()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 更新组间休息时长（设置页）
    func updateRestSeconds(_ val: Int) {
        restSeconds = max(15, min(300, val))
        defaults.set(restSeconds, forKey: "fitRestSeconds")
    }

    /// 放弃训练（回到选训练日）
    func abandonWorkout() {
        stopTicking()
        cancelWorkoutNotifications()
        endLiveActivity()
        phase = .idle
        currentDayId = nil
        exerciseIndex = 0
        setNumber = 1
        logs = []
        deadline = nil
        sessionStart = nil
        clearSession()
    }

    /// 庆祝页「完成」→ 回到 idle
    func dismissFinished() {
        phase = .idle
        currentDayId = nil
        exerciseIndex = 0
        setNumber = 1
        logs = []
        sessionStart = nil
        clearSession()
    }

    // MARK: - 休息结束后的推进逻辑

    private func advanceAfterRest() {
        guard let day = currentDay, let exercise = currentExercise else {
            abandonWorkout()
            return
        }

        if setNumber < exercise.sets {
            // 同一动作下一组
            setNumber += 1
        } else {
            // 下一动作第一组
            exerciseIndex += 1
            setNumber = 1
            if let next = currentExercise {
                logs.append(ExerciseLog(exerciseId: next.id, sets: []))
            }
        }
        deadline = nil
        phase = .exercising
        saveSession()
        updateLiveActivity()
    }

    private func finishWorkout() {
        stopTicking()
        cancelWorkoutNotifications()
        let record = DayRecord(
            date: todayKey,
            dayId: currentDayId ?? "",
            startTime: sessionStart?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
            durationSeconds: elapsedSeconds,
            entries: logs
        )
        appendRecord(record)
        lastRecord = record
        phase = .finished
        clearSession()
        endLiveActivity()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Timer（deadline 驱动，同护眼项目）

    private func startTicking() {
        stopTicking()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let deadline = self.deadline else { return }
            let remaining = max(0, deadline.timeIntervalSinceNow)
            DispatchQueue.main.async { self.timeRemaining = remaining }
            if remaining <= 0 {
                DispatchQueue.main.async {
                    self.stopTicking()
                    self.cancelWorkoutNotifications()
                    self.advanceAfterRest()
                }
            }
        }
    }

    private func stopTicking() { tickTimer?.invalidate(); tickTimer = nil }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func scheduleRestEndNotification() {
        cancelWorkoutNotifications()
        guard let deadline, deadline > Date() else { return }
        let after = max(1, deadline.timeIntervalSince(Date()))

        let nextText: String
        if let exercise = currentExercise {
            let nextSet = setNumber < exercise.sets ? setNumber + 1 : 1
            let name = setNumber < exercise.sets
                ? exercise.name
                : (nextExercise?.name ?? "")
            nextText = "下一个：\(name) 第 \(nextSet) 组"
        } else {
            nextText = "继续训练"
        }

        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = nextText
        content.sound = UNNotificationSound(named: UNNotificationSoundName("rest_end.wav"))
        let req = UNNotificationRequest(
            identifier: "fit-rest-end",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: after, repeats: false)
        )
        UNUserNotificationCenter.current().add(req)
    }

    private func cancelWorkoutNotifications() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["fit-rest-end"])
    }

    // MARK: - Live Activity

    private func updateLiveActivity() {
        FitnessLiveActivityManager.shared.startOrUpdate(
            phase: phase.rawValue,
            exerciseName: currentExercise?.name ?? "",
            setNumber: setNumber,
            totalSets: currentExercise?.sets ?? 0,
            timeRemaining: Int(timeRemaining),
            completedCount: completedSets,
            totalCount: totalSets
        )
    }

    private func endLiveActivity() {
        FitnessLiveActivityManager.shared.end()
    }

    // MARK: - Persistence（会话恢复 + 训练记录）

    private func saveSession() {
        defaults.set(phase.rawValue, forKey: "fit_phase")
        defaults.set(currentDayId, forKey: "fit_dayId")
        defaults.set(exerciseIndex, forKey: "fit_exerciseIndex")
        defaults.set(setNumber, forKey: "fit_setNumber")
        if let deadline { defaults.set(deadline.timeIntervalSince1970, forKey: "fit_deadline") }
        else { defaults.removeObject(forKey: "fit_deadline") }
        if let sessionStart { defaults.set(sessionStart.timeIntervalSince1970, forKey: "fit_sessionStart") }
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: "fit_logs")
        }
    }

    private func loadSession() {
        guard let raw = defaults.string(forKey: "fit_phase"),
              let saved = Phase(rawValue: raw),
              saved != .idle, saved != .finished,
              let dayId = defaults.string(forKey: "fit_dayId"),
              TrainingData.days.contains(where: { $0.id == dayId }) else {
            clearSession()
            return
        }

        currentDayId = dayId
        phase = saved
        exerciseIndex = defaults.integer(forKey: "fit_exerciseIndex")
        setNumber = max(1, defaults.integer(forKey: "fit_setNumber"))
        let startTs = defaults.double(forKey: "fit_sessionStart")
        if startTs > 0 { sessionStart = Date(timeIntervalSince1970: startTs) }
        if let data = defaults.data(forKey: "fit_logs"),
           let savedLogs = try? JSONDecoder().decode([ExerciseLog].self, from: data) {
            logs = savedLogs
        }
        // 防御：索引越界则收敛到合法范围
        if let day = currentDay, exerciseIndex >= day.exerciseIds.count {
            exerciseIndex = day.exerciseIds.count - 1
        }

        if saved == .resting {
            let deadlineTs = defaults.double(forKey: "fit_deadline")
            if deadlineTs > Date().timeIntervalSince1970 {
                deadline = Date(timeIntervalSince1970: deadlineTs)
                timeRemaining = deadline!.timeIntervalSince(Date())
                startTicking()
                scheduleRestEndNotification()
            } else {
                // 休息早已结束 → 直接推进到下一组
                advanceAfterRest()
            }
        }
        updateLiveActivity()
    }

    private func clearSession() {
        ["fit_phase", "fit_dayId", "fit_exerciseIndex", "fit_setNumber",
         "fit_deadline", "fit_sessionStart", "fit_logs"]
            .forEach { defaults.removeObject(forKey: $0) }
    }

    private func appendRecord(_ record: DayRecord) {
        var list = Self.records(on: record.date, defaults: defaults)
        list.append(record)
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: "fit_records_\(record.date)")
        }
    }

    // MARK: - Records 查询（记录页用）

    static func records(on date: String, defaults: UserDefaults = .standard) -> [DayRecord] {
        guard let data = defaults.data(forKey: "fit_records_\(date)"),
              let list = try? JSONDecoder().decode([DayRecord].self, from: data) else {
            return []
        }
        return list
    }

    /// 最近 N 天的全部记录（含今天）
    static func recentRecords(days: Int, defaults: UserDefaults = .standard) -> [DayRecord] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var all: [DayRecord] = []
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            all.append(contentsOf: records(on: fmt.string(from: day), defaults: defaults))
        }
        return all
    }

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
