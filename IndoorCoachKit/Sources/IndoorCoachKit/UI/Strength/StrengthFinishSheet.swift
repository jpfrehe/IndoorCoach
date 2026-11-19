import SwiftUI

/// Abschluss einer aufgezeichneten Krafteinheit: Härte (CR-10), Beine (aus den Übungen vorbelegt) und Notiz.
/// Der Aufrufer speichert mit `AppModel.saveStrength(from:draft:)`.
struct StrengthFinishSheet: View {
    var templateName: String?
    var exercises: [PerformedExercise]
    /// Gesetzt bei „Andere Einheit“: Beine nur bei muskulärer Sportart, Speichern als Einheit mit Sportart.
    var sportName: String?
    var onSave: (StrengthDraft) -> Void
    var onDiscard: (() -> Void)?

    @State private var exertion: Int?
    @State private var legs: LegInvolvement
    @State private var note = ""

    init(templateName: String? = nil, exercises: [PerformedExercise], sportName: String? = nil,
         onSave: @escaping (StrengthDraft) -> Void, onDiscard: (() -> Void)? = nil) {
        self.templateName = templateName
        self.exercises = exercises
        self.sportName = sportName
        self.onSave = onSave
        self.onDiscard = onDiscard
        _legs = State(initialValue: ExerciseCatalog.legShare(for: exercises))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Wie hart war es?") { ExertionPicker(value: $exertion) }
                    if showsLegs { section("Beine") {
                        LegInvolvementPicker(value: $legs)
                        Text("Vorbelegt aus deinen Übungen. Du kannst ändern.")
                            .font(.footnote).foregroundStyle(Theme.rowSecondary)
                    } }
                    section("Notiz") {
                        TextField("Optional", text: $note, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(12)
                            .background(Theme.softFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("strength.finish.note")
                    }
                    Button { onSave(draft) } label: { Text("Speichern").frame(maxWidth: .infinity) }
                        .buttonStyle(.jelly)
                        .accessibilityIdentifier("strength.finish.save")
                    if let onDiscard {
                        Button(role: .destructive) { onDiscard() } label: { Text("Verwerfen").frame(maxWidth: .infinity, minHeight: 44) }
                            .accessibilityIdentifier("strength.finish.discard")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationTitle("Einheit abschließen")
            .inlineNavigationTitle()
        }
        .presentationDetents([.large])
    }

    private var showsLegs: Bool {
        sportName.map { SportClassification.category(for: $0).feedsMuscleTrack } ?? true
    }

    var draft: StrengthDraft {
        if let sportName { return .otherSport(sportName, exertion: exertion, legShare: legs, note: note) }
        return StrengthDraft(templateName: templateName, exercises: exercises, exertion: exertion, legShare: legs,
                      note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}
