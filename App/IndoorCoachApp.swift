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
        #if os(iOS)
        RecordingLive.presenter = LiveActivityPresenter.make()
        // Reste eines Absturzes/Neustarts vom Sperrbildschirm räumen, aber nur ohne laufende Aufzeichnung.
        Task { @MainActor in
            guard !RecordingService.shared.isRunning else { return }
            await (RecordingLive.presenter as? RecordingLiveController)?.endOrphans()
        }
        #endif
        AppTips.configure()
        AppTips.setOnboardingComplete(!model.needsOnboarding)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .featureTourDebugCover()
                .onOpenURL { url in
                    // "Öffnen in IndoorCoach" / Teilen-Menü for .fit files (OAuth callbacks never arrive here).
                    if url.isFileURL, url.pathExtension.lowercased() == "fit" { model.importFITFiles([url]) }
                }
                .onChange(of: model.needsOnboarding) { _, pending in AppTips.setOnboardingComplete(!pending) }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.syncStrava() }
                Task { await model.syncFromBridge(announce: false) }   // no-op unless a Mac is paired; at most every 2 min
            }
        }
    }
}
