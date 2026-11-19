import SwiftData
import SwiftUI

/// Karte für „Heute": fragt vor der geplanten Einheit nach dem Befinden, später zeigt sie noch offene Angebote.
/// Erscheint nur mit geplanter Einheit heute (nie an Ruhetagen), höchstens ein Check-in pro Tag.
struct CheckInCard: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredWorkout.date) private var workouts: [StoredWorkout]
    @Query private var checkIns: [StoredCheckIn]
    @State private var showSheet = false

    /// Debug builds with a UI-test seed hide the check-in unless `-uiCheckIn YES` is passed, so existing UI tests stay unchanged.
    static var suppressedInUITests: Bool {
        #if DEBUG
        let defaults = UserDefaults.standard
        return defaults.string(forKey: "uiSeed") != nil && !defaults.bool(forKey: "uiCheckIn")
        #else
        false
        #endif
    }

    var body: some View {
        let calendar = Calendar.current
        let workout = workouts.first { !$0.isDeleted && $0.status == .planned && calendar.isDateInToday($0.date) }
        let existing = checkIns.first { calendar.isDateInToday($0.day) }
        if !Self.suppressedInUITests, let workout {
            if existing == nil {
                card(title: "Wie startest du heute?", text: "Drei Tipps, unter 10 Sekunden. Du kannst auch überspringen.",
                     button: "Check-in", id: "checkin.card.start", workout: workout, existing: nil, skippable: true)
            } else if let existing, !existing.skipped, existing.chosen == nil, workout.originalSegmentsData == nil,
                      !existing.offered.isEmpty || existing.answers.hasInfection {
                card(title: "Dein Check-in", text: CheckIn.healthHint(for: existing.answers) ?? "Es gibt Angebote für heute.",
                     button: "Angebote ansehen", id: "checkin.card.offers", workout: workout, existing: existing, skippable: false)
            }
        }
    }

    private func card(title: String, text: String, button: String, id: String, workout: StoredWorkout,
                      existing: StoredCheckIn?, skippable: Bool) -> some View {
        Card(title: title, systemImage: "heart.text.square") {
            Text(text).font(.subheadline).foregroundStyle(Theme.rowSecondary)
            HStack(spacing: 10) {
                Button { showSheet = true } label: { Text(button).frame(maxWidth: .infinity) }
                    .buttonStyle(.jelly)
                    .accessibilityIdentifier(id)
                if skippable {
                    Button { model.skipCheckIn() } label: { Text("Später").frame(maxWidth: .infinity) }
                        .buttonStyle(.soft)
                        .accessibilityIdentifier("checkin.card.skip")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showSheet) { CheckInSheet(workout: workout, existing: existing) }
    }
}
