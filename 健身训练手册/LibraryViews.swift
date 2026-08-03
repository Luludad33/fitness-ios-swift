import SwiftUI

// MARK: - 图鉴 Tab

struct LibraryView: View {
    @State private var category = 0   // 0 力量 / 1 拉伸 / 2 原则

    var body: some View {
        NavigationStack {
            List {
                if category == 0 {
                    strengthSections
                } else if category == 1 {
                    stretchSections
                } else {
                    principlesSections
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("动作图鉴")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $category) {
                        Text("力量 12").tag(0)
                        Text("拉伸 10").tag(1)
                        Text("原则 4").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
            }
        }
    }

    private var strengthSections: some View {
        ForEach(TrainingData.days) { day in
            Section("\(day.emoji) \(day.name)（\(day.subtitle)）") {
                ForEach(day.exercises) { ex in
                    NavigationLink {
                        ExerciseDetailView(exercise: ex)
                    } label: {
                        ExerciseRow(exercise: ex)
                    }
                }
            }
        }
    }

    private var stretchSections: some View {
        Group {
            ForEach(["下肢", "上肢与躯干"], id: \.self) { group in
                Section(group) {
                    ForEach(TrainingData.stretches.filter { $0.group == group }) { s in
                        NavigationLink {
                            StretchDetailView(stretch: s)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.name)
                                    .font(.subheadline.weight(.medium))
                                Text(s.target)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            Section("练后拉伸速查") {
                ForEach(TrainingData.stretchTable, id: \.day) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.day)
                            .font(.subheadline.weight(.semibold))
                        Text(row.part)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(row.move)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var principlesSections: some View {
        Section("通用训练原则") {
            ForEach(TrainingData.principles, id: \.title) { p in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(p.emoji) \(p.title)")
                        .font(.subheadline.weight(.semibold))
                    Text(p.text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumb(exercise: exercise, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.subheadline.weight(.medium))
                Text(exercise.muscles)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(exercise.sets)×\(exercise.repRange)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 力量动作详情

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 头图
                Group {
                    if let imageName = exercise.imageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ZStack {
                            Color.blue.opacity(0.1)
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 64))
                                .foregroundColor(.blue)
                        }
                        .frame(height: 180)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 16))

                // 基本信息
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("🇬🇧 英文名", exercise.en)
                    infoRow("🎯 目标肌群", exercise.muscles)
                    infoRow("🏋️ 器械", exercise.equipment)
                    infoRow("📊 建议", "\(exercise.sets) 组 × \(exercise.repRange) 次")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: .rect(cornerRadius: 14))

                blockView("动作步骤", icon: "list.number") {
                    ForEach(Array(exercise.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.blue, in: .circle)
                            Text(step)
                                .font(.subheadline)
                        }
                    }
                }

                blockView("动作要领", icon: "checkmark.seal") {
                    ForEach(exercise.cues, id: \.self) { cue in
                        HStack(alignment: .top, spacing: 8) {
                            Text("✅").font(.caption)
                            Text(cue).font(.subheadline)
                        }
                    }
                }

                blockView("常见错误", icon: "exclamationmark.triangle") {
                    ForEach(exercise.mistakes, id: \.self) { m in
                        HStack(alignment: .top, spacing: 8) {
                            Text("❌").font(.caption)
                            Text(m).font(.subheadline)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("呼吸方法", systemImage: "wind")
                        .font(.headline)
                    Text(exercise.breathing)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cyan.opacity(0.1), in: .rect(cornerRadius: 14))
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.subheadline)
        }
    }

    private func blockView(_ title: String, icon: String,
                           @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }
}

// MARK: - 拉伸动作详情

struct StretchDetailView: View {
    let stretch: StretchMove

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("🧘 拉伸部位")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(stretch.target)
                        .font(.title3.weight(.medium))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1), in: .rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 10) {
                    Text("做法")
                        .font(.headline)
                    ForEach(stretch.how, id: \.self) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.green)
                                .padding(.top, 6)
                            Text(step)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: .rect(cornerRadius: 14))

                Text("拉伸原则：每个动作保持 20–30 秒，不要弹震，拉到有牵拉感但不疼的程度。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(stretch.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
