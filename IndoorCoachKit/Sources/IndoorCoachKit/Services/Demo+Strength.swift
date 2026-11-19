import Foundation

extension AppModel {
    /// Drei Demo-Krafteinheiten relativ zu `now`: Beine, Oberkörper, Rumpf (nur im Demo-Modus aus `bootstrap`).
    static func demoStrengthSessions(now: Date = .now, calendar: Calendar = .current) -> [StrengthSession] {
        func at(daysAgo: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        }
        return [
            StrengthSession(start: at(daysAgo: 2, hour: 18), durationSeconds: 55 * 60, source: .manual, exertion: 7,
                            exercises: [PerformedExercise(exerciseID: "squat", sets: 4, reps: 6, weightKg: 80),
                                        PerformedExercise(exerciseID: "romanian_deadlift", sets: 3, reps: 8, weightKg: 70),
                                        PerformedExercise(exerciseID: "calf_raise", sets: 3, reps: 15)],
                            templateName: "Beine"),
            StrengthSession(start: at(daysAgo: 5, hour: 18), durationSeconds: 45 * 60, source: .manual, exertion: 5,
                            exercises: [PerformedExercise(exerciseID: "bench_press", sets: 3, reps: 8, weightKg: 60),
                                        PerformedExercise(exerciseID: "pull_up", sets: 3, reps: 6),
                                        PerformedExercise(exerciseID: "dips", sets: 3, reps: 8)],
                            templateName: "Oberkörper"),
            StrengthSession(start: at(daysAgo: 9, hour: 7), durationSeconds: 25 * 60, source: .manual, exertion: 3,
                            exercises: [PerformedExercise(exerciseID: "plank"), PerformedExercise(exerciseID: "dead_bug")],
                            templateName: "Rumpf"),
        ]
    }

    func seedDemoStrength() {
        for s in Self.demoStrengthSessions() { context.insert(StoredStrengthSession(session: s, isDemo: true)) }
    }
}
