import SwiftUI

@main
struct FitCoachApp: App {
    @StateObject private var workoutManager = WorkoutManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
                .onChange(of: scenePhase) { _, newPhase in
                    workoutManager.handleScenePhaseChange(to: newPhase)
                }
        }
    }
}
