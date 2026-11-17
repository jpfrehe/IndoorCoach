import Foundation

/// G4 "Alpenüberquerung": the Winter Arc's ten levels as ten stages of a stylised route from Garmisch to the
/// Gardasee. Purely presentational – the position is derived from the level and `levelProgress`.
public enum WinterJourney {
    public struct Stage: Equatable, Sendable {
        public var number: Int
        public var place: String
        /// Height of the stage's destination in metres – only used to draw the profile.
        public var elevation: Int
    }

    public static let title = "Alpenüberquerung"

    public static let stages: [Stage] = [
        Stage(number: 1, place: "Garmisch", elevation: 708),
        Stage(number: 2, place: "Fernpass", elevation: 1216),
        Stage(number: 3, place: "Reschen", elevation: 1507),
        Stage(number: 4, place: "Stilfser Joch", elevation: 2757),
        Stage(number: 5, place: "Bormio", elevation: 1225),
        Stage(number: 6, place: "Aprica", elevation: 1176),
        Stage(number: 7, place: "Edolo", elevation: 699),
        Stage(number: 8, place: "Crocedomini", elevation: 1892),
        Stage(number: 9, place: "Idrosee", elevation: 368),
        Stage(number: 10, place: "Gardasee", elevation: 65),
    ]

    public struct Position: Equatable, Sendable {
        public var stage: Stage
        /// 0…1 inside the current stage.
        public var progress: Double
        public var count: Int

        public var percent: Int { Int((progress * 100).rounded()) }
        public var next: Stage? { stage.number < count ? WinterJourney.stages[stage.number] : nil }
        /// 0…1 along the whole route; stage 1 is the start, stage 10 the finish, so 9 legs in between.
        public var routeFraction: Double {
            min(1, (Double(stage.number - 1) + progress) / Double(count - 1))
        }
        public var accessibilityLabel: String {
            "Etappe \(stage.number) von \(count): \(stage.place), \(percent) % geschafft"
        }
    }

    public static func position(level: Int, levelProgress: Double) -> Position {
        let n = min(stages.count, max(1, level))
        return Position(stage: stages[n - 1], progress: min(1, max(0, levelProgress)), count: stages.count)
    }
}
