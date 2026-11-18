import AppKit
import SwiftUI

/// Content of the menu-bar panel (journey steps 6 + 8).
struct MenuPanelView: View {
    @Bindable var controller: BridgeController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let status = controller.statusLine
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(status.text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: status.level == .warning ? "exclamationmark.triangle.fill" : status.level == .ok ? "checkmark.circle.fill" : "iphone")
                    .foregroundStyle(status.level == .warning ? Color.orange : status.level == .ok ? Color.green : Color.secondary)
            }
            if let error = controller.serverError {
                Text(error).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let latest = controller.latestRideText {
                Text("Letzte Fahrt: \(latest)").font(.callout).foregroundStyle(.secondary)
            }

            Divider()

            Button("Weiteres iPhone koppeln…") {
                openSetup()
                Task { await controller.startPairing() }
            }
            Button("Ordner ändern…") { controller.chooseFolder() }
            Button("Einrichtung öffnen") { openSetup() }

            Toggle("Beim Anmelden starten", isOn: Binding(get: { controller.launchAtLogin }, set: { controller.setLaunchAtLogin($0) }))
            if let error = controller.launchAtLoginError {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Kopplung zurücksetzen…") { controller.resetPairing() }
            Button("Beenden") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }

    private func openSetup() {
        openWindow(id: "setup")
        NSApp.activate()
    }
}
