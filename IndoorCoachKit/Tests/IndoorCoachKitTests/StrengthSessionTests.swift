import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("StrengthSession und Katalog")
struct StrengthSessionTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func codableRoundTripIsStable() throws {
        let s = StrengthSession(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            start: t0, durationSeconds: 3600, source: .healthAnnotation, exertion: 7, legShare: .heavy,
            exercises: [PerformedExercise(exerciseID: "squat", sets: 4, reps: 6, weightKg: 100)],
            templateName: "Beine + Rumpf", note: "gut")
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(StrengthSession.self, from: data)
        #expect(back == s)
    }

    @Test func rawValuesAreStable() {
        #expect(StrengthSource.recorded.rawValue == "recorded")
        #expect(StrengthSource.manual.rawValue == "manual")
        #expect(StrengthSource.healthAnnotation.rawValue == "healthAnnotation")
        #expect(LegInvolvement.heavy.rawValue == "heavy")
    }

    @Test func endAndMinutes() {
        let s = StrengthSession(start: t0, durationSeconds: 2700)
        #expect(s.end == t0.addingTimeInterval(2700))
        #expect(s.durationMinutes == 45)
    }

    @Test func exertionOutsideRangeIsInvalid() {
        #expect(StrengthSession(start: t0, durationSeconds: 60, exertion: 11).validExertion == nil)
        #expect(StrengthSession(start: t0, durationSeconds: 60, exertion: -1).validExertion == nil)
        #expect(StrengthSession(start: t0, durationSeconds: 60, exertion: 0).validExertion == 0)
        #expect(StrengthSession(start: t0, durationSeconds: 60, exertion: 10).validExertion == 10)
        #expect(StrengthSession(start: t0, durationSeconds: 60).validExertion == nil)
    }

    @Test func effectiveLegShareUsesExplicitValueFirst() {
        let s = StrengthSession(start: t0, durationSeconds: 60, legShare: LegInvolvement.none,
                                exercises: [PerformedExercise(exerciseID: "squat")])
        #expect(s.effectiveLegShare == LegInvolvement.none)
    }

    @Test func effectiveLegShareFallsBackToExercises() {
        let s = StrengthSession(start: t0, durationSeconds: 60, exercises: [PerformedExercise(exerciseID: "squat")])
        #expect(s.effectiveLegShare == .heavy)
        #expect(StrengthSession(start: t0, durationSeconds: 60).effectiveLegShare == LegInvolvement.none)
    }

    // MARK: Katalog

    @Test func catalogHasAboutFortyUniqueExercises() {
        let ids = ExerciseCatalog.all.map(\.id)
        #expect(ids.count >= 38 && ids.count <= 45)
        #expect(Set(ids).count == ids.count)
        #expect(ExerciseCatalog.all.allSatisfy { !$0.name.isEmpty && !$0.muscles.isEmpty })
    }

    @Test func catalogContainsRequiredExercises() {
        let required = ["squat", "front_squat", "deadlift", "romanian_deadlift", "leg_press", "lunge",
                        "bulgarian_split_squat", "step_up", "hip_thrust", "leg_extension", "leg_curl", "calf_raise",
                        "goblet_squat", "box_jump", "kettlebell_swing", "plank", "side_plank", "dead_bug", "bird_dog",
                        "pallof_press", "russian_twist", "hanging_leg_raise", "pull_up", "lat_pulldown",
                        "row_cable", "row_dumbbell", "bench_press", "push_up", "shoulder_press", "lateral_raise",
                        "face_pull", "biceps_curl", "triceps_pushdown", "back_extension", "good_morning",
                        "farmers_walk", "burpee", "mountain_climber", "climbing"]
        for id in required { #expect(ExerciseCatalog.exercise(id: id) != nil, "fehlt: \(id)") }
    }

    @Test func everyMuscleGroupIsCovered() {
        for g in MuscleGroup.allCases { #expect(!ExerciseCatalog.exercises(for: g).isEmpty, "leer: \(g)") }
    }

    @Test func legInvolvementOfKeyExercises() {
        #expect(ExerciseCatalog.exercise(id: "squat")?.legInvolvement == .heavy)
        #expect(ExerciseCatalog.exercise(id: "deadlift")?.legInvolvement == .heavy)
        #expect(ExerciseCatalog.exercise(id: "calf_raise")?.legInvolvement == .light)
        #expect(ExerciseCatalog.exercise(id: "plank")?.legInvolvement == LegInvolvement.none)
        #expect(ExerciseCatalog.exercise(id: "bench_press")?.legInvolvement == LegInvolvement.none)
    }

    @Test func climbingIsSpecialAndLegLight() {
        let c = ExerciseCatalog.exercise(id: "climbing")
        #expect(c?.isSpecial == true)
        #expect(c?.legInvolvement == .light)
        #expect(c?.name == "Bouldern/Klettern")
    }

    @Test func legShareHeavyWhenOneHeavyChecked() {
        let ex = [PerformedExercise(exerciseID: "plank"), PerformedExercise(exerciseID: "lunge")]
        #expect(ExerciseCatalog.legShare(for: ex) == .heavy)
    }

    @Test func legShareHeavyWithVolumeEvenIfUnchecked() {
        let ex = [PerformedExercise(exerciseID: "squat", sets: 3, reps: 5, weightKg: 80, checked: false)]
        #expect(ExerciseCatalog.legShare(for: ex) == .heavy)
    }

    @Test func legShareIgnoresUncheckedWithoutVolume() {
        let ex = [PerformedExercise(exerciseID: "squat", checked: false), PerformedExercise(exerciseID: "plank")]
        #expect(ExerciseCatalog.legShare(for: ex) == LegInvolvement.none)
    }

    @Test func legShareLightWhenOnlyLightOnes() {
        let ex = [PerformedExercise(exerciseID: "calf_raise"), PerformedExercise(exerciseID: "bench_press")]
        #expect(ExerciseCatalog.legShare(for: ex) == .light)
    }

    @Test func legShareNoneForUpperBodyUnknownAndEmpty() {
        #expect(ExerciseCatalog.legShare(for: []) == LegInvolvement.none)
        #expect(ExerciseCatalog.legShare(for: [PerformedExercise(exerciseID: "does_not_exist")]) == LegInvolvement.none)
        #expect(ExerciseCatalog.legShare(for: [PerformedExercise(exerciseID: "pull_up")]) == LegInvolvement.none)
    }

    @Test func legShareBoulderingIsLight() {
        #expect(ExerciseCatalog.legShare(for: [PerformedExercise(exerciseID: "climbing")]) == .light)
    }

    @Test func legInvolvementOrdering() {
        #expect(LegInvolvement.none < .light && LegInvolvement.light < .heavy)
    }
}
