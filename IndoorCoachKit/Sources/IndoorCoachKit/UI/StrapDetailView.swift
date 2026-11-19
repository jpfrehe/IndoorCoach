import SwiftUI

/// Sections for a connected strap: live pulse, capabilities, battery, multi-connection test, forget.
struct StrapDetailView: View {
    let session: StrapSession
    @State private var multiStep = 0
    @State private var multiResult: Bool?
    @State private var confirmForget = false

    var body: some View {
        Section("Live") {
            LabeledContent("Puls") {
                Text(session.liveHeartRate.map { "\($0) bpm" } ?? "–")
                    .font(.title2.monospacedDigit().bold())
                    .accessibilityIdentifier("strap.livePulse")
            }
            if session.contact == .notDetected {
                Text("Kein Hautkontakt. Gurt anfeuchten und enger anlegen.").font(.footnote).foregroundStyle(.orange)
            }
        }
        Section("Gurt") {
            LabeledContent("Name", value: session.deviceName ?? "–")
            if let manufacturer = session.manufacturer { LabeledContent("Hersteller", value: manufacturer) }
            LabeledContent("RR-Intervalle (HRV)") {
                Text(session.rrSeen ? "✓ empfangen" : "–")
            }
            LabeledContent("Akku") { Text(session.batteryLevel.map { "\($0) %" } ?? "–") }
            if session.batteryLow {
                Text("Akku unter 20 %. Wechsle bald die Batterie, sonst bricht die Verbindung ab.").font(.footnote).foregroundStyle(.orange)
            }
        }
        multiConnectionSection
        Section {
            Button("Trennen") { session.disconnect() }
            Button("Vergessen", role: .destructive) { confirmForget = true }
                .accessibilityIdentifier("strap.forget")
                .confirmationDialog("Gurt vergessen?", isPresented: $confirmForget, titleVisibility: .visible) {
                    Button("Vergessen", role: .destructive) { session.forget() }
                } message: { Text("Die gespeicherte Kopplung wird gelöscht. Du kannst den Gurt jederzeit neu suchen.") }
        }
    }

    private var multiConnectionSection: some View {
        let hint = StrapModelHints.hint(forName: session.deviceName)
        return Section {
            Text(hint.note).font(.footnote).foregroundStyle(.secondary)
            switch multiStep {
            case 0:
                Button("Test starten") { multiStep = 1; multiResult = nil }
            case 1:
                Text("1. Öffne MyWhoosh auf dem Mac und verbinde dort denselben Gurt als Pulsquelle.")
                Button("MyWhoosh ist verbunden") { multiStep = 2 }
            default:
                Text("2. Siehst du hier weiter Puls?")
                LabeledContent("Aktuell") { Text(session.liveHeartRate.map { "\($0) bpm" } ?? "kein Puls") }
                HStack {
                    Button("Ja, Puls läuft weiter") { multiResult = true; multiStep = 0 }
                    Button("Nein, Puls weg") { multiResult = false; multiStep = 0 }
                }
                .buttonStyle(.bordered)
            }
            if let multiResult {
                Text(multiResult
                     ? "Mehrfachverbindung funktioniert. Prüfe zusätzlich, ob RR-Intervalle (✓ oben) weiter ankommen."
                     : "Dein Gurt gibt nur eine Verbindung her oder ist nicht für mehrere freigeschaltet (Polar H10: Mehrfachverbindung in Polar Beat aktivieren). Nutze für MyWhoosh dann eine andere Pulsquelle oder trenne den Gurt hier während der Fahrt.")
                    .font(.footnote)
            }
        } header: { Text("Mehrfachverbindungs-Test") }
    }
}
