import IndoorCoachKit
import SwiftData
import SwiftUI

@main
struct IndoorCoachApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = AppEnvironment.makeContainerRecovering()
        self.container = container
        let model = AppEnvironment.makeModel(container: container)
        _model = State(initialValue: model)
        AppTips.configure()
        AppTips.setOnboardingComplete(!model.needsOnboarding)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .featureTourDebugCover()
                .onChange(of: model.needsOnboarding) { _, pending in AppTips.setOnboardingComplete(!pending) }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.syncStrava() } }
        }
    }
}
