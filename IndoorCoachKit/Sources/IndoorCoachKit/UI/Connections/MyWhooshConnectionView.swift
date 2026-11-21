import SwiftUI

/// Profil → Dienste & Geräte → MyWhoosh: Anmeldung, Pläne senden, Fahrten laden, Abmelden.
struct MyWhooshConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false

    var body: some View {
        @Bindable var model = model
        let descriptor = model.connection(.myWhoosh)
        let signedIn = model.myWhooshUser != nil
        ConnectionDetailScaffold(
            title: "MyWhoosh",
            footer: "Einheiten landen direkt in MyWhoosh unter „Custom Workouts“ und im MyWhoosh-Kalender, deine gefahrenen Einheiten lädt die App von dort zurück – ganz ohne Strava. Nutzt die inoffizielle MyWhoosh-Schnittstelle; sie kann sich jederzeit ändern. Dann bleiben die .zwo-Datei und der FIT-Import (Dateien-App, auch von Zwift oder Wahoo) als Weg. Dein Passwort wird nur zur Anmeldung gesendet und nicht gespeichert.",
            help: ConnectionHelpLink(title: "MyWhoosh Workout Builder", systemImage: "figure.indoor.cycle",
                                     url: URL(string: "https://workout.mywhoosh.com")!),
            disconnect: signedIn
                ? ConnectionDisconnect(buttonTitle: "Bei MyWhoosh abmelden", dialogTitle: "Bei MyWhoosh abmelden?", confirmTitle: "Abmelden",
                                       message: "Pläne werden nicht mehr automatisch gesendet. Bereits geladene Fahrten bleiben in der App.",
                                       identifier: "mywhoosh.disconnect") {
                    Task { await model.disconnectMyWhoosh() }
                } : nil,
            showsOptions: signedIn
        ) {
            ConnectionStatusHeader(status: descriptor.status, syncTitle: "Letzter Import",
                                   account: model.myWhooshUser, lastSync: model.lastMyWhooshImport)
        } main: {
            if signedIn {
                Button {
                    Task { await model.importMyWhooshRides(full: true) }   // known rides are skipped, so the full window is cheap
                } label: {
                    HStack {
                        Label("Fahrten aus MyWhoosh laden", systemImage: "arrow.down.circle")
                        if model.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.isSyncing)
            } else {
                MyWhooshLoginForm(busy: $busy)
            }
        } options: {
            if signedIn {
                Toggle("Neue Pläne automatisch senden", isOn: $model.profile.autoSendToMyWhoosh)
            }
        }
    }
}
