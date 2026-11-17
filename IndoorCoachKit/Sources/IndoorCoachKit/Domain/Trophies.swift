import Foundation

/// Trophies (K3): computed on the fly from rides, challenges and the Winter Arc – nothing is stored.
/// Every trophy has a condition text; earned ones also carry the date they were earned.
public struct Trophy: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case challenge, level, streak, record, secondData }

    public var id: String
    public var kind: Kind
    public var title: String
    /// What it takes ("12 Indoor-Einheiten im Januar") – shown for locked trophies.
    public var condition: String
    /// Extra line for earned ones ("312 W · Sweet Spot 2×20"), optional.
    public var detail: String?
    public var symbol: String
    /// nil = not earned yet.
    public var earnedOn: Date?

    public var isEarned: Bool { earnedOn != nil }

    /// Spoken summary for VoiceOver.
    public var summary: String {
        if let earnedOn {
            let date = earnedOn.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_DE")))
            return "\(title), erreicht am \(date)\(detail.map { ". \($0)" } ?? "")"
        }
        return "\(title), noch nicht erreicht. \(condition)"
    }
}

public enum Trophies {
    public static let streakMilestones = [4, 8, 12]

    /// Day each Winter Arc level was first reached: level 1 on the season start, level n on the first day the best
    /// fitness since the start covers (n−1)/10 of the way to the target (same rule as `WinterArc.status`).
    public static func levelDates(status: WinterArc.Status, points: [FitnessFreshness.Point],
                                  calendar: Calendar = .current) -> [Int: Date] {
        var result: [Int: Date] = [1: status.start]
        let span = status.targetCTL - status.startCTL
        guard span > 0 else { return result }
        var best = status.startCTL
        for p in points.sorted(by: { $0.date < $1.date }) where calendar.startOfDay(for: p.date) >= status.start {
            best = max(best, p.fitness)
            let raw = min(1, max(0, (best - status.startCTL) / span)) * Double(WinterArc.levels.count)
            let index = min(WinterArc.levels.count - 1, Int(raw))
            if index >= 1 {
                for n in 2...(index + 1) where result[n] == nil { result[n] = calendar.startOfDay(for: p.date) }
            }
        }
        return result
    }

    /// Last day of the `n`-th week of a streak of `streak` weeks that ended with the last completed ISO week.
    /// An estimate (the streak itself is only known as a count), capped at `now`.
    static func streakDate(milestone n: Int, streak: Int, now: Date, calendar baseCalendar: Calendar) -> Date {
        var calendar = baseCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let weeksBack = max(0, streak - n)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: weekStart)!
        let date = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: lastDay) ?? lastDay
        return min(date, calendar.startOfDay(for: now))
    }

    static func durationText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600) h"
    }

    /// Every trophy, earned ones first (newest first), then locked ones in their natural order.
    public static func all(rides: [RideSummary], ftp: Int, arc: WinterArc.Status?, fitness: [FitnessFreshness.Point],
                           now: Date = .now, calendar: Calendar = .current) -> [Trophy] {
        var list: [Trophy] = []

        // Challenges
        for c in Challenges.season(rides: rides, ftp: ftp, now: now, calendar: calendar) {
            var date: Date?
            if case .completed(let on) = c.state { date = on }
            list.append(Trophy(id: "challenge-\(c.id)", kind: .challenge, title: c.title, condition: c.rule, detail: nil,
                               symbol: c.symbol, earnedOn: date))
        }

        // Winter Arc levels and streak
        if let arc {
            let dates = levelDates(status: arc, points: fitness, calendar: calendar)
            for level in WinterArc.levels {
                let reached = level.number <= arc.level.number
                list.append(Trophy(id: "level-\(level.number)", kind: .level, title: "Level \(level.number) · \(level.name)",
                                   condition: level.number == 1 ? "Starte deinen Winter Arc"
                                       : "\(level.number * 10 - 10) % des Wegs zur Ziel-Fitness",
                                   detail: nil, symbol: level.symbol,
                                   earnedOn: reached ? (dates[level.number] ?? arc.start) : nil))
            }
            for n in streakMilestones {
                let reached = arc.streakWeeks >= n
                list.append(Trophy(id: "streak-\(n)", kind: .streak, title: "\(n) Wochen in Folge",
                                   condition: "\(n) Wochen in Folge dein Wochenziel halten", detail: nil, symbol: "flame",
                                   earnedOn: reached ? streakDate(milestone: n, streak: arc.streakWeeks, now: now, calendar: calendar) : nil))
            }
        }

        // Best efforts: per headline duration the latest ride that set a 90-day best at the time.
        let measured = rides.filter { $0.powerCurve != nil }.sorted { $0.startDate < $1.startDate }
        var latest: [Int: (ride: RideSummary, watts: Double)] = [:]
        for ride in measured {
            for p in PowerCurve.records(for: ride, among: rides, now: ride.startDate) { latest[p.duration] = (ride, p.watts) }
        }
        for d in PowerCurve.headlineDurations {
            let text = durationText(d)
            if let hit = latest[d] {
                list.append(Trophy(id: "record-\(d)", kind: .record, title: "Bestleistung \(text)",
                                   condition: "Neue Bestleistung über \(text)", detail: "\(Int(hit.watts.rounded())) W · \(hit.ride.name)",
                                   symbol: "trophy", earnedOn: hit.ride.startDate))
            } else {
                list.append(Trophy(id: "record-\(d)", kind: .record, title: "Bestleistung \(text)",
                                   condition: "Fahre über \(text) deine beste Leistung der letzten 90 Tage (mit Sekundendaten)",
                                   detail: nil, symbol: "trophy", earnedOn: nil))
            }
        }

        // First ride with 1 Hz data
        if let first = measured.first {
            list.append(Trophy(id: "second-data", kind: .secondData, title: "Sekundengenau", condition: "Fahrt mit Sekundendaten",
                               detail: first.name, symbol: "waveform.path.ecg", earnedOn: first.startDate))
        } else {
            list.append(Trophy(id: "second-data", kind: .secondData, title: "Sekundengenau",
                               condition: "Importiere eine FIT-Datei mit Sekundendaten", detail: nil,
                               symbol: "waveform.path.ecg", earnedOn: nil))
        }

        let earned = list.filter(\.isEarned).sorted { ($0.earnedOn ?? .distantPast) > ($1.earnedOn ?? .distantPast) }
        return earned + list.filter { !$0.isEarned }
    }
}
