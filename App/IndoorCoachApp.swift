import IndoorCoachKit
import SwiftData
import SwiftUI

@main
struct IndoorCoachApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let container = try AppEnvironment.makeContainer()
            self.container = container
            _model = State(initialValue: AppEnvironment.makeModel(container: container))
        } catch {
            fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.syncStrava() } }
        }
    }
}
