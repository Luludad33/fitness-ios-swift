import SwiftUI
import UniformTypeIdentifiers

// MARK: - 我的 Tab（昵称 / 设置 / 备份 / 关于）

struct ProfileView: View {
    @EnvironmentObject var wm: WorkoutManager
    @State private var showImporter = false
    @State private var showClearConfirm = false
    @State private var showImportResult = false
    @State private var importMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Text("🏋️")
                            .font(.title2)
                        TextField("昵称", text: $wm.profileName)
                            .font(.subheadline.weight(.medium))
                    }
                } header: {
                    Text("个人")
                }

                Section("设置") {
                    Toggle("深色模式", isOn: $wm.darkMode)
                        .tint(.blue)
                    Picker("下一个训练日", selection: nextDayBinding) {
                        ForEach(TrainingData.days) { day in
                            Text("\(day.emoji) \(day.name)").tag(day.id)
                        }
                    }
                }

                Section("数据") {
                    ShareLink(item: exportURL) {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入备份", systemImage: "square.and.arrow.down")
                    }
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("清空所有数据", systemImage: "trash")
                    }
                }

                Section("关于") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("健身训练手册 FitCoach")
                            .font(.subheadline.weight(.semibold))
                        Text("内容来自《健身动作图解与训练手册 V2.0》：三分化训练（推/拉/腿）、12 个力量动作、10 个拉伸动作。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("所有数据仅保存在本机。备份格式兼容「压舱石 BALLAST」（ballast.v1）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("我的")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .confirmationDialog("清空所有数据？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { wm.clearAllData() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("体重、围度、训练记录、设置将全部删除，且不可恢复。建议先导出备份。")
            }
            .alert("导入结果", isPresented: $showImportResult) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importMessage)
            }
        }
    }

    private var nextDayBinding: Binding<String> {
        Binding(
            get: { wm.nextDayId },
            set: { wm.setNextDay($0) }
        )
    }

    /// 导出文件：写入临时目录后由 ShareLink 分享
    private var exportURL: URL {
        let json = wm.exportJSON()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitCoach备份_\(DataView.todayString()).json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            importMessage = wm.importJSON(text) ? "导入成功 ✅" : "文件格式不正确 ❌"
        } else {
            importMessage = "读取文件失败 ❌"
        }
        showImportResult = true
    }
}