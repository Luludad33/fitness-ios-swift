import SwiftUI

// MARK: - 训练 Tab：训练日选择

struct DaySelectionView: View {
    @EnvironmentObject var wm: WorkoutManager
    @State private var showChecklistFor: WorkoutDay?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(TrainingData.days) { day in
                        DayCard(day: day) {
                            showChecklistFor = day
                        }
                    }

                    SectionCard(title: "通用训练原则", icon: "lightbulb.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(TrainingData.principles, id: \.title) { p in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(p.emoji) \(p.title)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(p.text)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("健身训练手册")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        wm.darkMode.toggle()
                    } label: {
                        Image(systemName: wm.darkMode ? "sun.max.fill" : "moon.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(item: $showChecklistFor) { day in
                ChecklistSheet(day: day)
            }
        }
    }
}

struct DayCard: View {
    let day: WorkoutDay
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.name)
                        .font(.title3.weight(.bold))
                    Text(day.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(day.durationText)
                        .font(.caption.weight(.medium))
                    Text("休息 \(day.restRangeText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            ForEach(Array(day.exercises.enumerated()), id: \.element.id) { i, ex in
                HStack(spacing: 8) {
                    Text(["①", "②", "③", "④"][i])
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(ex.name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(ex.sets)×\(ex.repRange)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("热身 \(day.warmupText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onStart) {
                    Text("开始训练")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .clipShape(.capsule)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

/// 训练前 Checklist（文档原文 8 项）
struct ChecklistSheet: View {
    let day: WorkoutDay
    @EnvironmentObject var wm: WorkoutManager
    @Environment(\.dismiss) private var dismiss
    @State private var checked: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(TrainingData.preWorkoutChecklist.enumerated()), id: \.offset) { i, item in
                        Button {
                            if checked.contains(i) { checked.remove(i) } else { checked.insert(i) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: checked.contains(i) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(checked.contains(i) ? .green : .secondary)
                                Text(item)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .strikethrough(checked.contains(i), color: .secondary)
                            }
                        }
                    }
                } footer: {
                    Text("全部勾选不是硬性要求，心里有数就行 💪")
                }
            }
            .navigationTitle("\(day.emoji) \(day.name) · 练前检查")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始！") {
                        dismiss()
                        wm.startWorkout(day: day)
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 训练流程页（全屏）

struct WorkoutFlowView: View {
    @EnvironmentObject var wm: WorkoutManager
    @State private var repsText = ""
    @State private var weightText = ""
    @State private var showAbandonConfirm = false
    @State private var showDetails = false

    var body: some View {
        Group {
            if wm.phase == .finished {
                WorkoutFinishedView()
            } else if let exercise = wm.currentExercise, let day = wm.currentDay {
                exerciseScreen(exercise: exercise, day: day)
            } else {
                Color(.systemBackground).ignoresSafeArea()
            }
        }
    }

    private func exerciseScreen(exercise: Exercise, day: WorkoutDay) -> some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 顶部信息条
                    HStack {
                        Button {
                            showAbandonConfirm = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(day.emoji) \(day.name)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Menu {
                            Picker("组间休息", selection: Binding(
                                get: { wm.restSeconds },
                                set: { wm.updateRestSeconds($0) }
                            )) {
                                ForEach([30, 45, 60, 75, 90, 105, 120, 150, 180], id: \.self) { s in
                                    Text("\(s) 秒").tag(s)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                Text("休息 \(wm.restSeconds)s")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }

                    // 总进度
                    VStack(spacing: 6) {
                        HStack {
                            Text("第 \(wm.exerciseIndex + 1)/\(day.exerciseIds.count) 个动作 · 第 \(wm.setNumber)/\(exercise.sets) 组")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(wm.completedSets)/\(wm.totalSets) 组")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: Double(wm.completedSets), total: Double(max(1, wm.totalSets)))
                            .tint(.blue)
                    }

                    // 动作卡片
                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            ExerciseThumb(exercise: exercise, size: 88)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(.title2.weight(.bold))
                                Text(exercise.muscles)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("目标：\(exercise.sets) 组 × \(exercise.repRange) 次")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                        }

                        DisclosureGroup(isExpanded: $showDetails) {
                            VStack(alignment: .leading, spacing: 12) {
                                detailBlock("动作要领", items: exercise.cues, bullet: "✅")
                                detailBlock("常见错误", items: exercise.mistakes, bullet: "❌")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("💨 呼吸").font(.subheadline.weight(.semibold))
                                    Text(exercise.breathing)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("动作要领与常见错误")
                                .font(.subheadline)
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))

                    // 本组录入
                    VStack(spacing: 14) {
                        HStack {
                            Text("做了多少次？")
                                .font(.subheadline)
                            Spacer()
                            Stepper(value: repsBinding, in: 0...60) {
                                Text("\(repsValue) 次")
                                    .font(.subheadline.monospacedDigit())
                                    .frame(minWidth: 44, alignment: .trailing)
                            }
                            .fixedSize()
                        }

                        HStack {
                            Text("重量（kg，可不填）")
                                .font(.subheadline)
                            Spacer()
                            TextField("选填", text: $weightText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
                        }

                        Button {
                            completeCurrentSet()
                        } label: {
                            Text(completeLabel)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue)
                                .clipShape(.capsule)
                                .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                        }
                        .disabled(repsValue <= 0)
                        .opacity(repsValue <= 0 ? 0.5 : 1)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))

                    // 下一动作预告
                    if let next = wm.nextExercise, wm.setNumber >= exercise.sets {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.orange)
                            Text("下一个动作：\(next.name)（\(next.sets) 组 × \(next.repRange)）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .onAppear { resetInputs(for: exercise) }
        .onChange(of: wm.exerciseIndex) { _, _ in
            if let ex = wm.currentExercise { resetInputs(for: ex) }
        }
        .onChange(of: wm.setNumber) { _, _ in
            if let ex = wm.currentExercise { resetInputs(for: ex) }
        }
        .confirmationDialog("放弃本次训练？", isPresented: $showAbandonConfirm, titleVisibility: .visible) {
            Button("放弃训练", role: .destructive) { wm.abandonWorkout() }
            Button("继续练", role: .cancel) {}
        }
    }

    private var repsValue: Int {
        Int(repsText) ?? defaultReps
    }

    private var repsBinding: Binding<Int> {
        Binding(
            get: { Int(repsText) ?? defaultReps },
            set: { repsText = String($0) }
        )
    }

    /// 当前动作的默认次数（repRange 中值）
    private var defaultReps: Int {
        guard let ex = wm.currentExercise else { return 10 }
        let nums = Self.numbers(in: ex.repRange)
        guard !nums.isEmpty else { return 10 }
        return nums.reduce(0, +) / nums.count
    }

    /// 从 "8–12" / "每腿 8–10" 这类文本里提取连续数字
    static func numbers(in s: String) -> [Int] {
        var nums: [Int] = []
        var current = ""
        for ch in s {
            if let d = ch.wholeNumberValue {
                current += String(d)
            } else {
                if let n = Int(current) { nums.append(n) }
                current = ""
            }
        }
        if let n = Int(current) { nums.append(n) }
        return nums
    }

    private var completeLabel: String {
        if let ex = wm.currentExercise, let day = wm.currentDay,
           wm.setNumber >= ex.sets, wm.exerciseIndex >= day.exerciseIds.count - 1 {
            return "完成最后一个动作 🎉"
        }
        return "本组完成 → 休息 \(wm.restSeconds) 秒"
    }

    private func resetInputs(for exercise: Exercise) {
        let nums = Self.numbers(in: exercise.repRange)
        let def = nums.isEmpty ? 10 : nums.reduce(0, +) / nums.count
        repsText = String(def)
        weightText = ""
        showDetails = false
    }

    private func completeCurrentSet() {
        let weight = Double(weightText.replacingOccurrences(of: "，", with: ".")) ?? 0
        wm.completeSet(reps: repsValue, weightKg: weight > 0 ? weight : nil)
    }

    private func detailBlock(_ title: String, items: [String], bullet: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text(bullet).font(.caption)
                    Text(item)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - 组间休息遮罩（同护眼 RestOverlayView 结构）

struct RestOverlayView: View {
    @EnvironmentObject var wm: WorkoutManager
    @State private var appear = false
    @State private var tipIndex = 0

    var body: some View {
        Color.black.opacity(0.35)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 14) {
                    Text("😮‍💨")
                        .font(.system(size: 44))

                    Text("组间休息")
                        .font(.title3.weight(.bold))

                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 8)
                            .frame(width: 170, height: 170)
                        Circle()
                            .trim(from: 0, to: wm.restProgress)
                            .stroke(Color.orange, style: .init(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 170, height: 170)
                            .animation(.linear(duration: 0.2), value: wm.restProgress)
                        Text("\(Int(ceil(wm.timeRemaining)))")
                            .font(.system(size: 52, weight: .heavy, design: .monospaced))
                            .foregroundColor(.orange)
                            .contentTransition(.numericText(countsDown: true))
                    }

                    if let next = nextUpText {
                        Text(next)
                            .font(.subheadline.weight(.medium))
                    }

                    Text(TrainingData.restTips[tipIndex % TrainingData.restTips.count])
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 32)

                    Button("跳过休息") {
                        withAnimation(.easeOut(duration: 0.2)) { wm.skipRest() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                .padding(28)
                .frame(maxWidth: 310)
                .background(.regularMaterial, in: .rect(cornerRadius: 24))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
                .scaleEffect(appear ? 1 : 0.85)
                .opacity(appear ? 1 : 0)
            )
            .onAppear {
                tipIndex = Int.random(in: 0..<TrainingData.restTips.count)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    appear = true
                }
            }
    }

    private var nextUpText: String? {
        guard let ex = wm.currentExercise else { return nil }
        if wm.setNumber < ex.sets {
            return "下一组：\(ex.name) 第 \(wm.setNumber + 1)/\(ex.sets) 组"
        } else if let next = wm.nextExercise {
            return "下一个动作：\(next.name)（\(next.sets) 组 × \(next.repRange)）"
        }
        return nil
    }
}

// MARK: - 训练完成庆祝（同护眼 SessionCompletedView 结构）

struct WorkoutFinishedView: View {
    @EnvironmentObject var wm: WorkoutManager
    @State private var appear = false

    var body: some View {
        Color.black.opacity(0.35)
            .ignoresSafeArea()
            .overlay(
                ScrollView {
                    VStack(spacing: 16) {
                        Text("🎉")
                            .font(.system(size: 64))

                        Text("训练完成！")
                            .font(.title.weight(.bold))

                        if let record = wm.lastRecord {
                            HStack(spacing: 20) {
                                statItem("\(record.dayName)", label: "训练日")
                                statItem("\(record.durationSeconds / 60) 分钟", label: "总时长")
                                statItem("\(record.totalSets) 组", label: "完成组数")
                            }
                        }

                        if let dayId = wm.lastRecord?.dayId,
                           let stretchIds = TrainingData.postWorkoutStretch[dayId] {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("🧘 练后拉伸 5-10 分钟（每个 30 秒）")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(stretchIds, id: \.self) { sid in
                                    if let s = TrainingData.stretches.first(where: { $0.id == sid }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.circle")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                            Text("\(s.name) — \(s.target)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.green.opacity(0.08), in: .rect(cornerRadius: 14))
                        }

                        Text("练后 1-2 小时内补充蛋白质+碳水 🥗")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("完成") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                wm.dismissFinished()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(28)
                    .frame(maxWidth: 320)
                    .background(.regularMaterial, in: .rect(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
                    .scaleEffect(appear ? 1 : 0.85)
                    .opacity(appear ? 1 : 0)
                }
            )
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    appear = true
                }
            }
    }

    private func statItem(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
