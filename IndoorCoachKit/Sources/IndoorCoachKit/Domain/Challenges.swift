import Foundation

/// Season challenges (K3): static goals per winter, computed purely from the rides (indoor only, no persistence).
///
/// The season year follows `WinterArc.defaultSeason`: Aug–Dec belong to the coming winter, Jan–Jul to the one
/// that started the year before. A window runs from the start of its first day up to the end of its last day.
public enum Challenges {
    public enum Kind: String, Sendable {
        case indoor500, kalterJanuar, februarFundament, monatsKonstanz
    }

    public enum Unit: String, Sendable {
        case minutes, sessions
    }

    public enum State: Equatable, Sendable {
        /// Starts in `daysUntilStart` days (≥ 1).
        case upcoming(daysUntilStart: Int)
        /// Running. `daysLeft` counts today, so it is 1 on the last day.
        case active(daysLeft: Int)
        case completed(on: Date)
        case missed
    }

    public struct Challenge: Identifiable, Equatable, Sendable {
        public var id: String
        public var kind: Kind
        public var title: String
        /// One-line rule, e.g. "12 Indoor-Einheiten im Januar".
        public var rule: String
        public var symbol: String
        /// First day (start of day).
        public var start: Date
        /// Day after the last day (start of day, exclusive).
        public var end: Date
        public var goal: Double
        public var unit: Unit
        public var progress: Double
        public var state: State
        /// The ride that pushed the progress over the goal.
        public var completedByRideID: Int?

        /// 0…1.
        public var fraction: Double { goal > 0 ? min(1, progress / goal) : 0 }
        public var remaining: Double { max(0, goal - progress) }
        public var isCompleted: Bool { if case .completed = state { true } else { false } }
        public var isActive: Bool { if case .active = state { true } else { false } }
        public var isUpcoming: Bool { if case .upcoming = state { true } else { false } }

        /// "180 von 500 Minuten" / "5 von 8 Einheiten" / "3,5 von 10 h".
        public var progressText: String {
            "\(Challenges.format(progress, unit: unit, goal: goal)) von \(Challenges.format(goal, unit: unit, goal: goal, withUnit: true))"
        }
        /// "noch 320 Minuten" / "noch 3 Einheiten".
        public var remainingText: String { "noch \(Challenges.format(remaining, unit: unit, goal: goal, withUnit: true))" }
    }

    /// Februar-Fundament counts endurance rides below this intensity factor.
    public static let enduranceIFLimit = 0.75

    static func format(_ value: Double, unit: Unit, goal: Double, withUnit: Bool = false) -> String {
        switch unit {
        case .sessions:
            let n = Int(value.rounded(.up))
            return withUnit ? "\(n) \(n == 1 ? "Einheit" : "Einheiten")" : "\(n)"
        case .minutes:
            if goal >= 600 { // long goals are shown in hours
                let h = (value / 6).rounded() / 10
                let s = h == h.rounded() ? "\(Int(h))" : String(format: "%.1f", h).replacingOccurrences(of: ".", with: ",")
                return withUnit ? "\(s) h" : s
            }
            let m = Int(value.rounded(.up))
            return withUnit ? "\(m) Minuten" : "\(m)"
        }
    }

    /// The winter (start year of its November) that contains `date`.
    public static func seasonStartYear(containing date: Date, calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: date)
        return calendar.component(.month, from: date) >= 8 ? year : year - 1
    }

    private static let monthNames = [11: "November", 12: "Dezember", 1: "Januar", 2: "Februar", 3: "März"]

    /// All challenges of the winter containing `now`, ordered by start (then by end).
    public static func season(rides: [RideSummary], ftp: Int, now: Date = .now, calendar: Calendar = .current) -> [Challenge] {
        let y = seasonStartYear(containing: now, calendar: calendar)
        let indoor = rides.filter(\.isIndoor).sorted { $0.startDate < $1.startDate }
        let today = calendar.startOfDay(for: now)

        func day(_ year: Int, _ month: Int, _ d: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: d))!
        }
        func make(id: String, kind: Kind, title: String, rule: String, symbol: String, start: Date, end: Date,
                  goal: Double, unit: Unit, value: (RideSummary) -> Double?) -> Challenge {
            var total = 0.0
            var doneOn: Date?
            var doneBy: Int?
            for ride in indoor where ride.startDate >= start && ride.startDate < end {
                guard let v = value(ride), v > 0 else { continue }
                total += v
                if doneOn == nil, total >= goal { doneOn = ride.startDate; doneBy = ride.id }
            }
            let state: State
            if let doneOn {
                state = .completed(on: doneOn)
            } else if today >= end {
                state = .missed
            } else if today < start {
                state = .upcoming(daysUntilStart: calendar.dateComponents([.day], from: today, to: start).day ?? 0)
            } else {
                state = .active(daysLeft: calendar.dateComponents([.day], from: today, to: end).day ?? 1)
            }
            return Challenge(id: id, kind: kind, title: title, rule: rule, symbol: symbol, start: start, end: end,
                             goal: goal, unit: unit, progress: total, state: state, completedByRideID: doneBy)
        }
        let minutes: (RideSummary) -> Double? = { Double($0.movingTime) / 60 }
        let session: (RideSummary) -> Double? = { _ in 1 }
        let endurance: (RideSummary) -> Double? = { ride in
            guard ftp > 0, let np = ride.weightedAverageWatts ?? ride.averageWatts.map({ $0 * 1.05 }), np > 0,
                  np / Double(ftp) < enduranceIFLimit else { return nil }
            return Double(ride.movingTime) / 60
        }

        var result: [Challenge] = []
        for (month, year) in [(11, y), (12, y), (1, y + 1), (2, y + 1), (3, y + 1)] {
            let start = day(year, month, 1)
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            let name = monthNames[month]!
            result.append(make(id: "konstanz-\(year)-\(month)", kind: .monatsKonstanz, title: "Monats-Konstanz \(name)",
                               rule: "8 Indoor-Einheiten im \(name)", symbol: "calendar.badge.checkmark",
                               start: start, end: end, goal: 8, unit: .sessions, value: session))
        }
        result.append(make(id: "indoor500-\(y)", kind: .indoor500, title: "Indoor-500",
                           rule: "500 Indoor-Minuten vom 24. bis 31. Dezember", symbol: "gift",
                           start: day(y, 12, 24), end: day(y + 1, 1, 1), goal: 500, unit: .minutes, value: minutes))
        result.append(make(id: "kalter-januar-\(y + 1)", kind: .kalterJanuar, title: "Kalter Januar",
                           rule: "12 Indoor-Einheiten im Januar", symbol: "thermometer.snowflake",
                           start: day(y + 1, 1, 1), end: day(y + 1, 2, 1), goal: 12, unit: .sessions, value: session))
        result.append(make(id: "februar-fundament-\(y + 1)", kind: .februarFundament, title: "Februar-Fundament",
                           rule: "10 Stunden Grundlage im Februar (unter 0,75 IF, nur Fahrten mit Leistung)",
                           symbol: "square.stack.3d.up", start: day(y + 1, 2, 1), end: day(y + 1, 3, 1),
                           goal: 600, unit: .minutes, value: endurance))
        return result.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// The one challenge worth a card on Heute: a running one (soonest ending, then furthest along), otherwise one
    /// starting within `days` days.
    public static func highlight(in challenges: [Challenge], within days: Int = 7) -> Challenge? {
        let active = challenges.filter(\.isActive).sorted { ($0.end, -$0.fraction) < ($1.end, -$1.fraction) }
        if let first = active.first { return first }
        return challenges.compactMap { c -> (Challenge, Int)? in
            if case .upcoming(let d) = c.state, d <= days { return (c, d) }
            return nil
        }.min { $0.1 < $1.1 }?.0
    }

    /// Challenges this very ride completed.
    public static func completed(by ride: RideSummary, in challenges: [Challenge]) -> [Challenge] {
        challenges.filter { $0.completedByRideID == ride.id }
    }

    /// Spoken summary for VoiceOver.
    public static func summary(_ c: Challenge) -> String {
        switch c.state {
        case .upcoming(let d): "\(c.title), \(c.rule). Startet in \(d) \(d == 1 ? "Tag" : "Tagen")."
        case .active(let d): "\(c.title), \(c.progressText), \(c.remainingText), noch \(d) \(d == 1 ? "Tag" : "Tage")."
        case .completed(let date): "\(c.title), geschafft am \(date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "de_DE"))))."
        case .missed: "\(c.title), diesmal nicht geschafft, \(c.progressText)."
        }
    }
}
