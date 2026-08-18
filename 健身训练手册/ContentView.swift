import SwiftUI

/// 根视图：五个 Tab（训练 / 图鉴 / 数据 / 记录 / 我的）+ 训练进行时全屏覆盖层（同护眼项目 ZStack 叠层思路）
struct ContentView: View {
    @EnvironmentObject var wm: WorkoutManager
    @State private var tab = 0

    private var sessionActive: Bool {
        wm.phase == .exercising || wm.phase == .resting
    }

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                DaySelectionView()
                    .tabItem { Label("训练", systemImage: "figure.strengthtraining.traditional") }
                    .tag(0)
                LibraryView()
                    .tabItem { Label("图鉴", systemImage: "book.fill") }
                    .tag(1)
                DataView()
                    .tabItem { Label("数据", systemImage: "chart.xyaxis.line") }
                    .tag(2)
                RecordsView()
                    .tabItem { Label("记录", systemImage: "chart.bar.fill") }
                    .tag(3)
                ProfileView()
                    .tabItem { Label("我的", systemImage: "person.fill") }
                    .tag(4)
            }

            // 训练流程全屏页（含 finished 庆祝页）
            if sessionActive || wm.phase == .finished {
                WorkoutFlowView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // 组间休息遮罩（最上层）
            if wm.phase == .resting {
                RestOverlayView()
            }

            // 训练暂停悬浮条：可回 Tab 浏览其他内容，随时点「继续训练」回来
            if wm.phase == .paused {
                HStack(spacing: 12) {
                    Text("训练已暂停")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("继续训练") { wm.resumeWorkout() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("保存并结束") { wm.saveAndFinishEarly() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
                .padding(.horizontal)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: wm.phase)
        .preferredColorScheme(wm.darkMode ? .dark : .light)
    }
}

// MARK: - 通用小组件

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

/// 动作缩略图：有图用图，没图用 SF Symbol（腿举机）
struct ExerciseThumb: View {
    let exercise: Exercise
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let imageName = exercise.imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.blue.opacity(0.12)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: size * 0.45))
                        .foregroundColor(.blue)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 12))
    }
}
