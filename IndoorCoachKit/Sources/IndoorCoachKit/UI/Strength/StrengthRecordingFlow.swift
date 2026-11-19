import SwiftUI

/// Aufzeichnung mit Gurt für Kraft und „Andere Einheit“ (W3-A): Vollbild, Stopp, Abschluss-Sheet, Speichern.

/// Was das Vollbild aufzeichnet. `title` ist bei „Andere Einheit“ die Sportart.
struct RecordingRequest: Identifiable, Equatable {
    let id = UUID()
    var kind: RecordingKind
    var title: String
    var template: StrengthTemplate?

    static func strength(template: StrengthTemplate?) -> RecordingRequest {
        RecordingRequest(kind: .strength, title: "Kraft", template: template)
    }

    static func other(sport: String) -> RecordingRequest { RecordingRequest(kind: .other, title: sport) }

    /// Fortsetzen einer unterbrochenen Aufzeichnung (Übungen sind nicht gesichert).
    static func resumed(kind: RecordingKind, title: String) -> RecordingRequest {
        RecordingRequest(kind: kind, title: title)
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
        let list = request.template?.makeExercises().map { e -> PerformedExercise in var c = e; c.checked = false; return c } ?? []
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
            Button("Verwerfen", role: .destructive) { service.stop(); dismiss() }
                .accessibilityIdentifier("recording.discard.confirm")
            Button("Weiter aufzeichnen", role: .cancel) {}
        } message: {
            Text("Nichts wird gespeichert. Das lässt sich nicht rückgängig machen.")
        }
        .sheet(item: $finished) { result in
            RecordedSessionFinish(result: result, templateName: templateName, exercises: exercises) {
                finished = nil
                dismiss()
            }
        }
    }

    private var templateName: String? {
        request.template.flatMap { $0.name == StrengthTemplate.lastWeekName ? nil : $0.name }
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
    var onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var confirmDiscard = false

    var body: some View {
        StrengthFinishSheet(templateName: templateName, exercises: exercises.filter(\.isPerformed),
                            sportName: result.kind == .other ? result.title : nil,
                            onSave: save, onDiscard: { confirmDiscard = true })
            .interactiveDismissDisabled()
            .confirmationDialog("Einheit verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) { onDone() }
                    .accessibilityIdentifier("strength.finish.discard.confirm")
                Button("Zurück", role: .cancel) {}
            } message: {
                Text("Die Aufzeichnung wird nicht gespeichert.")
            }
    }

    private func save(_ draft: StrengthDraft) {
        if model.saveStrength(from: result, draft: draft) != nil {
            model.show(result.kind == .other ? "\(result.title) gespeichert." : "Krafteinheit gespeichert.", error: false)
        } else {
            model.show("Die Einheit war zu kurz zum Speichern.", error: true)
        }
        onDone()
    }
}
