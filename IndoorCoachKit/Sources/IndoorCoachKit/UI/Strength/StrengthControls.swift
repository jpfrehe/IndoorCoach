import SwiftUI

/// Wird vom PO am Wurzel-View gesetzt: startet die Aufzeichnung mit Brustgurt für eine Krafteinheit (optional mit
/// Vorlage). Ohne Wert (`nil`) blenden die Kraft-Sheets „Mit Gurt aufzeichnen“ aus.
typealias StrengthRecordAction = @MainActor @Sendable (StrengthTemplate?) -> Void

private struct StrengthRecordActionKey: EnvironmentKey {
    static let defaultValue: StrengthRecordAction? = nil
}

extension EnvironmentValues {
    var strengthRecordAction: StrengthRecordAction? {
        get { self[StrengthRecordActionKey.self] }
        set { self[StrengthRecordActionKey.self] = newValue }
    }
}

extension View {
    /// Verdrahtung der Aufzeichnung (Integration): `rootView.strengthRecordAction { template in … }`.
    func strengthRecordAction(_ action: @escaping StrengthRecordAction) -> some View {
        environment(\.strengthRecordAction, action)
    }
}

/// Für `ForEach($exercises)`: eine Übung kommt je Einheit höchstens einmal vor.
extension PerformedExercise: Identifiable {
    public var id: String { exerciseID }
}

/// Texte und Formatierung rund um Krafteinheiten.
enum StrengthFormat {
    static func exerciseName(_ id: String) -> String { ExerciseCatalog.exercise(id: id)?.name ?? id }

    static func sourceLabel(_ source: StrengthSource) -> String {
        switch source {
        case .recorded: "Aufgezeichnet (Brustgurt)"
        case .manual: "Nachgetragen"
        case .healthAnnotation: "Apple Health, ergänzt"
        }
    }

    static func title(_ row: StoredStrengthSession) -> String {
        if let sport = row.sportName { return sport }
        return row.templateName.map { "Kraft · \($0)" } ?? "Krafttraining"
    }

    static func exertionText(_ value: Int?) -> String {
        guard let value, (0...10).contains(value) else { return "Härte fehlt" }
        return "\(value) · \(label(forExertion: value))"
    }

    static func label(forExertion value: Int) -> String {
        value == 0 ? "Ruhe" : (RelativeEffort.perceivedExertionLabels[value] ?? "")
    }

    static func weight(_ kg: Double) -> String {
        (kg.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(kg)) : String(format: "%.1f", kg).replacingOccurrences(of: ".", with: ",")) + " kg"
    }

    /// Kurzfassung eines Satzes, z. B. „3 × 8 · 60 kg“.
    static func volume(_ e: PerformedExercise) -> String? {
        var parts: [String] = []
        if let sets = e.sets, let reps = e.reps { parts.append("\(sets) × \(reps)") }
        else if let sets = e.sets { parts.append("\(sets) Sätze") }
        else if let reps = e.reps { parts.append("\(reps) Wdh.") }
        if let kg = e.weightKg, kg > 0 { parts.append(weight(kg)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Große Auswahl-Kachel (≥ 48 pt) im Stil der Check-in-Kacheln.
struct ChoiceTile: View {
    var title: String
    var selected: Bool
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(selected ? Theme.ink : Theme.accent)
                .background(selected ? AnyShapeStyle(Theme.sunset) : AnyShapeStyle(Theme.softFill),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Härte nach CR-10: Kacheln 0–10 und der Klartext darunter. Nochmal tippen nimmt die Angabe zurück.
struct ExertionPicker: View {
    @Binding var value: Int?
    var idPrefix = "strength.exertion"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                ForEach(0...10, id: \.self) { n in
                    ChoiceTile(title: "\(n)", selected: value == n, identifier: "\(idPrefix).\(n)") {
                        value = (value == n) ? nil : n
                    }
                    .accessibilityLabel("Härte \(n), \(StrengthFormat.label(forExertion: n))")
                }
            }
            Text(value.map { "\($0) · \(StrengthFormat.label(forExertion: $0))" } ?? "Optional. Ohne Härte fehlt die Muskel-Last.")
                .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                .accessibilityIdentifier("\(idPrefix).label")
        }
    }
}

/// Beinanteil: keine / leicht / schwer.
struct LegInvolvementPicker: View {
    @Binding var value: LegInvolvement
    var idPrefix = "strength.legs"

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LegInvolvement.allCases, id: \.self) { leg in
                ChoiceTile(title: leg.label.prefix(1).uppercased() + leg.label.dropFirst(), selected: value == leg,
                           identifier: "\(idPrefix).\(leg.rawValue)") { value = leg }
                    .accessibilityLabel("Beine \(leg.label)")
            }
        }
    }
}

/// Stepper für optionale Zahlen: `nil` zeigt „–“, 0 setzt zurück.
struct OptionalStepper: View {
    var title: String
    @Binding var value: Int?
    var range: ClosedRange<Int>
    var identifier: String

    var body: some View {
        Stepper(value: Binding(get: { value ?? 0 }, set: { value = $0 <= 0 ? nil : $0 }), in: 0...range.upperBound) {
            LabeledContent(title, value: value.map(String.init) ?? "–")
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier(identifier)
    }
}

struct OptionalWeightStepper: View {
    @Binding var value: Double?
    var identifier: String

    var body: some View {
        Stepper(value: Binding(get: { value ?? 0 }, set: { value = $0 <= 0 ? nil : $0 }), in: 0...500, step: 2.5) {
            LabeledContent("Gewicht", value: value.map(StrengthFormat.weight) ?? "–")
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier(identifier)
    }
}

/// Übungskatalog zum Hinzufügen: gruppiert nach der ersten Muskelgruppe, mit Suche.
struct ExercisePickerSheet: View {
    var excluding: Set<String> = []
    var onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    let items = ExerciseCatalog.all.filter { $0.muscles.first == group && !excluding.contains($0.id) && matches($0) }
                    if !items.isEmpty {
                        Section(group.label) {
                            ForEach(items) { e in
                                Button { onPick(e); dismiss() } label: {
                                    HStack {
                                        Text(e.name)
                                        Spacer()
                                        Text("Beine \(e.legInvolvement.label)").font(.caption).foregroundStyle(Theme.rowSecondary)
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .accessibilityIdentifier("strength.pick.\(e.id)")
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Übung suchen")
            .navigationTitle("Übung hinzufügen")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }

    private func matches(_ e: Exercise) -> Bool {
        query.isEmpty || e.name.localizedCaseInsensitiveContains(query)
    }
}
