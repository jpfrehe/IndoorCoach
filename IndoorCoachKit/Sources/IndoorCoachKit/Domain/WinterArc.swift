import Foundation

/// The personal "Winter Arc" (ADR-13): from the season start (default 1 Nov) to the spring goal (default 21 Mar).
///
/// Progress is measured as fitness (CTL) gained towards a target. Ten levels; the shown level is the best one
/// reached since the start, so a sick week never takes a level away. A linear pace line tells whether the
/// athlete is ahead of, on, or behind course; a streak counts weeks with ≥ 80 % of the weekly time budget.
public enum WinterArc {
    public struct Level: Equatable, Sendable {
        public var number: Int
        public var name: String
        public var symbol: String
    }

    public static let levels: [Level] = [
        Level(number: 1, name: "Erster Frost", symbol: "snowflake"),
        Level(number: 2, name: "Raureif", symbol: "cloud.snow"),
        Level(number: 3, name: "Glühwein-Kilometer", symbol: "cup.and.saucer"),
        Level(number: 4, name: "Rollen-Routine", symbol: "figure.indoor.cycle"),
        Level(number: 5, name: "Wintersonnenwende", symbol: "sun.min"),
        Level(number: 6, name: "Eisbrecher", symbol: "mountain.2"),
        Level(number: 7, name: "Tauwetter", symbol: "drop"),
        Level(number: 8, name: "Erste Knospen", symbol: "leaf"),
        Level(number: 9, name: "Frühlingsbote", symbol: "bird"),
        Level(number: 10, name: "Frühlingsform", symbol: "sun.max"),
    ]

    public enum Pace: String, Sendable {
        case ahead, onTrack, behind

        public var label: String {
            switch self {
            case .ahead: "Vor dem Kurs"
            case .onTrack: "Auf Kurs"
            case .behind: "Hinter dem Kurs"
            }
        }
    }

    public struct Status: Sendable {
        public var start: Date
        public var goal: Date
        public var daysTotal: Int
        public var daysLeft: Int
        /// 0…1 of the season's time.
        public var seasonFraction: Double
        public var startCTL: Double
        public var targetCTL: Double
        public var currentCTL: Double
        /// Where the linear pace line is today.
        public var paceCTL: Double
        public var pace: Pace
        /// 0…1 of the CTL way, based on the best CTL since the start.
        public var progress: Double
        public var level: Level
        /// 0…1 towards the next level (1 at the last level).
        public var levelProgress: Double
        public var streakWeeks: Int

        public var isFinished: Bool { daysLeft == 0 }
    }

    /// Ambitious but reachable: +35 %, at least +15 CTL.
    public static func defaultTarget(startCTL: Double) -> Double {
        (max(startCTL + 15, startCTL * 1.35)).rounded()
    }

    /// 1 Nov → 21 Mar of the season that contains `date` (Aug–Dec belongs to the coming winter).
    public static func defaultSeason(containing date: Date, calendar: Calendar = .current) -> (start: Date, goal: Date) {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let startYear = month >= 8 ? year : year - 1
        let start = calendar.date(from: DateComponents(year: startYear, month: 11, day: 1))!
        let goal = calendar.date(from: DateComponents(year: startYear + 1, month: 3, day: 21))!
        return (start, goal)
    }

    public static func status(start: Date, goal: Date, today: Date, startCTL: Double, currentCTL: Double,
                              bestCTLSinceStart: Double, targetCTL: Double?, weeklyHours: [Double],
                              weeklyBudgetHours: Double, calendar: Calendar = .current) -> Status {
        let s = calendar.startOfDay(for: start), g = calendar.startOfDay(for: goal), t = calendar.startOfDay(for: today)
        let total = max(1, calendar.dateComponents([.day], from: s, to: g).day ?? 1)
        let elapsed = min(total, max(0, calendar.dateComponents([.day], from: s, to: t).day ?? 0))
        let target = max(startCTL + 1, targetCTL ?? defaultTarget(startCTL: startCTL))
        let fraction = Double(elapsed) / Double(total)
        let paceCTL = startCTL + (target - startCTL) * fraction
        let pace: Pace = currentCTL > paceCTL + 3 ? .ahead : (currentCTL < paceCTL - 3 ? .behind : .onTrack)
        let progress = min(1, max(0, (max(bestCTLSinceStart, currentCTL) - startCTL) / (target - startCTL)))
        let raw = progress * Double(levels.count)
        let index = min(levels.count - 1, Int(raw))
        let levelProgress = index == levels.count - 1 ? 1 : raw - Double(index)
        let threshold = weeklyBudgetHours * 0.8
        var streak = 0
        for hours in weeklyHours.reversed() {
            guard hours >= threshold, threshold > 0 else { break }
            streak += 1
        }
        return Status(start: s, goal: g, daysTotal: total, daysLeft: total - elapsed, seasonFraction: fraction,
                      startCTL: startCTL, targetCTL: target, currentCTL: currentCTL, paceCTL: paceCTL, pace: pace,
                      progress: progress, level: levels[index], levelProgress: levelProgress, streakWeeks: streak)
    }
}
