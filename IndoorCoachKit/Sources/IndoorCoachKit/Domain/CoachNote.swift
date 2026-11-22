import Foundation

// Coach-Notiz zum Gipfelmoment (docs/22, B1): ein Satz nach festen Regeln, ohne KI und ohne Verbindung. Er nutzt den
// Langzeitbezug (Vergleich mit dir selbst) und den Kontext aus dem Check-in, nennt immer seine Quelle und wechselt die
// Regel ab. Antwort auf die Kritik an KI-Zusammenfassungen: Kontext, Langzeit, Ton, Quelle.

public struct CoachNote: Equatable, Sendable {
    /// Stabile Regel-ID (`checkin`, `efficiency` …) für die Abwechslung im Ledger.
    public var rule: String
    public var text: String
    /// Woher die Aussage stammt („aus deinen Sekundendaten“); steht klein unter dem Satz.
    public var source: String

    /// Der erste passende Satz nach Rang der Regeln; eine Regel, die in den letzten drei Notizen schon vorkam, wird
    /// übersprungen. nil, wenn nichts passt (dann zeigt die Karte keinen Satz).
    public static func make(_ context: CoachNoteContext, ledger: MomentLedger) -> CoachNote? {
        for rule in Rule.allCases where ledger.canUseNoteRule(rule.rawValue) {
            if let note = rule.note(for: context) { return note }
        }
        return nil
    }

    /// Reihenfolge = Rang. `comeback` begrüßt zuerst, danach die sieben Regeln aus docs/22.
    enum Rule: String, CaseIterable {
        case comeback, checkin, efficiency, warmup, record, streak, fitness, season

        func note(for c: CoachNoteContext) -> CoachNote? {
            let f = CoachNoteFormat(c)
            switch self {
            case .comeback:
                guard let gap = c.comebackGapDays else { return nil }
                return make("Nach \(gap) Tagen wieder auf der Rolle. Das Schwerste war der Anfang, und der ist geschafft.", "aus deinen Fahrten")
            case .checkin:
                guard let answers = c.checkIn else { return nil }
                let reason: String
                if answers.legs == .bad { reason = "schwerer Beine" }
                else if answers.sleep == .bad { reason = "kurzer Nacht" }
                else if answers.mood == .bad { reason = "mieser Laune" }
                else { return nil }
                let how = c.shortened ? "gefahren und klug gekürzt" : "gefahren"
                return make("Trotz \(reason) \(how). So bleibt man durch den Winter dran.", "aus deinem Check-in")
            case .efficiency:
                guard let e = c.efficiency, e.fewerBeats > 0 else { return nil }
                return make("Bei \(e.watts) W schlägt dein Herz \(e.fewerBeats)-mal pro Minute weniger als im \(f.month(e.since)).",
                            "aus deinen Sekundendaten")
            case .warmup:
                guard let w = c.warmup, w.fewerBeats > 0 else { return nil }
                let beats = w.fewerBeats == 1 ? "1 Schlag" : "\(w.fewerBeats) Schläge"
                let weeks = w.weeksAgo == 1 ? "1 Woche" : "\(w.weeksAgo) Wochen"
                return make("Im Aufwärm-Check: \(beats) weniger bei gleichen \(w.watts) W als vor \(weeks).", "aus deinen Sekundendaten")
            case .record:
                guard let r = c.record else { return nil }
                let phrase = CoachNoteFormat.strongest(r.duration)
                let tail = r.betterBefore.map { f.since($0) } ?? "der letzten 90 Tage"
                return make("Deine \(phrase) \(r.betterBefore == nil ? tail : "seit \(tail)").", "aus deinen Sekundendaten")
            case .streak:
                guard let s = c.streak, s.weeks >= 2 else { return nil }
                return make("\(s.weeks) Wochen in Folge dabei, seit dem \(f.dayMonth(s.since)).", "aus Plan und Fahrten")
            case .fitness:
                guard let x = c.fitness, x.to > x.from else { return nil }
                return make("Seit dem \(f.dayMonth(x.since)) ist deine Fitness von \(x.from) auf \(x.to) gestiegen.", "geschätzt aus deiner Trainingsbelastung")
            case .season:
                guard let s = c.season, s.sessions >= 3, s.hours >= 1 else { return nil }
                let units = "\(s.sessions) Einheiten"
                let hours = s.hours == 1 ? "1 Stunde" : "\(s.hours) Stunden"
                let winter = f.isWinter ? ", während draußen Winter ist" : ""
                return make("\(units) seit dem \(f.dayMonth(s.since)), \(hours) auf der Rolle\(winter).", "aus deinen Fahrten")
            }
        }

        private func make(_ text: String, _ source: String) -> CoachNote { CoachNote(rule: rawValue, text: text, source: source) }
    }
}

/// Alles, was die Regeln über den Fahrer wissen müssen. `AppModel+Moments` füllt es aus Fahrten, Check-in und Plan.
public struct CoachNoteContext: Equatable, Sendable {
    public struct Efficiency: Equatable, Sendable {
        public var watts: Int
        public var fewerBeats: Int
        /// Beginn des Vergleichszeitraums (nur der Monat wird genannt).
        public var since: Date
        public init(watts: Int, fewerBeats: Int, since: Date) { self.watts = watts; self.fewerBeats = fewerBeats; self.since = since }
    }

    public struct Warmup: Equatable, Sendable {
        public var watts: Int
        public var fewerBeats: Int
        public var weeksAgo: Int
        public init(watts: Int, fewerBeats: Int, weeksAgo: Int) { self.watts = watts; self.fewerBeats = fewerBeats; self.weeksAgo = weeksAgo }
    }

    public struct Record: Equatable, Sendable {
        public var duration: Int
        /// Wann es zuletzt eine bessere Leistung über diese Dauer gab; nil = nie in den Daten.
        public var betterBefore: Date?
        public init(duration: Int, betterBefore: Date?) { self.duration = duration; self.betterBefore = betterBefore }
    }

    public struct Streak: Equatable, Sendable {
        public var weeks: Int
        public var since: Date
        public init(weeks: Int, since: Date) { self.weeks = weeks; self.since = since }
    }

    public struct Fitness: Equatable, Sendable {
        public var from: Int
        public var to: Int
        public var since: Date
        public init(from: Int, to: Int, since: Date) { self.from = from; self.to = to; self.since = since }
    }

    public struct Season: Equatable, Sendable {
        public var sessions: Int
        public var hours: Int
        public var since: Date
        public init(sessions: Int, hours: Int, since: Date) { self.sessions = sessions; self.hours = hours; self.since = since }
    }

    public var now: Date
    public var calendar: Calendar
    /// Check-in von heute (nil ohne) und ob die Einheit auf Wunsch gekürzt wurde.
    public var checkIn: CheckIn.Answers?
    public var shortened: Bool
    public var comebackGapDays: Int?
    public var efficiency: Efficiency?
    public var warmup: Warmup?
    public var record: Record?
    public var streak: Streak?
    public var fitness: Fitness?
    public var season: Season?

    public init(now: Date, calendar: Calendar = .current, checkIn: CheckIn.Answers? = nil, shortened: Bool = false,
                comebackGapDays: Int? = nil, efficiency: Efficiency? = nil, warmup: Warmup? = nil, record: Record? = nil,
                streak: Streak? = nil, fitness: Fitness? = nil, season: Season? = nil) {
        self.now = now
        self.calendar = calendar
        self.checkIn = checkIn
        self.shortened = shortened
        self.comebackGapDays = comebackGapDays
        self.efficiency = efficiency
        self.warmup = warmup
        self.record = record
        self.streak = streak
        self.fitness = fitness
        self.season = season
    }

    // MARK: Aus Fahrten abgeleitet

    /// Gleiche Watt, weniger Puls: Die Fahrt (mindestens 20 Minuten, mit Puls) gegen den Median der Fahrten aus den ersten
    /// drei Wochen der Saison bei ±5 % derselben Leistung. Erst ab 3 % weniger Puls.
    public static func efficiency(for ride: RideSummary, in rides: [RideSummary], seasonStart: Date, calendar: Calendar) -> Efficiency? {
        guard ride.movingTime >= 20 * 60, let watts = ride.averageWatts, watts > 0, let hr = ride.averageHeartrate, hr > 0 else { return nil }
        let start = calendar.startOfDay(for: seasonStart)
        guard let end = calendar.date(byAdding: .day, value: 21, to: start), ride.startDate >= end else { return nil }
        let early = rides.filter {
            guard $0.id != ride.id, $0.startDate >= start, $0.startDate < end, $0.movingTime >= 20 * 60,
                  let w = $0.averageWatts, let h = $0.averageHeartrate, h > 0 else { return false }
            return abs(w - watts) <= watts * 0.05
        }
        guard let median = AerobicEfficiency.median(early.compactMap(\.averageHeartrate)), (median - hr) / median >= 0.03 else { return nil }
        let first = early.map(\.startDate).min() ?? start
        return Efficiency(watts: Int(watts.rounded()), fewerBeats: Int((median - hr).rounded()), since: first)
    }
}

/// Wortlaute und Datumsformate der Regeln (Deutsch, Kalender des Nutzers).
struct CoachNoteFormat {
    var calendar: Calendar
    var now: Date

    init(_ context: CoachNoteContext) { calendar = context.calendar; now = context.now }

    private func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale.de
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }

    func month(_ date: Date) -> String { format(date, "LLLL") }
    func dayMonth(_ date: Date) -> String { format(date, "d. MMMM") }

    /// „Juli“ ab zwei Monaten Abstand, sonst der genaue Tag („dem 3. Dezember“).
    func since(_ date: Date) -> String {
        ((calendar.dateComponents([.day], from: date, to: now).day ?? 0) >= 60) ? month(date) : "dem \(dayMonth(date))"
    }

    /// Winter heißt hier November bis März.
    var isWinter: Bool { [11, 12, 1, 2, 3].contains(calendar.component(.month, from: now)) }

    /// „stärksten 5 Minuten“, „stärkste Minute“, „stärkste Stunde“.
    static func strongest(_ seconds: Int) -> String {
        switch seconds {
        case 60: return "stärkste Minute"
        case 3600: return "stärkste Stunde"
        case ..<60: return "stärksten \(seconds) Sekunden"
        case ..<3600: return "stärksten \(seconds / 60) Minuten"
        default: return "stärksten \(seconds / 3600) Stunden"
        }
    }
}

/// Anrede mit Namen: höchstens in der Überschrift und nur jedes zweite Mal (docs/22, Tonregeln).
public enum MomentGreeting {
    /// „Stark, Sabine.“ – nur mit gesetztem Namen und abwechselnd (gerade Anzahl gesehener Momente im Ledger).
    public static func make(name: String, ledger: MomentLedger) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ledger.seenIDs.count % 2 == 0 else { return nil }
        return "Stark, \(trimmed)."
    }
}
