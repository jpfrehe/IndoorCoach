import AuthenticationServices
import SwiftUI

/// Profil → Dienste & Geräte → intervals.icu: Anmelden (OAuth oder API-Key), Pläne senden, Fahrten laden, Trennen.
struct IntervalsConnectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var apiKey = ""
    @State private var connecting = false
    @State private var keyOpen = false
    @FocusState private var keyFocused: Bool

    private static let sharedText = "IndoorCoach sendet deine geplanten Einheiten in deinen intervals.icu-Kalender und liest deine Fahrten. Die Daten gehen direkt an intervals.icu, nicht an uns."
    private static let forwardText = "Damit Einheiten in Zwift, Garmin, Wahoo oder Rouvy erscheinen, schalte in intervals.icu unter Einstellungen → Connections die Übertragung geplanter Workouts ein."

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        @Bindable var model = model
        let descriptor = model.connection(.intervalsICU)
        let connected = model.isIntervalsConnected
        ConnectionDetailScaffold(
            title: "intervals.icu",
            footer: connected ? "\(Self.sharedText)\n\n\(Self.forwardText)" : Self.sharedText,
            help: ConnectionHelpLink(title: "intervals.icu Einstellungen", systemImage: "gearshape",
                                     url: URL(string: "https://intervals.icu/settings")!),
            disconnect: connected
                ? ConnectionDisconnect(buttonTitle: "intervals.icu trennen", dialogTitle: "intervals.icu trennen?", confirmTitle: "Trennen",
                                       message: "Importierte Fahrten bleiben in der App. Bereits gesendete Einheiten bleiben in deinem intervals.icu-Kalender.",
                                       identifier: "intervals.disconnect") {
                    Task { await model.disconnectIntervals() }
                } : nil,
            showsOptions: connected
        ) {
            ConnectionStatusHeader(status: descriptor.status, syncTitle: "Letzter Import",
                                   account: connected ? (model.intervalsAthleteName ?? (model.intervalsUsesAPIKey ? "Persönlicher API-Key" : nil)) : nil,
                                   lastSync: connected ? model.lastIntervalsImport : nil)
        } main: {
            if connected {
                Button {
                    Task { await model.importIntervalsRides() }
                } label: {
                    HStack {
                        Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                        if model.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.isSyncing)
            } else {
                login
            }
        } options: {
            if connected {
                Toggle("Neue Pläne automatisch senden", isOn: $model.profile.autoSendToIntervals)
                    .accessibilityIdentifier("intervals.autoSend")
                Button {
                    Task { await model.sendUpcomingToIntervals() }
                } label: {
                    HStack {
                        Label("Geplante Einheiten jetzt senden", systemImage: "paperplane")
                        if model.isSendingToIntervals { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.isSendingToIntervals)
                .accessibilityIdentifier("intervals.sendAll")
                Button("Alle Fahrten neu laden (210 Tage)") { Task { await model.importIntervalsRides(full: true) } }
                    .disabled(model.isSyncing)
            }
        }
    }

    @ViewBuilder
    private var login: some View {
        if model.intervalsConfig.isOAuthAvailable {
            Button {
                connecting = true
                Task {
                    defer { connecting = false }
                    await model.connectIntervals { url in
                        try await webAuth.authenticate(using: url, callbackURLScheme: IntervalsConfig.callbackScheme,
                                                       preferredBrowserSession: .shared)
                    }
                }
            } label: {
                HStack {
                    Label("Mit intervals.icu verbinden", systemImage: "link").font(.headline)
                    if connecting { Spacer(); ProgressView() }
                }
            }
            .disabled(connecting)
            .accessibilityIdentifier("intervals.connect")
            DisclosureGroup("API-Key verwenden", isExpanded: $keyOpen) { keyForm }
        } else {
            Text("Die Anmeldung über intervals.icu ist noch nicht verfügbar. Verbinde dich bis dahin mit deinem persönlichen API-Key.")
                .font(.subheadline).foregroundStyle(.secondary)
            keyForm
        }
    }

    private func connectWithKey() {
        let key = trimmedKey
        guard !key.isEmpty, !connecting else { return }
        connecting = true
        keyFocused = false
        Task {
            defer { connecting = false }
            if await model.connectIntervals(apiKey: key) { apiKey = "" }
        }
    }

    @ViewBuilder
    private var keyForm: some View {
        LabeledContent("API-Key") {
            SecureField("API-Key", text: $apiKey, prompt: Text("aus intervals.icu"))
                .plainTextInput()
                .credentialInput()
                .multilineTextAlignment(.trailing)
                .focused($keyFocused)
                .submitLabel(.go)
                .onSubmit { connectWithKey() }
                .accessibilityIdentifier("intervals.apiKey")
        }
        .contentShape(Rectangle())
        .onTapGesture { keyFocused = true }
        Button { connectWithKey() } label: {
            HStack {
                Label("Mit API-Key verbinden", systemImage: "key")
                if connecting { Spacer(); ProgressView() }
            }
        }
        .disabled(trimmedKey.isEmpty || connecting)
        .accessibilityIdentifier("intervals.connectKey")
        Text("Nur für dein eigenes Konto. Den Schlüssel findest du in intervals.icu unter Einstellungen → Developer Settings.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
