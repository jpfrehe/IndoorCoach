import SwiftUI

// Dünne Unterseiten der Profil-Startseite (docs/18, AP4): Winter Arc, Coach, Erinnerungen, Hilfe, Speicher.

/// Profil → Winter Arc: Saisonstart, Ziel-Tag und Ziel-Fitness.
struct WinterArcSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let season = WinterArc.defaultSeason(containing: .now)
        Form {
            Section {
                DatePicker("Saisonstart", selection: Binding(get: { model.profile.arcStart ?? season.start },
                                                              set: { model.profile.arcStart = $0 }),
                           displayedComponents: .date)
                LabeledContent("Ziel-Tag", value: (model.winterArc(rides: model.allRides())?.goal ?? season.goal)
                    .formatted(.dateTime.day().month(.wide).year().locale(Locale.de)))
                Stepper(value: Binding(get: { Int(model.profile.targetCTL ?? 0) },
                                       set: { model.profile.targetCTL = $0 == 0 ? nil : Double($0) }),
                        in: 0...150, step: 1) {
                    LabeledContent("Ziel-Fitness", value: model.profile.targetCTL.map { Formatters.decimal($0) } ?? "automatisch")
                }
            } footer: {
                Text("Vom Saisonstart bis zum Ziel-Tag baust du Fitness auf. Ziel-Tag ist dein Zieldatum, wenn es höchstens 8 Monate nach dem Start liegt, sonst der 21. März. „Automatisch“ setzt das Ziel auf +35 % der Start-Fitness, mindestens +15.")
            }
        }
        // ANCHOR-B1-SETTING: Schalter „Feiern nach der Fahrt“ (`model.momentsEnabled`) als eigene Section im Form – Agent A
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Winter Arc")
    }
}

/// Profil → Coach · Claude: API-Key, Modell, Datenschutz und Link zur Console.
struct CoachSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ClaudeKeyForm(showsRemove: true)
                Picker("Modell", selection: $model.profile.model) {
                    ForEach(ClaudeModel.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                    Label("Claude Console – API-Keys", systemImage: "key")
                }
            } footer: {
                Text("API-Key aus console.anthropic.com (nicht das claude.ai-Abo). Der Key liegt nur im Schlüsselbund dieses iPhones. Ein Plan kostet mit Opus 5.5 ca. 0,10 $.")
            }
            // ANCHOR-W4C (Profil → Coach · Claude: Claude-Einwilligung)
            ClaudePrivacySection()
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
        .navigationTitle("Coach · Claude")
    }
}

/// Profil → Erinnerungen.
struct ReminderSettingsView: View {
    var body: some View {
        Form {
            ReminderSection()
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Erinnerungen")
    }
}

/// Profil → Hilfe & Feedback.
struct HelpView: View {
    var body: some View {
        Form {
            HelpFeedbackSection()
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Hilfe & Feedback")
    }
}

/// Profil → Daten auf diesem iPhone: „Alle Daten löschen“ (die einzige destruktive Aktion außerhalb der Dienste).
struct StorageView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDeleteAll = false

    var body: some View {
        Form {
            Section {
                Button("Alle Daten löschen", role: .destructive) { confirmDeleteAll = true }
                    .frame(minHeight: 44)
                    .confirmationDialog("Alle Daten löschen?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                        Button("Alle Daten löschen", role: .destructive) { Task { await model.deleteAllData() } }
                    } message: {
                        Text("Gelöscht werden alle Fahrten, geplanten Einheiten und Krafttrainings, Gesundheits- und Morgenmessungs-Daten, die Kalendereinträge der App samt Kalender „Indoor Training“, alle Erinnerungen, Claude-API-Key, Strava-Zugang und -Client-Secret, MyWhoosh-Anmeldung, intervals.icu-Zugang, Mac-Kopplung, der gespeicherte Brustgurt sowie Profil und Einstellungen. Deine Daten bei Strava, MyWhoosh und intervals.icu bleiben erhalten. Das lässt sich nicht rückgängig machen.")
                    }
            } footer: {
                Text("Entfernt alles, was IndoorCoach auf diesem iPhone gespeichert hat.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Daten auf diesem iPhone")
    }
}
