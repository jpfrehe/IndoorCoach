import SwiftUI

/// Aufzeichnung mit Gurt für Kraft und „Andere Einheit“ (W3-A): Vollbild, Stopp, Abschluss-Sheet, Speichern.

/// Was das Vollbild aufzeichnet. `title` ist bei „Andere Einheit“ die Sportart.
struct RecordingRequest: Identifiable, Equatable {
    let id = UUID()
    var kind: RecordingKind
    var title: String
    var template: StrengthTemplate?
    /// Gesicherte Häkchen und Vorlage einer unterbrochenen Kraft-Aufzeichnung.
    var restored: StoredStrengthState?

    static func strength(template: StrengthTemplate?) -> RecordingRequest {
        RecordingRequest(kind: .strength, title: "Kraft", template: template)
    }

    static func other(sport: String) -> RecordingRequest { RecordingRequest(kind: .other, title: sport) }

    /// Fortsetzen einer unterbrochenen Aufzeichnung: Häkchen und Vorlagenname kommen aus der Zwischenspeicherung zurück.
    static func resumed(kind: RecordingKind, title: String, restored: StoredStrengthState? = nil) -> RecordingRequest {
        RecordingRequest(kind: kind, title: title, restored: restored)
    }
}

extension RecordingResult: Identifiable {}

extension View {
    func recordingCover<Item: Identifiable, C: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> C) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
}

/// Inhalt des Aufzeichnungs-Vollbilds für `.strength` und `.other`.
struct StrengthRecordingView: View {
    var request: RecordingRequest
    var service: RecordingService = .shared

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [PerformedExercise]
    @State private var finished: RecordingResult?
    @State private var confirmDiscard = false

    init(request: RecordingRequest, service: RecordingService = .shared) {
        self.request = request
        self.service = service
        let list = request.restored?.exercises
            ?? request.template?.makeExercises().map { e -> PerformedExercise in var c = e; c.checked = false; return c } ?? []
        _exercises = State(initialValue: list)
    }

    var body: some View {
        RecordingView(kind: request.kind, title: request.title, service: service, onFinish: { finished = $0 }) {
            VStack(alignment: .leading, spacing: 16) {
                if finished == nil {
                    if StrapSession.shared.savedStrapID == nil { noStrapHint }
                    if request.kind == .strength {
                        Text("Übungen").font(.headline)
                        StrengthExerciseChecklist(exercises: $exercises)
                    }
                    if service.isRunning {
                        Button(role: .destructive) { confirmDiscard = true } label: {
                            Text("Aufzeichnung verwerfen").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("recording.discard")
                    }
                }
            }
        }
        .confirmationDialog("Aufzeichnung verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) { service.cancel(); dismiss() }
                .accessibilityIdentifier("recording.discard.confirm")
            Button("Weiter aufzeichnen", role: .cancel) {}
        } message: {
            Text("Nichts wird gespeichert. Das lässt sich nicht rückgängig machen.")
        }
        .onChange(of: exercises) { pushState() }
        .onChange(of: service.isRunning) { pushState() }
        .sheet(item: $finished) { result in
            RecordedSessionFinish(result: result, templateName: templateName, exercises: exercises, service: service) {
                finished = nil
                dismiss()
            }
        }
    }

    private var templateName: String? {
        if let restored = request.restored { return restored.templateName }
        return request.template.flatMap { $0.name == StrengthTemplate.lastWeekName ? nil : $0.name }
    }

    /// Sichert Häkchen und Vorlage mit der Zwischenspeicherung der Aufzeichnung (nur Kraft).
    private func pushState() {
        guard request.kind == .strength, service.isRunning else { return }
        service.updateStrength(StoredStrengthState(templateName: templateName, exercises: exercises))
    }

    private var noStrapHint: some View {
        Card(title: "Kein Gurt gekoppelt", systemImage: "heart.slash.circle") {
            Text("Ohne Gurt gibt es keinen Puls. Du kannst trotzdem starten, die Einheit hat dann nur Dauer und Härte.")
                .font(.subheadline)
            NavigationLink { DevicesView() } label: {
                Label("Gurt koppeln (Geräte)", systemImage: "link").frame(minHeight: 44)
            }
            .accessibilityIdentifier("recording.noStrap.link")
        }
        .accessibilityIdentifier("recording.noStrap")
    }
}

/// Abschluss-Sheet einer aufgezeichneten Einheit: Härte, Beine, Notiz → `saveStrength(from:draft:)`.
/// Kann nicht weggewischt werden; „Verwerfen“ fragt nach.
struct RecordedSessionFinish: View {
    var result: RecordingResult
    var templateName: String?
    var exercises: [PerformedExercise] = []
    /// Bestätigt nach dem Speichern bzw. Verwerfen, dass die Zwischendatei weg darf.
    var service: RecordingService = .shared
    var onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var confirmDiscard = false

    var body: some View {
        StrengthFinishSheet(templateName: templateName, exercises: exercises.filter(\.isPerformed),
                            sportName: result.kind == .other ? result.title : nil,
                            onSave: save, onDiscard: { confirmDiscard = true })
            .interactiveDismissDisabled()
            .confirmationDialog("Einheit verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) { service.confirmHandled(result); onDone() }
                    .accessibilityIdentifier("strength.finish.discard.confirm")
                Button("Zurück", role: .cancel) {}
            } message: {
                Text("Die Aufzeichnung wird nicht gespeichert.")
            }
    }

    private func save(_ draft: StrengthDraft) {
        if Int(result.duration.rounded()) <= 0 {
            model.show("Die Einheit war zu kurz zum Speichern.", error: true)
            service.confirmHandled(result)
            onDone()
        } else if model.saveStrength(from: result, draft: draft) != nil {
            model.show(result.kind == .other ? "\(result.title) gespeichert." : "Krafteinheit gespeichert.", error: false)
            service.confirmHandled(result)
            onDone()
        }
        // Sonst ist das Speichern gescheitert (Banner steht): das Sheet bleibt offen, die Zwischendatei liegt weiter bereit.
    }
}
