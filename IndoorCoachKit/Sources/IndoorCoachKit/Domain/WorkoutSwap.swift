import Foundation

/// "Gegen Grundlage tauschen" (docs/17, B29): regelbasiert, gleiche Dauer, Z2 mit Warm-up und Cool-down.
public enum WorkoutSwap {
    /// Z2 is about 60–70 % FTP; the middle is used.
    public static let basePower = 0.65
    static let minTotal = 15 * 60

    /// Easy endurance version of `d` with the same total duration; nil when the workout is too short (< 15 min).
    public static func base(for d: WorkoutDefinition) -> WorkoutDefinition? {
        let total = d.totalDuration
        guard total >= minTotal else { return nil }
        let warm = total >= 30 * 60 ? 600 : 300
        let cool = 300
        let main = total - warm - cool
        let segments = [
            Segment(kind: .warmup, duration: warm, powerLow: 0.45, powerHigh: 0.60),
            Segment(kind: .steady, duration: main, power: basePower, text: "Grundlage, locker (Z2)"),
            Segment(kind: .cooldown, duration: cool, powerLow: 0.40, powerHigh: 0.60),
        ]
        return WorkoutDefinition(title: d.title, type: .endurance,
                                 summary: "Lockere Grundlage statt \(d.type.label): gleiche Dauer, Z2.", segments: segments)
    }
}
