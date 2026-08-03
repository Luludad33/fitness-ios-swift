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

    // MARK: - 身体数据与设置（数据 Tab / 我的 Tab 用）

    @Published var profileName: String {        // 用户名（默认「训练者」）
        didSet { defaults.set(profileName, forKey: "fit_profileName") }
    }
    @Published var nextDayId: String {          // 下一个训练日（push/pull/legs）
        didSet { defaults.set(nextDayId, forKey: "fit_nextDay") }
    }
    @Published var weights: [WeightEntry] = []          // 体重记录（按日期升序）
    @Published var measurements: [MeasurementEntry] = [] // 围度记录（按日期升序）

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
        profileName = defaults.string(forKey: "fit_profileName") ?? "训练者"
        nextDayId = defaults.string(forKey: "fit_nextDay") ?? "push"
        if let data = defaults.data(forKey: "fit_weights"),
           let list = try? JSONDecoder().decode([WeightEntry].self, from: data) {
            weights = list
        }
        if let data = defaults.data(forKey: "fit_meas"),
           let list = try? JSONDecoder().decode([MeasurementEntry].self, from: data) {
            measurements = list
        }
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

    // MARK: - 身体数据（体重 / 围度）

    func addWeight(kg: Double, date: String) {
        weights.removeAll { $0.date == date }
        weights.append(WeightEntry(date: date, kg: kg))
        weights.sort { $0.date < $1.date }
        if weights.count > 400 { weights = Array(weights.suffix(400)) }
        saveBodyData()
    }

    func addMeasurement(_ m: MeasurementEntry) {
        measurements.removeAll { $0.date == m.date }
        measurements.append(m)
        measurements.sort { $0.date < $1.date }
        saveBodyData()
    }

    private func saveBodyData() {
        if let data = try? JSONEncoder().encode(weights) {
            defaults.set(data, forKey: "fit_weights")
        }
        if let data = try? JSONEncoder().encode(measurements) {
            defaults.set(data, forKey: "fit_meas")
        }
    }

    // MARK: - 训练前 Checklist（按日期持久化）

    func checkedChecklistItems(on date: String) -> Set<Int> {
        guard let data = defaults.data(forKey: "fit_checklist_\(date)"),
              let list = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
        return Set(list)
    }

    func setChecklistItem(_ index: Int, checked: Bool, on date: String) {
        var set = checkedChecklistItems(on: date)
        if checked { set.insert(index) } else { set.remove(index) }
        if let data = try? JSONEncoder().encode(set.sorted()) {
            defaults.set(data, forKey: "fit_checklist_\(date)")
        }
    }

    // MARK: - 下一个训练日（推→拉→腿 循环）

    func advanceNextDay(from dayId: String?) {
        let order = ["push", "pull", "legs"]
        guard let dayId, let idx = order.firstIndex(of: dayId) else {
            nextDayId = "push"
            return
        }
        nextDayId = order[(idx + 1) % order.count]
    }

    func setNextDay(_ id: String) {
        guard TrainingData.days.contains(where: { $0.id == id }) else { return }
        nextDayId = id
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
        advanceNextDay(from: currentDayId)   // 练完自动推进 推→拉→腿
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

    /// 全量记录（扫描所有 fit_records_ key，PR/导出/连续天数用）
    func allRecords() -> [DayRecord] {
        var all: [DayRecord] = []
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("fit_records_") }
        for key in keys {
            guard let data = defaults.data(forKey: key),
                  let list = try? JSONDecoder().decode([DayRecord].self, from: data) else { continue }
            all.append(contentsOf: list)
        }
        return all.sorted { $0.startTime > $1.startTime }
    }

    // MARK: - 统计（连续天数 / 本周 / PR / 容量）

    /// 连续训练天数（今天没练则从昨天起算）
    var streakCount: Int {
        let fmt = Self.dayFormatter()
        let days = Set(allRecords().map { $0.date })
        var d = Date()
        if !days.contains(fmt.string(from: d)) {
            d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d
        }
        var count = 0
        while days.contains(fmt.string(from: d)) {
            count += 1
            d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return count
    }

    /// 本周训练次数（周一起算）
    var weekCount: Int {
        let fmt = Self.dayFormatter()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date())   // 1=周日 … 7=周六
        let daysSinceMonday = (weekday + 5) % 7               // 周一=0
        guard let monday = cal.date(byAdding: .day, value: -daysSinceMonday, to: Date()) else { return 0 }
        let mondayStr = fmt.string(from: monday)
        return allRecords().filter { $0.date >= mondayStr }.count
    }

    var totalWorkouts: Int { allRecords().count }

    /// Epley 公式估算 1RM：w × (1 + r/30)
    nonisolated static func epley(_ w: Double, _ r: Int) -> Double {
        w * (1 + Double(max(1, r)) / 30)
    }

    /// 个人纪录条目（按估算 1RM 降序）
    struct PRRecord: Identifiable {
        let exercise: Exercise
        let weightKg: Double
        let reps: Int
        let date: String
        var id: String { exercise.id }
        var oneRM: Int { Int(WorkoutManager.epley(weightKg, reps).rounded()) }
    }

    var prs: [PRRecord] {
        var best: [String: (w: Double, r: Int, date: String)] = [:]
        for rec in allRecords() {
            for entry in rec.entries {
                for set in entry.sets {
                    guard let w = set.weightKg, w > 0 else { continue }
                    let r = max(1, set.reps)
                    let score = Self.epley(w, r)
                    if let cur = best[entry.exerciseId] {
                        if score > Self.epley(cur.w, max(1, cur.r)) {
                            best[entry.exerciseId] = (w, r, rec.date)
                        }
                    } else {
                        best[entry.exerciseId] = (w, r, rec.date)
                    }
                }
            }
        }
        return best.compactMap { id, v in
            guard let ex = TrainingData.exerciseMap[id] else { return nil }
            return PRRecord(exercise: ex, weightKg: v.w, reps: v.r, date: v.date)
        }
        .sorted { Self.epley($0.weightKg, $0.reps) > Self.epley($1.weightKg, $1.reps) }
    }

    /// 某动作历史最佳组（Epley 分数最高），训练录入时预填重量
    func bestSet(for exerciseId: String) -> SetLog? {
        var best: SetLog?
        var bestScore: Double = 0
        for rec in allRecords() {
            for entry in rec.entries where entry.exerciseId == exerciseId {
                for set in entry.sets {
                    guard let w = set.weightKg, w > 0 else { continue }
                    let score = Self.epley(w, set.reps)
                    if score > bestScore {
                        bestScore = score
                        best = set
                    }
                }
            }
        }
        return best
    }

    /// 训练总容量（Σ 重量×次数）
    static func volume(of record: DayRecord) -> Int {
        Int(record.entries.reduce(0.0) { acc, e in
            acc + e.sets.reduce(0.0) { $0 + (($1.weightKg ?? 0) * Double($1.reps)) }
        }.rounded())
    }

    // MARK: - 备份（导出 / 导入 / 清空）

    /// iOS 自身备份格式
    private struct BackupPackage: Codable {
        var profileName: String
        var nextDayId: String
        var weights: [WeightEntry]
        var measurements: [MeasurementEntry]
        var records: [DayRecord]
        var checklist: [String: [Int]]
    }

    /// ballast.v1（压舱石 PWA）备份格式
    private struct BallastBackup: Codable {
        struct Profile: Codable { var name: String? }
        struct WeightItem: Codable { var d: String; var kg: Double }
        struct MeasItem: Codable {
            var d: String
            var chest: Double?; var waist: Double?; var arm: Double?
            var thigh: Double?; var shoulder: Double?; var neck: Double?
        }
        struct Workout: Codable {
            var date: String
            var day: String
            var exercises: [ExerciseItem]?
        }
        struct ExerciseItem: Codable {
            var id: String
            var sets: [SetItem]?
        }
        struct SetItem: Codable {
            var w: Double?
            var r: Int?
            var done: Bool?
        }
        var profile: Profile?
        var nextDay: String?
        var weight: [WeightItem]?
        var meas: [MeasItem]?
        var workouts: [Workout]?
    }

    /// 导出为 JSON 字符串（iOS 自身格式）
    func exportJSON() -> String {
        var checklist: [String: [Int]] = [:]
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("fit_checklist_") }
        for key in keys {
            let date = String(key.dropFirst("fit_checklist_".count))
            checklist[date] = checkedChecklistItems(on: date).sorted()
        }
        let pkg = BackupPackage(
            profileName: profileName,
            nextDayId: nextDayId,
            weights: weights,
            measurements: measurements,
            records: allRecords(),
            checklist: checklist
        )
        guard let data = try? JSONEncoder().encode(pkg) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 导入备份：先试 iOS 格式，再试 ballast.v1 格式
    @discardableResult
    func importJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }

        // 1) iOS 自身格式
        if let pkg = try? JSONDecoder().decode(BackupPackage.self, from: data) {
            profileName = pkg.profileName
            setNextDay(pkg.nextDayId)
            weights = pkg.weights
            measurements = pkg.measurements
            saveBodyData()
            for (date, _) in pkg.checklist {
                defaults.removeObject(forKey: "fit_checklist_\(date)")
            }
            for rec in pkg.records {
                if let d = try? JSONEncoder().encode([rec]) {
                    defaults.set(d, forKey: "fit_records_\(rec.date)")
                }
            }
            return true
        }

        // 2) ballast.v1（压舱石 PWA）格式
        guard let raw = try? JSONDecoder().decode(BallastBackup.self, from: data) else { return false }
        if let name = raw.profile?.name, !name.isEmpty { profileName = name }
        if let nd = raw.nextDay, TrainingData.days.contains(where: { $0.id == nd }) { setNextDay(nd) }
        weights = (raw.weight ?? []).map { WeightEntry(date: $0.d, kg: $0.kg) }
        measurements = (raw.meas ?? []).map { m in
            MeasurementEntry(date: m.d, chest: m.chest, waist: m.waist, arm: m.arm,
                             thigh: m.thigh, shoulder: m.shoulder, neck: m.neck)
        }
        saveBodyData()
        for w in raw.workouts ?? [] {
            var entries: [ExerciseLog] = []
            for e in w.exercises ?? [] {
                let iosId = TrainingData.ballastExerciseMap[e.id]
                    ?? (TrainingData.exerciseMap[e.id] != nil ? e.id : nil)
                guard let iosId else { continue }
                var sets: [SetLog] = []
                for s in e.sets ?? [] where s.done == true {
                    guard let reps = s.r, reps > 0 else { continue }
                    let wKg = s.w ?? 0
                    sets.append(SetLog(weightKg: wKg > 0 ? wKg : nil, reps: reps))
                }
                if !sets.isEmpty {
                    entries.append(ExerciseLog(exerciseId: iosId, sets: sets))
                }
            }
            guard !entries.isEmpty else { continue }
            let start = Self.noonTimestamp(of: w.date) ?? Date().timeIntervalSince1970
            let rec = DayRecord(date: w.date, dayId: w.day, startTime: start,
                                durationSeconds: 0, entries: entries)
            if let d = try? JSONEncoder().encode([rec]) {
                defaults.set(d, forKey: "fit_records_\(rec.date)")
            }
        }
        return true
    }

    /// 清空所有数据（含记录、体重、围度、设置）
    func clearAllData() {
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("fit") }
        for key in keys { defaults.removeObject(forKey: key) }
        abandonWorkout()
        profileName = "训练者"
        setNextDay("push")
        weights = []
        measurements = []
        darkMode = false
        restSeconds = 75
    }

    private static func noonTimestamp(of date: String) -> TimeInterval? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: date) else { return nil }
        return d.addingTimeInterval(12 * 3600).timeIntervalSince1970
    }

    private static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
