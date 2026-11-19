import Foundation

/// Check-in vor der Einheit (docs/17, §9.3): drei Fragen × drei Stufen plus Kontext-Chips. Pure Regeln, keine Diagnose.
/// Daten ändern den Plan nie automatisch – es gibt nur Angebote, der Fahrer entscheidet.
public enum CheckIn {
    public enum Question: String, CaseIterable, Sendable, Identifiable {
        case legs, sleep, mood
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .legs: "Beine"
            case .sleep: "Schlaf"
            case .mood: "Laune"
            }
        }
    }

    /// Three levels for every question; `bad` counts as negative.
    public enum Level: String, CaseIterable, Codable, Sendable, Identifiable {
        case good, ok, bad
        public var id: String { rawValue }

        public func label(for question: Question) -> String {
            switch (question, self) {
            case (.legs, .good): "frisch"
            case (.legs, .ok): "normal"
            case (.legs, .bad): "schwer"
            case (.sleep, .good): "gut"
            case (.sleep, .ok): "okay"
            case (.sleep, .bad): "schlecht"
            case (.mood, .good): "gut"
            case (.mood, .ok): "okay"
            case (.mood, .bad): "mies"
            }
        }
    }

    public enum Tag: String, CaseIterable, Codable, Sendable, Identifiable {
        case infekt, heiss, koffein, stress
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .infekt: "Infekt"
            case .heiss: "Heiß"
            case .koffein: "Koffein"
            case .stress: "Stress"
            }
        }
    }

    public struct Answers: Equatable, Sendable {
        public var legs: Level
        public var sleep: Level
        public var mood: Level
        public var tags: Set<Tag>

        public init(legs: Level = .ok, sleep: Level = .ok, mood: Level = .ok, tags: Set<Tag> = []) {
            self.legs = legs; self.sleep = sleep; self.mood = mood; self.tags = tags
        }

        public subscript(question: Question) -> Level {
            get { switch question { case .legs: legs; case .sleep: sleep; case .mood: mood } }
            set { switch question { case .legs: legs = newValue; case .sleep: sleep = newValue; case .mood: mood = newValue } }
        }

        public var negativeCount: Int { [legs, sleep, mood].filter { $0 == .bad }.count }
        public var hasInfection: Bool { tags.contains(.infekt) }
        /// Offers appear from two negative answers or with the tag "Infekt".
        public var offerNeeded: Bool { negativeCount >= 2 || hasInfection }
    }

    /// What the athlete can choose after a negative check-in. Stored as `raw` in `StoredCheckIn`.
    public enum Action: Equatable, Sendable {
        case shorten(minutes: Int, easierBy: Int)
        case easier(percent: Int)
        case swapToBase
        case joker

        public var raw: String {
            switch self {
            case .shorten(let m, let e): "shorten:\(m):\(e)"
            case .easier(let p): "easier:\(p)"
            case .swapToBase: "swap"
            case .joker: "joker"
            }
        }

        public init?(raw: String) {
            let p = raw.split(separator: ":").map(String.init)
            switch (p.first, p.count) {
            case ("shorten", 3): guard let m = Int(p[1]), let e = Int(p[2]) else { return nil }; self = .shorten(minutes: m, easierBy: e)
            case ("easier", 2): guard let v = Int(p[1]) else { return nil }; self = .easier(percent: v)
            case ("swap", 1): self = .swapToBase
            case ("joker", 1): self = .joker
            default: return nil
            }
        }
    }

    /// At most one check-in per day, only with a planned workout today (no planned workout = Ruhetag).
    public static func isDue(hasPlannedWorkoutToday: Bool, alreadyAnswered: Bool) -> Bool {
        hasPlannedWorkoutToday && !alreadyAnswered
    }

    /// Offers for the answers. With "Infekt" no training is offered at all (only the joker); otherwise
    /// shorter/easier, swap against base and the joker when one is left.
    public static func offers(for a: Answers, plannedMinutes: Int, jokersAvailable: Int, canSwap: Bool = true) -> [Action] {
        guard a.offerNeeded else { return [] }
        let joker: [Action] = jokersAvailable > 0 ? [.joker] : []
        if a.hasInfection { return joker }
        var result: [Action] = []
        let options = WorkoutAdjust.shortenOptions(for: minutesDefinition(plannedMinutes))
        if let target = options.contains(45) ? 45 : options.last {
            result.append(.shorten(minutes: target, easierBy: 5))
        } else {
            result.append(.easier(percent: 10))
        }
        if canSwap { result.append(.swapToBase) }
        return result + joker
    }

    /// General hint, no diagnosis.
    public static func healthHint(for a: Answers) -> String? {
        a.hasInfection ? "Bei Fieber nicht trainieren. Gute Besserung." : nil
    }

    private static func minutesDefinition(_ minutes: Int) -> WorkoutDefinition {
        WorkoutDefinition(title: "", type: .mixed, summary: "", segments: [.steady(Double(minutes), at: 0.6)])
    }
}
