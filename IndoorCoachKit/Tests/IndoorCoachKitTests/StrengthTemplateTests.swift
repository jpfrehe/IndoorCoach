import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("StrengthTemplate")
struct StrengthTemplateTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func session(daysAgo: Double, name: String?, exercises: [PerformedExercise]) -> StrengthSession {
        StrengthSession(start: t0.addingTimeInterval(-daysAgo * 86400), durationSeconds: 3600,
                        exercises: exercises, templateName: name)
    }

    @Test func fromSessionKeepsOrderAndDefaults() {
        let s = session(daysAgo: 7, name: nil, exercises: [
            PerformedExercise(exerciseID: "squat", sets: 4, reps: 6, weightKg: 90),
            PerformedExercise(exerciseID: "plank"),
        ])
        let t = StrengthTemplate.from(session: s, name: "Beine")
        #expect(t.name == "Beine")
        #expect(t.exerciseIDs == ["squat", "plank"])
        #expect(t.defaults["squat"] == SetDefaults(sets: 4, reps: 6, weightKg: 90))
        #expect(t.defaults["plank"] == nil)
    }

    @Test func makeExercisesCopiesDefaultsUnchecked() {
        let t = StrengthTemplate(name: "X", exerciseIDs: ["squat", "plank"],
                                 defaults: ["squat": SetDefaults(sets: 3, reps: 8, weightKg: 60)])
        let ex = t.makeExercises()
        #expect(ex.map(\.exerciseID) == ["squat", "plank"])
        #expect(ex[0].sets == 3 && ex[0].reps == 8 && ex[0].weightKg == 60)
        #expect(ex[1].sets == nil)
        #expect(ex.allSatisfy { !$0.checked })
    }

    @Test func lastWeekPicksLatestWithSameNameCaseInsensitive() {
        let old = session(daysAgo: 14, name: "Beine", exercises: [PerformedExercise(exerciseID: "lunge")])
        let recent = session(daysAgo: 7, name: "beine", exercises: [PerformedExercise(exerciseID: "squat", sets: 3, reps: 5, weightKg: 100)])
        let other = session(daysAgo: 2, name: "Oberkörper", exercises: [PerformedExercise(exerciseID: "bench_press")])
        let t = StrengthTemplate.lastWeek(named: "Beine", in: [old, other, recent])
        #expect(t?.exerciseIDs == ["squat"])
        #expect(t?.defaults["squat"]?.weightKg == 100)
        #expect(t?.name == "Beine")
    }

    @Test func lastWeekWithoutNameUsesLatestSessionWithVolume() {
        let withVolume = session(daysAgo: 10, name: nil, exercises: [PerformedExercise(exerciseID: "squat", sets: 3, reps: 5)])
        let newerNoVolume = session(daysAgo: 3, name: nil, exercises: [PerformedExercise(exerciseID: "plank")])
        let t = StrengthTemplate.lastWeek(named: nil, in: [newerNoVolume, withVolume])
        #expect(t?.exerciseIDs == ["squat"])
        #expect(t?.name == StrengthTemplate.lastWeekName)
    }

    @Test func lastWeekWithoutNameFallsBackToLatestWithExercises() {
        let a = session(daysAgo: 10, name: nil, exercises: [PerformedExercise(exerciseID: "lunge")])
        let b = session(daysAgo: 3, name: nil, exercises: [PerformedExercise(exerciseID: "plank")])
        #expect(StrengthTemplate.lastWeek(named: nil, in: [a, b])?.exerciseIDs == ["plank"])
    }

    @Test func lastWeekNilWhenNothingMatches() {
        #expect(StrengthTemplate.lastWeek(named: "Beine", in: []) == nil)
        let empty = session(daysAgo: 1, name: "Beine", exercises: [])
        #expect(StrengthTemplate.lastWeek(named: "Beine", in: [empty]) == nil)
        let arms = session(daysAgo: 1, name: "Arme", exercises: [PerformedExercise(exerciseID: "biceps_curl")])
        #expect(StrengthTemplate.lastWeek(named: "Beine", in: [arms]) == nil)
    }

    @Test func suggestedLegShareFromExerciseIDs() {
        #expect(StrengthTemplate(name: "a", exerciseIDs: ["plank", "squat"]).suggestedLegShare == .heavy)
        #expect(StrengthTemplate(name: "a", exerciseIDs: ["plank"]).suggestedLegShare == LegInvolvement.none)
    }

    @Test func codableRoundTrip() throws {
        let t = StrengthTemplate(name: "A", exerciseIDs: ["squat"], defaults: ["squat": SetDefaults(sets: 3, reps: 5, weightKg: 80)])
        let back = try JSONDecoder().decode(StrengthTemplate.self, from: JSONEncoder().encode(t))
        #expect(back == t)
    }
}
