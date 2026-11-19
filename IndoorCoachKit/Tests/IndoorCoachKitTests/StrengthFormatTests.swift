import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Krafttraining (Texte)")
struct StrengthFormatTests {
    @Test func exertionTextCoversScale() {
        #expect(StrengthFormat.exertionText(nil) == "Härte fehlt")
        #expect(StrengthFormat.exertionText(11) == "Härte fehlt")
        #expect(StrengthFormat.exertionText(0) == "0 · Ruhe")
        #expect(StrengthFormat.exertionText(7) == "7 · Hart")
        #expect(StrengthFormat.exertionText(10) == "10 · Maximal")
    }

    @Test func volumeSummary() {
        #expect(StrengthFormat.volume(PerformedExercise(exerciseID: "squat")) == nil)
        #expect(StrengthFormat.volume(PerformedExercise(exerciseID: "squat", sets: 3, reps: 8, weightKg: 62.5)) == "3 × 8 · 62,5 kg")
        #expect(StrengthFormat.volume(PerformedExercise(exerciseID: "plank", sets: 3)) == "3 Sätze")
        #expect(StrengthFormat.volume(PerformedExercise(exerciseID: "squat", reps: 10, weightKg: 80)) == "10 Wdh. · 80 kg")
    }

    @Test func unknownExerciseFallsBackToID() {
        #expect(StrengthFormat.exerciseName("squat") == "Kniebeuge")
        #expect(StrengthFormat.exerciseName("xyz") == "xyz")
    }

    @Test func weekdaysCoverAllSevenOnce() {
        #expect(StrengthSettingsView.weekdays.map(\.day).sorted() == [1, 2, 3, 4, 5, 6, 7])
    }
}
