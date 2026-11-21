import AuthenticationServices
import SwiftUI

/// Profil → Dienste & Geräte → Strava: Zugangsdaten, Verbinden, Sync, Trennen.
struct StravaConnectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var secretInput = ""
    /// iPhone SE: "Client-Secret" wraps onto two lines; a tap on the label line now focuses the field too (audit 3).
    @FocusState private var secretFocused: Bool

    var body: some View {
        @Bindable var model = model
        let descriptor = model.connection(.strava)
        ConnectionDetailScaffold(
            title: "Strava",
            footer: model.isStravaConnected ? nil
                : "Einmalig unter strava.com/settings/api eine eigene API-App anlegen. Als „Authorization Callback Domain“ localhost eintragen. Client-ID und Client-Secret hier einfügen.",
            help: ConnectionHelpLink(title: "Strava API-Einstellungen", systemImage: "gearshape",
                                     url: URL(string: "https://www.strava.com/settings/api")!),
            disconnect: model.isStravaConnected
                ? ConnectionDisconnect(buttonTitle: "Strava trennen", dialogTitle: "Strava trennen?", confirmTitle: "Trennen",
                                       message: "Synchronisierte Fahrten werden aus der App entfernt.", identifier: "strava.disconnect") {
                    Task { await model.disconnectStrava() }
                } : nil,
            showsOptions: model.isStravaConnected
        ) {
            ConnectionStatusHeader(status: descriptor.status, syncTitle: "Letzter Sync",
                                   account: model.isStravaConnected ? model.stravaAthleteName : nil,
                                   lastSync: model.isStravaConnected ? model.lastSync : nil)
        } main: {
            if model.isStravaConnected {
                Button {
                    Task { await model.syncStrava() }
                } label: {
                    HStack {
                        Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                        if model.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.isSyncing)
            } else {
                credentials
            }
        } options: {
            if model.isStravaConnected {
                Button("Alle Fahrten neu laden (210 Tage)") { Task { await model.syncStrava(full: true) } }
                    .disabled(model.isSyncing)
            }
        }
    }

    @ViewBuilder
    private var credentials: some View {
        @Bindable var model = model
        LabeledContent("Client-ID") {
            TextField("Client-ID", text: $model.stravaClientID, prompt: Text("z. B. 123456"))
                .numericKeyboard().plainTextInput()
                .multilineTextAlignment(.trailing)
        }
        if model.hasStravaSecret {
            LabeledContent("Client-Secret") {
                Label { Text("Gespeichert") } icon: { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.done) }
            }
        } else {
            LabeledContent("Client-Secret") {
                SecureField("Client-Secret", text: $secretInput, prompt: Text("aus strava.com/settings/api"))
                    .plainTextInput()
                    .credentialInput()
                    .multilineTextAlignment(.trailing)
                    .focused($secretFocused)
                    .onSubmit { model.setStravaClientSecret(secretInput); secretInput = "" }
            }
            .contentShape(Rectangle())
            .onTapGesture { secretFocused = true }
        }
        Button {
            if !secretInput.isEmpty {
                model.setStravaClientSecret(secretInput)
                secretInput = ""
            }
            Task {
                await model.connectStrava { url in
                    try await webAuth.authenticate(using: url, callbackURLScheme: StravaConfig.callbackScheme,
                                                   preferredBrowserSession: .shared)
                }
            }
        } label: {
            Label("Mit Strava verbinden", systemImage: "link")
                .font(.headline)
                .foregroundStyle(Theme.strava)
        }
        .disabled(model.stravaClientID.isEmpty || (!model.hasStravaSecret && secretInput.isEmpty))
    }
}
