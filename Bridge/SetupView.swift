import SwiftUI

/// "Einrichtung" window (journey steps 3 + 4).
struct SetupView: View {
    @Bindable var controller: BridgeController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hallo! Ich bringe deine MyWhoosh-Fahrten aufs iPhone.")
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            folderStep
            pairingStep
            loginStep
        }
        .padding(24)
        .frame(width: 480)
    }

    // MARK: Step 1

    private var folderStep: some View {
        StepCard(number: 1, title: "MyWhoosh-Ordner freigeben", done: controller.folderState == .ready) {
            Text("Damit ich die Fahrten lesen kann, musst du mir den Ordner einmal freigeben.")
                .foregroundStyle(.secondary)
            if controller.myWhooshMissing {
                Text("MyWhoosh scheint auf diesem Mac nicht installiert zu sein. Du kannst trotzdem einen anderen Ordner mit FIT-Dateien wählen, zum Beispiel von Zwift.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("MyWhoosh-Ordner freigeben") { controller.chooseFolder() }
            switch controller.folderCheck {
            case let .found(count):
                Label(BridgeFormat.foundRidesText(count).replacingOccurrences(of: "✓ ", with: ""), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .empty:
                VStack(alignment: .leading, spacing: 4) {
                    Label("In diesem Ordner liegen keine MyWhoosh-Fahrten", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Wähle bitte den Ordner „Data“ in MyWhooshs Programmdaten (…/Epic/MyWhoosh/Content/Data). Der Dialog öffnet sich dort, falls er existiert.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case nil:
                if controller.folderState == .needsReshare {
                    Label("Ordner neu freigeben", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: Step 2

    private var pairingStep: some View {
        StepCard(number: 2, title: "iPhone koppeln", done: pairedDone) {
            switch controller.pairing {
            case let .active(code, until):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Öffne IndoorCoach auf dem iPhone und gib diesen Code ein:")
                        .foregroundStyle(.secondary)
                    Text(BridgeFormat.groupedCode(code))
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .textSelection(.enabled)
                        .accessibilityLabel("Kopplungscode \(code.map(String.init).joined(separator: " "))")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Noch \(BridgeFormat.countdown(until.timeIntervalSince(context.date))) gültig")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    Button("Abbrechen") { controller.cancelPairing() }
                }
            case let .paired(device):
                Label("Gekoppelt mit \(device)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Weiteres iPhone koppeln") { Task { await controller.startPairing() } }
            case .expired:
                Text("Der Code ist abgelaufen.").foregroundStyle(.secondary)
                Button("Neuen Code anzeigen") { Task { await controller.startPairing() } }
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Button("Noch einmal versuchen") { Task { await controller.startPairing() } }
            case .idle:
                if let device = controller.pairedDeviceName {
                    Label("Gekoppelt mit \(device)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Weiteres iPhone koppeln") { Task { await controller.startPairing() } }
                } else {
                    Text("Du bekommst einen 6-stelligen Code, den du am iPhone eingibst. Fragt macOS, ob die Brücke Geräte im lokalen Netzwerk finden darf, klicke auf „Erlauben“ – sonst findet dein iPhone sie nicht.")
                        .foregroundStyle(.secondary)
                    Button("iPhone koppeln") { Task { await controller.startPairing() } }
                }
            }
        }
    }

    private var pairedDone: Bool {
        if case .paired = controller.pairing { return true }
        return controller.pairedDeviceName != nil
    }

    // MARK: Step 3

    private var loginStep: some View {
        StepCard(number: 3, title: "Automatisch starten", done: controller.launchAtLogin) {
            Toggle("Beim Anmelden starten", isOn: Binding(get: { controller.launchAtLogin }, set: { controller.setLaunchAtLogin($0) }))
            if let error = controller.launchAtLoginError {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
            Text("Danach lebt die Brücke nur als Symbol in der Menüleiste.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
