import SwiftUI

/// Nachtragen ohne Aufzeichnung: Krafteinheit (mit optionalen Übungen) oder „Andere Einheit“ (Sportart, Dauer, Härte).
/// Alles ist vorbelegt (jetzt, 45 min), sodass Speichern ein Tipp ist.
struct StrengthEntryForm: View {
    enum Kind: Equatable { case strength, other }

    var kind: Kind
    var template: StrengthTemplate?
    /// Wird nach dem Speichern aufgerufen (z. B. um das umgebende Sheet zu schließen).
    var onSaved: () -> Void = {}

    @Environment(AppModel.self) private var model
    @State private var start = Date.now
    @State private var minutes: Int
    @State private var exertion: Int?
    @State private var legs: LegInvolvement
    @State private var legsTouched = false
    @State private var exercises: [PerformedExercise]
    @State private var showExercises: Bool
    @State private var sport = StrengthEntryForm.sports[0]
    @State private var note = ""

    /// Auswahl für „Andere Einheit“ (Namen kennt `SportClassification`).
    static let sports = ["Laufen", "Laufband", "Wandern", "Rudern", "Schwimmen", "Crosstrainer", "Kurs", "Bouldern", "Rumpf", "Sonstiges"]

    init(kind: Kind, template: StrengthTemplate? = nil, onSaved: @escaping () -> Void = {}) {
        self.kind = kind
        self.template = template
        self.onSaved = onSaved
        let list = template?.makeExercises().map { e -> PerformedExercise in var c = e; c.checked = false; return c } ?? []
        _exercises = State(initialValue: list)
        _showExercises = State(initialValue: !list.isEmpty)
        _minutes = State(initialValue: kind == .strength ? 45 : 40)
        _legs = State(initialValue: kind == .strength ? (template?.suggestedLegShare ?? LegInvolvement.none) : .none)
    }

    var body: some View {
        Form {
            if kind == .other {
                Section("Sportart") {
                    Picker("Sportart", selection: $sport) {
                        ForEach(Self.sports, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("strength.entry.sport")
                    Text(trackHint).font(.footnote).foregroundStyle(Theme.rowSecondary)
                }
            }
            Section("Wann und wie lange") {
                DatePicker("Beginn", selection: $start, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("strength.entry.start")
                Stepper(value: $minutes, in: 5...300, step: 5) {
                    LabeledContent("Dauer", value: "\(minutes) min")
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("strength.entry.duration")
            }
            Section("Härte") {
                ExertionPicker(value: $exertion)
            }
            if showsLegs {
                Section("Beine") {
                    LegInvolvementPicker(value: Binding(get: { legs }, set: { legs = $0; legsTouched = true }))
                }
            }
            if kind == .strength {
                Section {
                    DisclosureGroup("Übungen (optional)", isExpanded: $showExercises) {
                        StrengthExerciseChecklist(exercises: $exercises)
                    }
                    .accessibilityIdentifier("strength.entry.exercises")
                }
            }
            Section("Notiz") {
                TextField("Optional", text: $note, axis: .vertical).lineLimit(1...3)
            }
            Section {
                Button { save() } label: { Text("Speichern").frame(maxWidth: .infinity) }
                    .buttonStyle(.jelly)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("strength.entry.save")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle(kind == .strength ? "Kraft nachtragen" : "Andere Einheit")
        .inlineNavigationTitle()
        .onChange(of: exercises) { _, new in
            if !legsTouched, kind == .strength { legs = ExerciseCatalog.legShare(for: new) }
        }
    }

    private var showsLegs: Bool {
        kind == .strength || SportClassification.category(for: sport).feedsMuscleTrack
    }

    private var trackHint: String {
        SportClassification.category(for: sport).feedsMuscleTrack
            ? "Fließt in die Muskel-Last."
            : "Erscheint im Verlauf. Keine Belastungsrechnung."
    }

    private func save() {
        let done = exercises.filter(\.isPerformed)
        let leg: LegInvolvement? = {
            if kind == .strength { return legs }
            return SportClassification.category(for: sport).feedsMuscleTrack ? legs : nil
        }()
        let row = model.saveStrengthManual(start: start, durationMinutes: minutes, exertion: exertion, legShare: leg,
                                           exercises: done, templateName: template.flatMap { $0.name == StrengthTemplate.lastWeekName ? nil : $0.name },
                                           note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                           sportName: kind == .other ? sport : nil)
        if row != nil {
            model.show(kind == .strength ? "Krafteinheit gespeichert." : "\(sport) gespeichert.", error: false)
            onSaved()
        }
    }
}
