import SwiftUI
import Charts

// MARK: - 数据 Tab（体重趋势 / 身体围度 / PR 个人纪录）

struct DataView: View {
    @EnvironmentObject var wm: WorkoutManager
    @State private var weightText = ""
    @State private var weightDate = Date()
    @State private var measTexts: [String: String] = [:]

    /// 最近 30 条体重记录（weights 已按日期升序）
    private var lastWeights: [WeightEntry] {
        Array(wm.weights.suffix(30))
    }

    var body: some View {
        NavigationStack {
            List {
                weightSection
                measurementSection
                prSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("数据")
        }
    }

    // MARK: - 体重趋势

    private var weightSection: some View {
        Section {
            if wm.weights.isEmpty {
                Text("还没有体重数据，记下第一笔吧")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Chart(lastWeights) { w in
                    AreaMark(x: .value("日期", Self.date(from: w.date)), y: .value("体重", w.kg))
                        .foregroundStyle(.green.opacity(0.12))
                    LineMark(x: .value("日期", Self.date(from: w.date)), y: .value("体重", w.kg))
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)
                }
                .chartYAxisLabel("kg", position: .trailing)
                .frame(height: 170)

                HStack {
                    Text("最新 \(Self.fmt(latestKg)) kg")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(trendText)
                        .font(.caption)
                        .foregroundColor(trendColor)
                }
            }

            HStack(spacing: 10) {
                TextField("体重 kg", text: $weightText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                DatePicker("", selection: $weightDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                Button("记录") { addWeight() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(weightValue <= 0)
            }
            .padding(.top, 4)
        } header: {
            Label("体重趋势", systemImage: "scalemass")
        }
    }

    private var latestKg: Double { wm.weights.last?.kg ?? 0 }

    private var trendText: String {
        guard wm.weights.count >= 2 else { return "记录第一笔" }
        let d = wm.weights[wm.weights.count - 1].kg - wm.weights[wm.weights.count - 2].kg
        if d == 0 { return "持平" }
        return String(format: "%@ %.1f kg", d > 0 ? "▲" : "▼", abs(d))
    }

    private var trendColor: Color {
        guard wm.weights.count >= 2 else { return .secondary }
        let d = wm.weights[wm.weights.count - 1].kg - wm.weights[wm.weights.count - 2].kg
        return d > 0 ? .orange : .green
    }

    private var weightValue: Double {
        Double(weightText.replacingOccurrences(of: "，", with: ".")) ?? 0
    }

    private func addWeight() {
        let v = weightValue
        guard v > 0 else { return }
        wm.addWeight(kg: v, date: Self.dayString(from: weightDate))
        weightText = ""
    }

    // MARK: - 身体围度

    private var latestMeasurement: MeasurementEntry? { wm.measurements.last }
    private var previousMeasurement: MeasurementEntry? {
        wm.measurements.count > 1 ? wm.measurements[wm.measurements.count - 2] : nil
    }

    private var measurementSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(TrainingData.measParts, id: \.key) { part in
                    VStack(spacing: 2) {
                        Text(measurementValueText(for: part.key))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        Text("\(part.name) cm")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(diffText(for: part.key))
                            .font(.caption2)
                            .foregroundColor(diffColor(for: part.key))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
                }
            }

            ForEach(TrainingData.measParts, id: \.key) { part in
                TextField("\(part.name) cm（可只填部分）", text: binding(for: part.key))
                    .keyboardType(.decimalPad)
            }

            Button("保存今日围度") { saveMeasurement() }
                .frame(maxWidth: .infinity)
        } header: {
            Label("身体围度", systemImage: "ruler")
        }
    }

    private func measurementValueText(for key: String) -> String {
        guard let latest = latestMeasurement, let v = latest.value(for: key) else { return "--" }
        return Self.fmt(v)
    }

    private func diffText(for key: String) -> String {
        guard let latest = latestMeasurement, let v = latest.value(for: key),
              let prev = previousMeasurement, let pv = prev.value(for: key) else { return "" }
        let d = v - pv
        if d == 0 { return "±0" }
        return String(format: "%@%.1f", d > 0 ? "+" : "", d)
    }

    private func diffColor(for key: String) -> Color {
        guard let latest = latestMeasurement, let v = latest.value(for: key),
              let prev = previousMeasurement, let pv = prev.value(for: key) else { return .secondary }
        let d = v - pv
        return d > 0 ? .green : .blue
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { measTexts[key] ?? "" },
            set: { measTexts[key] = $0 }
        )
    }

    private func saveMeasurement() {
        var m = MeasurementEntry(date: Self.todayString())
        var any = false
        for part in TrainingData.measParts {
            guard let text = measTexts[part.key], let v = Double(text.replacingOccurrences(of: "，", with: ".")), v > 0 else { continue }
            m.setValue(v, for: part.key)
            any = true
        }
        guard any else { return }
        wm.addMeasurement(m)
        measTexts = [:]
    }

    // MARK: - PR 个人纪录

    private var prSection: some View {
        Section {
            if wm.prs.isEmpty {
                Text("完成训练并记录重量后，个人纪录会自动出现")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(wm.prs.enumerated()), id: \.element.id) { i, pr in
                    HStack(spacing: 10) {
                        Text("\(i + 1)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.exercise.name)
                                .font(.subheadline.weight(.medium))
                            Text("\(pr.date) · 估算 1RM \(pr.oneRM) kg")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Self.fmt(pr.weightKg)) kg × \(pr.reps)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        } header: {
            Label("个人纪录（按估算 1RM 排序）", systemImage: "trophy.fill")
        }
    }

    // MARK: - 工具

    static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }

    static func date(from s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s) ?? Date()
    }

    static func dayString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func todayString() -> String { dayString(from: Date()) }
}

// MARK: - MeasurementEntry 按键取值 / 赋值

extension MeasurementEntry {
    func value(for key: String) -> Double? {
        switch key {
        case "chest": return chest
        case "waist": return waist
        case "arm": return arm
        case "thigh": return thigh
        case "shoulder": return shoulder
        case "neck": return neck
        default: return nil
        }
    }

    mutating func setValue(_ v: Double, for key: String) {
        switch key {
        case "chest": chest = v
        case "waist": waist = v
        case "arm": arm = v
        case "thigh": thigh = v
        case "shoulder": shoulder = v
        case "neck": neck = v
        default: break
        }
    }
}