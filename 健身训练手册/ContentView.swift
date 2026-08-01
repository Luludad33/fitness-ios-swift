import SwiftUI

/// 根视图：三个 Tab（训练 / 图鉴 / 记录）+ 训练进行时全屏覆盖层（同护眼项目 ZStack 叠层思路）
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
                RecordsView()
                    .tabItem { Label("记录", systemImage: "chart.bar.fill") }
                    .tag(2)
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
        }
        .animation(.easeOut(duration: 0.25), value: wm.phase)
        .preferredColorScheme(wm.darkMode ? .dark : .light)
    }
}

// MARK: - 通用小组件

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

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
