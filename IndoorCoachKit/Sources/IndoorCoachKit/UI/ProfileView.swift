import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var stravaSecretInput = ""
    @State private var confirmDisconnect = false
    @State private var showFITImporter = false
    /// iPhone SE: "Client-Secret" wraps onto two lines; a tap on the label line now focuses the field too (audit 3).
    @FocusState private var stravaSecretFocused: Bool
    /// Ziel and Hinweise are multi-line (Return adds a line): while one is edited, the section header offers "Fertig"
    /// (audit 3: on the iPhone SE the keyboard otherwise covered half the list). A keyboard toolbar logged
    /// "Invalid frame dimension" on every appearance, hence the header.
    @FocusState private var goalEditing: Bool

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                athleteSection(model)
                goalSection(model)
                availabilitySection(model)
                seasonSection(model)
                // ANCHOR-CONNECTIONS (AP2 ersetzt diesen Block durch „Dienste & Geräte“)
                stravaSection(model).id(ProfileView.stravaSectionID)
                myWhooshSection(model)
                // ANCHOR-STRAP (Geräte → Brustgurt)
                Section("Geräte") {
                    NavigationLink { DevicesView() } label: {
                        Label("Brustgurt", systemImage: "heart.circle").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("profile.strap")
                }
                // ANCHOR-W3D (Profil → Datenquellen)
                Section("Daten") {
                    NavigationLink { DataSourcesView() } label: {
                        Label("Datenquellen", systemImage: "heart.text.square").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("profile.dataSources")
                }
                appSection(model)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .scrollsToStravaSectionOnRequest()
            .fileImporter(isPresented: $showFITImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { model.importFITFiles(urls) }
            }
            .navigationTitle("Profil")
            .confirmationDialog("Strava trennen?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Trennen", role: .destructive) { Task { await model.disconnectStrava() } }
            } message: {
                Text("Synchronisierte Fahrten werden aus der App entfernt.")
            }
        }
    }

    // MARK: Sections

    private func athleteSection(_ model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            Stepper(value: $model.profile.ftp, in: 80...500, step: 5) {
                LabeledContent("FTP", value: "\(model.profile.ftp) W")
            }
            Stepper(value: $model.profile.weightKg, in: 40...150, step: 0.5) {
                LabeledContent("Gewicht", value: "\(Formatters.decimal(model.profile.weightKg, digits: 1)) kg")
            }
            LabeledContent("W/kg", value: Formatters.decimal(model.calculationProfile.wattsPerKg, digits: 2))
            Stepper(value: Binding(get: { model.profile.thresholdHeartRate ?? 0 },
                                   set: { model.profile.thresholdHeartRate = $0 == 0 ? nil : $0 }),
                    in: 0...210, step: 1) {
                LabeledContent("Schwellen-HF", value: model.profile.thresholdHeartRate.map { "\($0) bpm" } ?? "–")
            }
            Stepper(value: $model.profile.restingHeartRate, in: 30...100, step: 1) {
                LabeledContent("Ruhe-HF", value: "\(model.profile.restingHeartRate) bpm")
            }
            Stepper(value: Binding(get: { min(230, max(120, model.profile.heartRateProfile.max)) },
                                   set: { model.profile.maxHeartRate = $0 }),
                    in: 120...230, step: 1) {
                LabeledContent("Max-HF", value: "\(model.profile.heartRateProfile.max) bpm" + (model.profile.maxHeartRate == nil ? " (geschätzt)" : ""))
            }
        } header: { Text("Athlet") } footer: {
            Text("Die FTP bestimmt alle Wattangaben. Ruhe- und Max-HF braucht der Relative Effort für Fahrten mit Herzfrequenz.")
        }
    }

    private func goalSection(_ model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            TextField("Ziel", text: $model.profile.goal, prompt: Text("z. B. FTP auf 280 W bis zum Frühjahr"), axis: .vertical)
                .lineLimit(2...4)
                .focused($goalEditing)
                .accessibilityLabel("Ziel")
            Toggle("Zieldatum", isOn: Binding(get: { model.profile.goalDate != nil },
                                             set: { model.profile.goalDate = $0 ? (model.profile.goalDate ?? Calendar.current.date(byAdding: .month, value: 3, to: .now)) : nil }))
            if let date = model.profile.goalDate {
                DatePicker("Datum", selection: Binding(get: { date }, set: { model.profile.goalDate = $0 }),
                           in: Date.now..., displayedComponents: .date)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Hinweise für den Coach").font(.caption).foregroundStyle(.secondary)
                TextField("Hinweise für den Coach", text: $model.profile.notes,
                          prompt: Text("z. B. Knie schonen, keine Sprints"), axis: .vertical)
                    .lineLimit(1...4)
                    .focused($goalEditing)
            }
        } header: {
            HStack {
                Text("Ziel")
                Spacer(minLength: 8)
                if goalEditing {
                    Button("Fertig") { goalEditing = false }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("keyboard.done")
                }
            }
        } footer: {
            Text("Ziel und Hinweise werden beim Planen an Claude (Anthropic) gesendet – bitte keine sensiblen Gesundheitsdaten.")
        }
    }

    private func seasonSection(_ model: AppModel) -> some View {
        let goalDay = model.winterArc(rides: model.allRides())?.goal ?? WinterArc.defaultSeason(containing: .now).goal
        return Section("Saison & Training") {
            NavigationLink { WinterArcSettingsView() } label: {
                LabeledContent {
                    Text(goalDay.formatted(.dateTime.day().month(.abbreviated).locale(Locale.de)))
                } label: {
                    Label("Winter Arc", systemImage: "snowflake")
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.winterArc")
            // ANCHOR-STRENGTH (Profil → Kraft)
            NavigationLink { StrengthSettingsView() } label: {
                Label("Kraft", systemImage: "dumbbell").frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.strength")
        }
    }

    private func availabilitySection(_ model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            WeekdayPicker(days: $model.profile.trainingDays)
            Stepper(value: $model.profile.weeklyHours, in: 1...20, step: 0.5) {
                LabeledContent("Wochenbudget", value: "\(Formatters.decimal(model.profile.weeklyHours, digits: 1)) h")
            }
            Stepper(value: $model.profile.longestSessionMinutes, in: 30...240, step: 15) {
                LabeledContent("Max. pro Einheit", value: "\(model.profile.longestSessionMinutes) min")
            }
            DatePicker("Startzeit", selection: Binding(
                get: { Calendar.current.date(bySettingHour: model.profile.preferredStartHour, minute: model.profile.preferredStartMinute, second: 0, of: .now) ?? .now },
                set: {
                    model.profile.preferredStartHour = Calendar.current.component(.hour, from: $0)
                    model.profile.preferredStartMinute = Calendar.current.component(.minute, from: $0)
                }), displayedComponents: .hourAndMinute)
        } header: { Text("Verfügbarkeit") } footer: {
            Text("Der Coach plant nur an markierten Tagen. Die Startzeit wird für Kalendereinträge genutzt.")
        }
    }

    private func appSection(_ model: AppModel) -> some View {
        Section("App") {
            NavigationLink { CoachSettingsView() } label: {
                LabeledContent {
                    Text(model.hasClaudeKey ? "Bereit" : "Key fehlt")
                } label: {
                    Label("Coach · Claude", systemImage: "sparkles")
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.coach")
            // ANCHOR-K2-PROFIL (Erinnerungen)
            NavigationLink { ReminderSettingsView() } label: {
                Label("Erinnerungen", systemImage: "bell").frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.reminders")
            NavigationLink { HelpView() } label: {
                Label("Hilfe & Feedback", systemImage: "questionmark.circle").frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.help")
            NavigationLink { StorageView() } label: {
                Label("Daten auf diesem iPhone", systemImage: "internaldrive").frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.storage")
        }
    }

    private func stravaSection(_ model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            if model.isStravaConnected {
                LabeledContent("Verbunden", value: model.stravaAthleteName ?? "Strava")
                if let last = model.lastSync {
                    LabeledContent("Letzter Sync", value: last.formatted(.relative(presentation: .named).locale(Locale.de)))
                }
                Button {
                    Task { await model.syncStrava() }
                } label: {
                    HStack {
                        Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                        if model.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.isSyncing)
                Button("Alle Fahrten neu laden (210 Tage)") { Task { await model.syncStrava(full: true) } }
                    .disabled(model.isSyncing)
                Button("Strava trennen", role: .destructive) { confirmDisconnect = true }
            } else {
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
                        SecureField("Client-Secret", text: $stravaSecretInput, prompt: Text("aus strava.com/settings/api"))
                            .plainTextInput()
                            .credentialInput()
                            .multilineTextAlignment(.trailing)
                            .focused($stravaSecretFocused)
                            .onSubmit { model.setStravaClientSecret(stravaSecretInput); stravaSecretInput = "" }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { stravaSecretFocused = true }
                }
                Button {
                    if !stravaSecretInput.isEmpty {
                        model.setStravaClientSecret(stravaSecretInput)
                        stravaSecretInput = ""
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
                .disabled(model.stravaClientID.isEmpty || (!model.hasStravaSecret && stravaSecretInput.isEmpty))
            }
            Link(destination: URL(string: "https://www.strava.com/settings/api")!) { Label("Strava API-Einstellungen", systemImage: "gearshape") }
        } header: { Text("Strava") } footer: {
            if !model.isStravaConnected {
                Text("Einmalig unter strava.com/settings/api eine eigene API-App anlegen. Als „Authorization Callback Domain“ localhost eintragen. Client-ID und Client-Secret hier einfügen.")
            }
        }
    }

    @State private var whooshBusy = false

    private func myWhooshSection(_ model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            if let user = model.myWhooshUser {
                LabeledContent("Verbunden", value: user)
                Toggle("Neue Pläne automatisch senden", isOn: $model.profile.autoSendToMyWhoosh)
                Button {
                    Task { await model.importMyWhooshRides(full: true) }   // known rides are skipped, so the full window is cheap
                } label: {
                    HStack {
                        Label("Fahrten aus MyWhoosh laden", systemImage: "arrow.down.circle")
                        if model.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.isSyncing)
                if let last = model.lastMyWhooshImport {
                    LabeledContent("Letzter Import", value: last.formatted(.relative(presentation: .named).locale(Locale.de)))
                }
                Button("Bei MyWhoosh abmelden", role: .destructive) { Task { await model.disconnectMyWhoosh() } }
            } else {
                MyWhooshLoginForm(busy: $whooshBusy)
            }
            // ANCHOR-BRIDGE: IndoorCoach Brücke (Mac) – Sekundendaten
            NavigationLink { MacBridgeView() } label: {
                LabeledContent {
                    Text(model.isBridgePaired ? (model.bridgeMacName ?? "Gekoppelt") : "Einrichten")
                } label: {
                    Label("Sekundendaten vom Mac", systemImage: "macbook.and.iphone")
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.bridge")
            Button { showFITImporter = true } label: {
                Label("FIT-Dateien importieren …", systemImage: "doc.badge.plus")
            }
            Link(destination: URL(string: "https://workout.mywhoosh.com")!) { Label("MyWhoosh Workout Builder", systemImage: "figure.indoor.cycle") }
        } header: { Text("MyWhoosh") } footer: {
            Text("Einheiten landen direkt in MyWhoosh unter „Custom Workouts“ und im MyWhoosh-Kalender, deine gefahrenen Einheiten lädt die App von dort zurück – ganz ohne Strava. Nutzt die inoffizielle MyWhoosh-Schnittstelle; sie kann sich jederzeit ändern. Dann bleiben die .zwo-Datei und der FIT-Import (Dateien-App, auch von Zwift oder Wahoo) als Weg. Dein Passwort wird nur zur Anmeldung gesendet und nicht gespeichert.")
        }
    }
}
