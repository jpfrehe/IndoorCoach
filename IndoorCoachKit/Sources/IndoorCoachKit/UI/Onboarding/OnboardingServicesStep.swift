import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    /// „Zwift“, „Rouvy“ oder „Zwift und Rouvy“, wenn intervals.icu wegen dieser Antworten empfohlen wurde (R4/R5); sonst nil.
    /// Nur dann braucht es den einen Schritt in intervals.icu („Zwift verbinden“).
    var intervalsForwardTargets: String? {
        guard let reasons = serviceRecommendations.first(where: { $0.id == .intervalsICU })?.reasons else { return nil }
        var names: [String] = []
        if reasons.contains(.intervalsZwift) { names.append("Zwift") }
        if reasons.contains(.intervalsRouvy) { names.append("Rouvy") }
        return names.isEmpty ? nil : Formatters.germanList(names)
    }
}

/// Oberflächen-Zustand von „Für dich passt“. Gehört der Elternansicht, damit er einen Schrittwechsel überlebt
/// (Zurück aus „Coach“ zeigt aufgeklappte Karten, Fehler und das offene MyWhoosh-Formular wie vorher).
struct ServicesStepUIState: Equatable {
    var expanded: Set<ConnectionID> = []
    var whooshFormOpen = false
    var activeID: ConnectionID?
    var errors: [ConnectionID: String] = [:]
    var showMore = false
}

/// Schritt 4 · Für dich passt: Empfehlungen als Karten, nach Stufen geordnet (docs/20 §6.5).
/// Verbinden passiert hier, ohne die Einführung zu verlassen.
struct OnboardingServicesStep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    /// MyWhoosh-Anmeldung läuft (gehört der Elternansicht, weil das Formular nach dem Verbinden verschwindet).
    @Binding var whooshBusy: Bool
    /// Eine andere Verbindung läuft (intervals.icu, Health).
    @Binding var otherBusy: Bool
    @Binding var ui: ServicesStepUIState
    /// Ein Feld im MyWhoosh-Formular hat den Fokus (die Elternansicht hält den Anmelden-Knopf über der Tastatur).
    var onEditing: () -> Void

    /// Ein Blatt zur Zeit; das Datei-Fenster hängt an einem eigenen Anker (mehrere `.sheet` am selben View sind unzuverlässig).
    private enum Sheet: String, Identifiable {
        case bridge, strap
        var id: String { rawValue }
    }
    @State private var sheet: Sheet?
    @State private var showFITImporter = false

    private var expanded: Set<ConnectionID> { ui.expanded }
    private var whooshFormOpen: Bool { ui.whooshFormOpen }
    private var activeID: ConnectionID? { ui.activeID }
    private var errors: [ConnectionID: String] { ui.errors }
    /// Vom Modell gemerkt, nicht im View-State: überlebt Schrittwechsel und Neustart.
    private var fitImported: Int? { model.onboardingServices.fitImportedCount > 0 ? model.onboardingServices.fitImportedCount : nil }

    private var answers: ServiceAnswers { model.onboardingServices.answers }

    var body: some View {
        let recommendations = model.serviceRecommendations
        let lines = model.onboardingSummary.services
        let showAll = answers.showAll
        let recommended = recommendations.filter { $0.tier == .recommended }
        let optional = recommendations.filter { $0.tier == .optional }
        let advanced = recommendations.filter { $0.tier == .advanced }
        let more = recommendations.filter { $0.tier == .more }

        VStack(alignment: .leading, spacing: 16) {
            if recommended.isEmpty && optional.isEmpty { emptyState }
            section("Empfohlen", id: "onboarding.section.recommended", entries: recommended, lines: lines,
                    hidden: showAll)
            section(showAll ? "Dienste" : "Auch möglich", id: "onboarding.section.optional", entries: optional, lines: lines)
            section("Für Fortgeschrittene", id: "onboarding.section.advanced", entries: advanced, lines: lines)
            if !more.isEmpty { moreServices(more, lines: lines) }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .bridge: OnboardingBridgeSheet()
            case .strap: OnboardingStrapSheet()
            }
        }
        .background {
            Color.clear.fileImporter(isPresented: $showFITImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                importFIT(result)
            }
        }
    }

    // MARK: Abschnitte

    private var emptyState: some View {
        Card {
            Label {
                Text("Für den Start brauchst du nichts zu verbinden. IndoorCoach plant deine Woche auch so, und du hakst Einheiten einfach ab.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.seal").foregroundStyle(Theme.accent)
            }
        }
        .accessibilityIdentifier("onboarding.emptyState")
    }

    @ViewBuilder
    private func section(_ title: String, id: String, entries: [ServiceRecommendation],
                         lines: [OnboardingSummary.ServiceLine], hidden: Bool = false) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if !hidden {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(id)
                }
                ForEach(entries) { entry in card(entry, lines: lines) }
            }
        }
    }

    private func moreServices(_ entries: [ServiceRecommendation], lines: [OnboardingSummary.ServiceLine]) -> some View {
        DisclosureGroup(isExpanded: $ui.showMore) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(entries) { entry in card(entry, lines: lines) }
            }
            .padding(.top, 8)
        } label: {
            Text("Alle Dienste anzeigen")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .tint(Theme.accent)
        .accessibilityIdentifier("onboarding.moreServices")
    }

    // MARK: Karte

    private func isConnected(_ id: ConnectionID) -> Bool {
        if id == .fitImport { return fitImported != nil }
        if case .connected = model.connection(id).status { return true }
        return false
    }

    private func cardState(_ id: ConnectionID, lines: [OnboardingSummary.ServiceLine]) -> ServiceCardState {
        if id == .myWhoosh, whooshBusy { return .busy }
        if id != .myWhoosh, otherBusy, activeID == id { return .busy }
        if id == .fitImport, let count = fitImported {
            return .connected("\(count) \(count == 1 ? "Fahrt" : "Fahrten") übernommen oder ergänzt")
        }
        if id != .fitImport, let line = lines.first(where: { $0.id == id }), case .connected(let detail) = line.state {
            return .connected(detail)
        }
        if failure(id) != nil || (id == .myWhoosh && whooshFormOpen && model.lastMyWhooshError != nil) { return .failed }
        if model.onboardingServices.deferred.contains(id) { return .later }
        return .open
    }

    /// Fehlertext in der Karte; MyWhoosh zeigt ihn im Formular selbst.
    private func failure(_ id: ConnectionID) -> String? {
        switch id {
        case .intervalsICU: isConnected(id) ? nil : model.lastIntervalsError
        case .myWhoosh: nil
        default: errors[id]
        }
    }

    private func card(_ entry: ServiceRecommendation, lines: [OnboardingSummary.ServiceLine]) -> some View {
        let id = entry.id
        let descriptor = model.connection(id)
        let state = cardState(id, lines: lines)
        let locked = whooshBusy || otherBusy
        let isExpanded = entry.tier == .recommended || entry.tier == .advanced || expanded.contains(id)
        let title: String? = switch id {
        case .myWhoosh: whooshFormOpen ? nil : "Anmelden"
        case .intervalsICU, .strava: nil
        case .macBridge: "Einrichten"
        case .appleHealth: "Weiter zur Freigabe"
        case .strap: "Gurt koppeln"
        case .fitImport: "Dateien auswählen"
        }
        return ServiceRecommendationCard(
            recommendation: entry,
            name: id == .macBridge ? "Fahrten im Detail vom Mac" : (id == .fitImport ? "FIT-Dateien" : descriptor.name),
            symbol: descriptor.systemImage,
            state: state,
            error: failure(id),
            isExpanded: isExpanded,
            connectTitle: title,
            isLocked: locked,
            offersLater: id != .strava,
            laterNote: id == .macBridge ? "Kein Problem. Sobald du Fahrten hast, erinnert dich Verlauf → Leistung daran." : nil,
            onConnect: { connect(id) },
            onLater: { later(id) },
            onResume: { resume(id) },
            onToggleExpanded: { withAnimation(.snappy(duration: 0.2)) { _ = ui.expanded.insert(id) } },
            extraStatusID: id == .myWhoosh ? "onboarding.myWhooshStatus" : nil
        ) {
            content(for: entry, state: state)
        }
    }

    // MARK: Dienst-Inhalt

    @ViewBuilder
    private func content(for entry: ServiceRecommendation, state: ServiceCardState) -> some View {
        switch entry.id {
        case .myWhoosh: whooshContent(state: state)
        case .intervalsICU: intervalsContent(entry, state: state)
        case .macBridge:
            if !state.isConnected {
                OnboardingHint("MyWhoosh speichert jede Fahrt sekundengenau auf deinem Mac. Ein kleiner Gratis-Helfer, die IndoorCoach Brücke, schickt sie im WLAN ans iPhone. Nichts verlässt dein Zuhause. Was du brauchst: die Mac-App „IndoorCoach Brücke“.")
            }
        case .appleHealth:
            if state.isConnected {
                OnboardingHint("Ändern kannst du das jederzeit in der Health-App unter Teilen → Apps.")
            } else {
                OnboardingHint("Gleich fragt iOS, was IndoorCoach aus Health lesen darf: Workouts, Puls und Gewicht. Du kannst jedes einzeln erlauben. Die Werte bleiben auf deinem iPhone und gehen nicht an den Coach.")
            }
        case .strap:
            if !state.isConnected {
                OnboardingHint("Lege den Gurt an und befeuchte ihn kurz, dann findet das iPhone ihn.")
            }
        case .fitImport:
            if !state.isConnected {
                OnboardingHint("FIT ist das Dateiformat, das fast jede Trainings-App exportieren kann.")
            }
        case .strava:
            Toggle("Nach der Einführung einrichten",
                   isOn: Binding(get: { model.onboardingServices.stravaAfterwards },
                                 set: { model.onboardingServices.stravaAfterwards = $0 }))
                .accessibilityIdentifier("onboarding.service.strava.afterwards")
                .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func whooshContent(state: ServiceCardState) -> some View {
        if state.isConnected {
            if let user = model.myWhooshUser { OnboardingHint(user) }
        } else {
            OnboardingHint("Was du brauchst: dein MyWhoosh-Konto. Dein Passwort wird nur zur Anmeldung gesendet und nicht gespeichert.")
            OnboardingHint("Meldest du dich bei MyWhoosh mit Google oder Apple an? Lege dort zuerst ein Passwort fest.")
                .font(.footnote)
            if whooshFormOpen {
                MyWhooshLoginForm(busy: $whooshBusy,
                                  onConnected: { model.onboardingServices.deferred.remove(.myWhoosh) },
                                  onEditing: onEditing,
                                  errorContainerID: "onboarding.service.myWhoosh.error")
            }
        }
    }

    @ViewBuilder
    private func intervalsContent(_ entry: ServiceRecommendation, state: ServiceCardState) -> some View {
        if state.isConnected {
            Toggle("Neue Pläne automatisch senden",
                   isOn: Binding(get: { model.profile.autoSendToIntervals }, set: { model.profile.autoSendToIntervals = $0 }))
                .accessibilityIdentifier("intervals.autoSend")
                .frame(minHeight: 44)
            if let targets = model.intervalsForwardTargets {
                IntervalsForwardHint(targets: targets)
            }
        } else {
            OnboardingHint("intervals.icu ist ein kostenloser Trainingskalender. IndoorCoach legt deine Einheiten dort ab, intervals.icu schickt sie weiter.")
            OnboardingHint("Gleich fragt iOS, ob die Anmeldeseite von intervals.icu öffnen darf. Tippe auf „Fortfahren“. Noch kein Konto? Das legst du dort kostenlos an.")
            IntervalsOAuthButton(busy: Binding(get: { otherBusy && activeID == .intervalsICU }, set: { otherBusy = $0 }),
                                 style: entry.tier == .recommended ? .prominent : .soft,
                                 identifier: "onboarding.service.intervalsICU.connect",
                                 isLocked: whooshBusy || otherBusy,
                                 onStart: { ui.activeID = .intervalsICU; model.onboardingServices.deferred.remove(.intervalsICU) })
        }
    }

    // MARK: Aktionen

    private func connect(_ id: ConnectionID) {
        model.onboardingServices.deferred.remove(id)
        ui.errors[id] = nil
        switch id {
        case .myWhoosh:
            withAnimation(.snappy(duration: 0.2)) { ui.whooshFormOpen = true }
        case .macBridge: sheet = .bridge
        case .strap: sheet = .strap
        case .fitImport: showFITImporter = true
        case .appleHealth: connectHealth()
        case .intervalsICU, .strava: break
        }
    }

    private func later(_ id: ConnectionID) {
        withAnimation(.snappy(duration: 0.2)) {
            model.onboardingServices.deferred.insert(id)
            ui.expanded.remove(id)
            if id == .myWhoosh { ui.whooshFormOpen = false }
        }
        ui.errors[id] = nil
    }

    private func resume(_ id: ConnectionID) {
        withAnimation(.snappy(duration: 0.2)) {
            model.onboardingServices.deferred.remove(id)
            ui.expanded.insert(id)
        }
    }

    private func connectHealth() {
        ui.activeID = .appleHealth
        otherBusy = true
        Task {
            await model.setHealthEnabled(true)
            otherBusy = false
            if !model.healthEnabled {
                ui.errors[.appleHealth] = "Die Freigabe hat nicht geklappt. Du kannst sie später unter Profil → Dienste & Geräte → Apple Health nachholen."
            }
        }
    }

    private func importFIT(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let count = model.importFITFiles(urls)
            if count > 0 {
                model.onboardingServices.fitImportedCount += count
                ui.errors[.fitImport] = nil
            } else {
                ui.errors[.fitImport] = "Aus den Dateien wurde nichts übernommen. Entweder sind die Fahrten schon da, oder die Dateien sind keine FIT-Aktivitäten."
            }
        case .failure:
            ui.errors[.fitImport] = "Die Dateien konnten nicht geöffnet werden."
        }
    }
}

/// Der eine Schritt in intervals.icu: Zwift (bzw. Rouvy) dort verbinden. Gleicher Text auf der Karte und in „Alles bereit“.
struct IntervalsForwardHint: View {
    var targets: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(compact
                     ? "Denk an den einen Schritt in intervals.icu: \(targets) verbinden."
                     : "Noch ein Schritt in intervals.icu: Öffne Einstellungen → Connections, verbinde \(targets) und schalte „Upload planned workouts“ ein. Dann erscheinen deine Einheiten dort.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(Theme.accent)
            }
            .font(.subheadline)
            Link(destination: IntervalsTexts.settingsURL) {
                Label("intervals.icu-Einstellungen öffnen", systemImage: "arrow.up.right.square")
                    .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("onboarding.intervals.settings")
        }
    }
}
