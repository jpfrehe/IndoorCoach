import SwiftUI

/// Abhak-Liste der Übungen einer Krafteinheit. Einbettbar (z. B. in den Slot der Aufzeichnung): Das Häkchen genügt,
/// Sätze × Wiederholungen × Gewicht sind optional und kommen mit Vorwerten aus der Vorlage.
struct StrengthExerciseChecklist: View {
    @Binding var exercises: [PerformedExercise]
    var allowsAdding = true
    @State private var expanded: String?
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if exercises.isEmpty {
                Text("Noch keine Übung. Füge eine hinzu oder speichere nur Dauer und Härte.")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }
            ForEach($exercises) { $exercise in
                row($exercise)
            }
            if allowsAdding {
                Button { showPicker = true } label: {
                    Label("Übung hinzufügen", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("strength.checklist.add")
            }
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet(excluding: Set(exercises.map(\.exerciseID))) { e in
                exercises.append(PerformedExercise(exerciseID: e.id, checked: true))
            }
        }
    }

    private func row(_ exercise: Binding<PerformedExercise>) -> some View {
        let id = exercise.wrappedValue.exerciseID
        let done = exercise.wrappedValue.isPerformed
        let isOpen = expanded == id
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { exercise.wrappedValue.checked.toggle() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: exercise.wrappedValue.checked ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(exercise.wrappedValue.checked ? Theme.accent : Theme.rowSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(StrengthFormat.exerciseName(id)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            if let volume = StrengthFormat.volume(exercise.wrappedValue) {
                                Text(volume).font(.caption).foregroundStyle(Theme.rowSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(done ? .isSelected : [])
                .accessibilityValue(done ? "gemacht" : "offen")
                .accessibilityIdentifier("strength.checklist.\(id)")

                Button { expanded = isOpen ? nil : id } label: {
                    Image(systemName: isOpen ? "chevron.up.circle" : "slider.horizontal.3")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Sätze und Gewicht für \(StrengthFormat.exerciseName(id))")
                .accessibilityIdentifier("strength.checklist.\(id).details")
            }
            if isOpen {
                VStack(spacing: 0) {
                    OptionalStepper(title: "Sätze", value: exercise.sets, range: 0...20, identifier: "strength.\(id).sets")
                    OptionalStepper(title: "Wiederholungen", value: exercise.reps, range: 0...100, identifier: "strength.\(id).reps")
                    OptionalWeightStepper(value: exercise.weightKg, identifier: "strength.\(id).weight")
                    Button(role: .destructive) {
                        exercises.removeAll { $0.exerciseID == id }
                        expanded = nil
                    } label: {
                        Text("Übung entfernen").frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.softFill.opacity(done ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
