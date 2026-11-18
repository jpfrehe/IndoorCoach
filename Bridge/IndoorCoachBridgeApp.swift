import SwiftUI

@main
struct IndoorCoachBridgeApp: App {
    @State private var controller: BridgeController

    init() {
        let controller = BridgeController()
        _controller = State(initialValue: controller)
        controller.start()
    }

    var body: some Scene {
        MenuBarExtra("IndoorCoach Brücke", systemImage: controller.menuSymbol) {
            MenuPanelView(controller: controller)
        }
        .menuBarExtraStyle(.window)

        // Opens by itself on the first launch (no folder chosen yet) and from the menu.
        Window("Einrichtung", id: "setup") {
            SetupView(controller: controller)
                .onAppear { NSApp.activate() }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(controller.needsSetupOnLaunch ? .presented : .suppressed)
    }
}
