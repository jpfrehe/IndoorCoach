import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var claudeKeyInput = ""
    @State private var stravaSecretInput = ""
    @State private var confirmDisconnect = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                athleteSection(model)
                goalSection(model)
                availabilitySection(model)
                coachSection(model)
                stravaSection(model)
                infoSection
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
            LabeledContent("W/kg", value: Formatters.decimal(model.profile.wattsPerKg, digits: 2))
            Stepper(value: Binding(get: { model.profile.thresholdHeartRate ?? 0 },
                                   set: { model.profile.thresholdHeartRate = $0 == 0 ? nil : $0 }),
                    in: 0...210, step: 1) {
                LabeledContent("Schwellen-HF", value: model.profile.thresholdHeartRate.map { "\($0) bpm" } ?? "–")
            }
        } header: { Text("Athlet") } footer: {
            Text("Die FTP bestimmt alle Wattangaben. Leistungen im Plan werden als % FTP gespeichert und passen sich automatisch an.")
        }
    }

    private func goalSection(_ model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            TextField("Ziel", text: $model.profile.goal, axis: .vertical).lineLimit(2...4)
            Toggle("Zieldatum", isOn: Binding(get: { model.profile.goalDate != nil },
                                             set: { model.profile.goalDate = $0 ? (model.profile.goalDate ?? Calendar.current.date(byAdding: .month, value: 3, to: .now)) : nil }))
            if let date = model.profile.goalDate {
                DatePicker("Datum", selection: Binding(get: { date }, set: { model.profile.goalDate = $0 }),
                           in: Date.now..., displayedComponents: .date)
            }
            TextField("Hinweise für den Coach (z. B. Knie schonen, keine Sprints)", text: $model.profile.notes, axis: .vertical)
                .lineLimit(1...4)
        } header: { Text("Ziel") } footer: {
            Text("Ziel und Hinweise werden beim Planen an Claude (Anthropic) gesendet – bitte keine sensiblen Gesundheitsdaten.")
        }
    }

    private func availabilitySection(_ model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let on = model.profile.trainingDays.contains(day)
                    Button {
                        if on { model.profile.trainingDays.removeAll { $0 == day } }
                        else { model.profile.trainingDays.append(day); model.profile.trainingDays.sort() }
                    } label: {
                        Text(AthleteProfile.weekdayNames[day] ?? "")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(on ? .white : .primary)
                            .background(on ? AnyShapeStyle(Theme.accent.gradient) : AnyShapeStyle(.quaternary),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AthleteProfile.weekdayLongNames[day] ?? "")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
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

    private func coachSection(_ model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            if model.hasClaudeKey {
                LabeledContent("API-Key") {
                    Label("Gespeichert", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                Button("API-Key entfernen", role: .destructive) { model.setClaudeAPIKey("") }
            } else {
                SecureField("sk-ant-…", text: $claudeKeyInput).plainTextInput()
                Button("API-Key speichern") {
                    model.setClaudeAPIKey(claudeKeyInput)
                    claudeKeyInput = ""
                }
                .disabled(claudeKeyInput.trimmingCharacters(in: .whitespaces).count < 20)
            }
            Picker("Modell", selection: $model.profile.model) {
                ForEach(ClaudeModel.allCases) { Text($0.label).tag($0.rawValue) }
            }
        } header: { Text("Coach · Claude") } footer: {
            Text("API-Key aus console.anthropic.com (nicht das claude.ai-Abo). Der Key liegt nur im Schlüsselbund dieses iPhones. Ein Plan kostet mit Opus 5.5 ca. 0,10 $.")
        }
    }

    private func stravaSection(_ model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            if model.isStravaConnected {
                LabeledContent("Verbunden", value: model.stravaAthleteName ?? "Strava")
                if let last = model.lastSync {
                    LabeledContent("Letzter Sync", value: last.formatted(.relative(presentation: .named).locale(Locale(identifier: "de_DE"))))
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
                Button("Alle Fahrten neu laden (120 Tage)") { Task { await model.syncStrava(full: true) } }
                    .disabled(model.isSyncing)
                Button("Strava trennen", role: .destructive) { confirmDisconnect = true }
            } else {
                TextField("Client-ID", text: $model.stravaClientID).numericKeyboard().plainTextInput()
                if model.hasStravaSecret {
                    LabeledContent("Client-Secret") {
                        Label("Gespeichert", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                } else {
                    SecureField("Client-Secret", text: $stravaSecretInput).plainTextInput()
                        .onSubmit { model.setStravaClientSecret(stravaSecretInput); stravaSecretInput = "" }
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
                        .foregroundStyle(Color(red: 0.99, green: 0.32, blue: 0.0))
                }
                .disabled(model.stravaClientID.isEmpty || (!model.hasStravaSecret && stravaSecretInput.isEmpty))
            }
        } header: { Text("Strava") } footer: {
            if !model.isStravaConnected {
                Text("Einmalig unter strava.com/settings/api eine eigene API-App anlegen. Als „Authorization Callback Domain“ localhost eintragen. Client-ID und Client-Secret hier einfügen.")
            }
        }
    }

    private var infoSection: some View {
        Section("Links") {
            Link(destination: URL(string: "https://www.strava.com/settings/api")!) { Label("Strava API-Einstellungen", systemImage: "gearshape") }
            Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) { Label("Claude Console – API-Keys", systemImage: "key") }
            Link(destination: URL(string: "https://workout.mywhoosh.com")!) { Label("MyWhoosh Workout Builder", systemImage: "figure.indoor.cycle") }
        }
    }
}
