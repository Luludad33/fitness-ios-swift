import SwiftUI

// MARK: - 记录 Tab

struct RecordsView: View {
    @EnvironmentObject var wm: WorkoutManager
    @State private var records: [DayRecord] = []

    /// 本周统计
    private var weekRecords: [DayRecord] {
        WorkoutManager.recentRecords(days: 7)
    }

    var body: some View {
        NavigationStack {
            List {
                // 本周统计卡
                Section {
                    HStack(spacing: 0) {
                        statItem("\(weekRecords.count)", label: "本周训练")
                        Divider().frame(height: 32).padding(.vertical, 8)
                        statItem("\(weekMinutes)", label: "总时长(分)")
                        Divider().frame(height: 32).padding(.vertical, 8)
                        statItem("\(weekRecords.reduce(0) { $0 + $1.totalSets })", label: "总组数")
                    }
                    .padding(.vertical, 6)
                }

                if records.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Text("🏋️")
                                .font(.system(size: 40))
                            Text("还没有训练记录")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("去「训练」页完成第一次训练吧")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                } else {
                    Section("最近 30 天") {
                        ForEach(records.sorted { $0.startTime > $1.startTime }) { record in
                            RecordRow(record: record)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("训练记录")
            .onAppear { refresh() }
            .onChange(of: wm.phase) { _, _ in refresh() }
        }
    }

    private var weekMinutes: Int {
        weekRecords.reduce(0) { $0 + $1.durationSeconds } / 60
    }

    private func refresh() {
        records = WorkoutManager.recentRecords(days: 30)
    }

    private func statItem(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecordRow: View {
    let record: DayRecord
    @State private var expanded = false

    private var dayEmoji: String {
        TrainingData.days.first { $0.id == record.dayId }?.emoji ?? "🏋️"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text(dayEmoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.dayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text(record.date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(record.durationSeconds / 60) 分钟")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.primary)
                        Text("\(record.totalSets) 组")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(record.entries, id: \.exerciseId) { entry in
                        let name = TrainingData.exerciseMap[entry.exerciseId]?.name ?? entry.exerciseId
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name)
                                .font(.caption.weight(.semibold))
                            ForEach(Array(entry.sets.enumerated()), id: \.offset) { i, set in
                                HStack(spacing: 6) {
                                    Text("第\(i + 1)组")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    if let w = set.weightKg {
                                        Text("\(formatWeight(w)) kg × \(set.reps) 次")
                                            .font(.caption.monospacedDigit())
                                    } else {
                                        Text("\(set.reps) 次")
                                            .font(.caption.monospacedDigit())
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
            }
        }
        .padding(.vertical, 2)
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(w))
            : String(format: "%.1f", w)
    }
}
