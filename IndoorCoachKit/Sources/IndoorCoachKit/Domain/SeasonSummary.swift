import Foundation

/// Saisonrückblick (G5): the few numbers that go onto the shareable season image. Pure; no personal data except
/// the name, and that only when the athlete has set one.
public struct SeasonSummary: Equatable, Sendable {
    public var levelNumber: Int
    public var levelName: String
    public var levelSymbol: String
    public var startCTL: Double
    public var currentCTL: Double
    public var streakWeeks: Int
    public var challengesCompleted: Int
    public var challengesTotal: Int
    /// Best measured or estimated 20-minute power since the season start.
    public var best20MinWatts: Int?
    public var seasonStart: Date
    public var seasonEnd: Date
    /// nil when the profile has no name.
    public var name: String?
    /// Zone of the calendar the season dates come from; the dates are midnights there, so the text must use it too
    /// (on a UTC machine "1. Nov." 00:00 Berlin would otherwise read "31. Okt.").
    public var timeZone: TimeZone = .current
    /// „Dein Herz im Winter Arc“ (B57): je verfügbarer Kennzahl eine Zeile („Ruhepuls 58 → 53“); leer ohne Daten.
    public var heartLines: [String] = []

    public static func make(status: WinterArc.Status, challenges: [Challenges.Challenge], rides: [RideSummary],
                            name: String, now: Date = .now, calendar: Calendar = .current,
                            heartLines: [String] = []) -> SeasonSummary {
        let best = PowerCurve.aggregate(rides: rides, from: status.start, to: now).best(1200)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SeasonSummary(levelNumber: status.level.number, levelName: status.level.name, levelSymbol: status.level.symbol,
                             startCTL: status.startCTL, currentCTL: status.currentCTL, streakWeeks: status.streakWeeks,
                             challengesCompleted: challenges.filter(\.isCompleted).count, challengesTotal: challenges.count,
                             best20MinWatts: best.map { Int($0.watts.rounded()) },
                             seasonStart: status.start, seasonEnd: status.goal, name: trimmed.isEmpty ? nil : trimmed,
                             timeZone: calendar.timeZone, heartLines: heartLines)
    }

    /// "1. Nov. – 21. März"
    public var periodText: String {
        let style = Date.FormatStyle(locale: Locale.de, timeZone: timeZone).day().month(.abbreviated)
        return "\(seasonStart.formatted(style)) – \(seasonEnd.formatted(style))"
    }

    /// "Fitness 24 → 34"
    public var fitnessText: String { "\(Formatters.decimal(startCTL)) → \(Formatters.decimal(currentCTL))" }

    public var streakText: String { "\(streakWeeks) \(streakWeeks == 1 ? "Woche" : "Wochen")" }

    public var challengesText: String { "\(challengesCompleted) von \(challengesTotal)" }

    public var best20MinText: String { best20MinWatts.map { "\($0) W" } ?? "–" }

    /// VoiceOver / share caption.
    public var caption: String {
        "Mein Winter Arc: Level \(levelNumber) \(levelName), Fitness \(fitnessText), Serie \(streakText), "
            + "\(challengesCompleted) Challenges geschafft."
    }
}
