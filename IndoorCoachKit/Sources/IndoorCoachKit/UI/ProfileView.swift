import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [ProfileRoute] = []
    /// Ziel and Hinweise are multi-line (Return adds a line): while one is edited, the section header offers "Fertig"
    /// (audit 3: on the iPhone SE the keyboard otherwise covered half the list). A keyboard toolbar logged
    /// "Invalid frame dimension" on every appearance, hence the header.
    @FocusState private var goalEditing: Bool

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            Form {
                athleteSection(model)
                goalSection(model)
                availabilitySection(model)
                seasonSection(model)
                connectionsSection(model)
                appSection(model)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .navigationTitle("Profil")
            .navigationDestination(for: ProfileRoute.self) { destination($0) }
            // Sprung von außen (Onboarding, Heute): erst den Wechsel auf den Tab abwarten, dann den Pfad setzen.
            // Sofort entnehmen, damit kein Sprung liegen bleibt. Nicht `.task(id:)`: das Entnehmen ändert die ID
            // und bräche den laufenden Task samt Pfadwechsel ab.
            .onChange(of: model.pendingProfileRoute, initial: true) {
                guard let route = model.takePendingProfileRoute() else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    path = route
                }
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: ProfileRoute) -> some View {
        switch route {
        case .connections: ConnectionsView()
        case .connection(let id): ConnectionDestination(id: id)
        case .coach: CoachSettingsView()
        case .winterArc: WinterArcSettingsView()
        case .strength: StrengthSettingsView()
        case .reminders: ReminderSettingsView()
        case .help: HelpView()
        case .storage: StorageView()
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
            NavigationLink(value: ProfileRoute.winterArc) {
                LabeledContent {
                    Text(goalDay.formatted(.dateTime.day().month(.abbreviated).locale(Locale.de)))
                } label: {
                    Label("Winter Arc", systemImage: "snowflake")
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.winterArc")
            // ANCHOR-STRENGTH (Profil → Kraft)
            NavigationLink(value: ProfileRoute.strength) {
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
            NavigationLink(value: ProfileRoute.coach) {
                LabeledContent {
                    Text(model.hasClaudeKey ? "Bereit" : "Key fehlt")
                } label: {
                    Label("Coach · Claude", systemImage: "sparkles")
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.coach")
            // ANCHOR-K2-PROFIL (Erinnerungen)
            NavigationLink(value: ProfileRoute.reminders) {
                Label("Erinnerungen", systemImage: "bell").frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.reminders")
            NavigationLink(value: ProfileRoute.help) {
                Label("Hilfe & Feedback", systemImage: "questionmark.circle").frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.help")
            NavigationLink(value: ProfileRoute.storage) {
                Label("Daten auf diesem iPhone", systemImage: "internaldrive").frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.storage")
        }
    }

    private func connectionsSection(_ model: AppModel) -> some View {
        let all = model.connections()
        let attention = all.filter(\.status.needsAttention)
        let connected = all.filter { id in
            if id.id == .fitImport { return false }
            if case .connected = id.status { return true }
            return false
        }.count
        return Section {
            NavigationLink(value: ProfileRoute.connections) {
                LabeledContent {
                    if attention.isEmpty {
                        Text(connected == 0 ? "Keine" : "\(connected) verbunden")
                    } else {
                        Label("\(attention.count) \(attention.count == 1 ? "Hinweis" : "Hinweise")",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } label: {
                    Label("Dienste & Geräte", systemImage: "cable.connector")
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile.connections")
            ForEach(attention) { descriptor in
                NavigationLink(value: ProfileRoute.connection(descriptor.id)) {
                    Label {
                        Text("\(descriptor.name): \(Self.attentionText(descriptor.status))")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile.attention.\(descriptor.id.rawValue)")
            }
        } header: { Text("Verbindungen") } footer: {
            Text("Woher deine Fahrten kommen und wohin Pläne gehen.")
        }
    }

    private static func attentionText(_ status: ConnectionStatus) -> String {
        switch status {
        case .needsSetup(let text), .error(let text): text
        case .connected, .notConnected, .unavailable: status.label
        }
    }
}
