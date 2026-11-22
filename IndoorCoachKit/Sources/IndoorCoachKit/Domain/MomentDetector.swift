import Foundation

// Gipfelmomente (docs/22, B1): die pure Erkennung. Nichts hier liest Speicher, Uhr oder Oberfläche – alles kommt als
// Wert herein, damit jede Regel einzeln getestet werden kann.

/// Alles, was die Erkennung über den Stand der Saison wissen muss. `AppModel+Moments` baut das aus Fahrten, Trophäen,
/// Challenges und der Wochen-Serie.
public struct MomentInput: Sendable {
    /// Plan-Erfüllung einer Woche (Wochenstart = Montag, vom Aufrufer gebildet).
    public struct WeekPlan: Equatable, Sendable {
        public var start: Date
        public var planned: Int
        public var done: Int

        public init(start: Date, planned: Int, done: Int) {
            self.start = start
            self.planned = planned
            self.done = done
        }
    }

    /// Saison-Schlüssel der IDs, z. B. „2026“ (Startjahr des Winters).
    public var season: String
    public var seasonStart: Date
    public var rides: [RideSummary]
    /// `Trophies.all`: Level, Serie, Kraft-Winter und „Sekundengenau“ samt Datum.
    public var trophies: [Trophy]
    public var challenges: [Challenges.Challenge]
    public var weeks: [WeekPlan]
    public var calendar: Calendar

    public init(season: String, seasonStart: Date, rides: [RideSummary], trophies: [Trophy], challenges: [Challenges.Challenge],
                weeks: [WeekPlan], calendar: Calendar = .current) {
        self.season = season
        self.seasonStart = seasonStart
        self.rides = rides
        self.trophies = trophies
        self.challenges = challenges
        self.weeks = weeks
        self.calendar = calendar
    }
}

public enum MomentDetector {
    /// Nur Ereignisse der letzten 72 Stunden kommen in Frage.
    public static let freshness: TimeInterval = 72 * 3600
    /// Lücke in Tagen, ab der die nächste Aktivität ein Comeback ist.
    public static let comebackGapDays = 10
    /// eFTP muss mindestens so viel über dem zuletzt gefeierten Wert liegen.
    public static let ftpRiseShare = 1.02

    /// Ergebnis einer Auswertung: der zu feiernde Stapel und das fortgeschriebene Ledger (still markierte IDs,
    /// Erstauswertung, eFTP-Basis). Die gefeierten Momente selbst trägt erst `acknowledged` ein.
    public struct Evaluation: Equatable, Sendable {
        public var batch: MomentBatch
        public var ledger: MomentLedger
    }

    public static func detect(_ input: MomentInput, ledger: MomentLedger, now: Date) -> MomentBatch {
        evaluate(input, ledger: ledger, now: now).batch
    }

    // MARK: Auswertung

    public static func evaluate(_ input: MomentInput, ledger start: MomentLedger, now: Date) -> Evaluation {
        var ledger = start
        let since = now.addingTimeInterval(-freshness)
        let isFresh: (Date) -> Bool = { $0 >= since && $0 <= now.addingTimeInterval(86_400) }
        let ftp = ftpStep(input, ledger: ledger, now: now, since: since, isFresh: isFresh)
        if let baseline = ftp.baseline { ledger.lastCelebratedFTP = baseline }

        // Erstauswertung (Neuinstallation, erster Import mit Historie): alles Verdiente still als gesehen, nur der eine
        // wichtigste frische Moment wird gefeiert. Ohne Fahrten bleibt das Ledger uninitialisiert.
        if !ledger.isInitialized, !input.rides.isEmpty {
            let built = build(input, includes: { _ in true }, recordRide: { isFresh($0.startDate) })
            let everything = built.moments + (ftp.moment.map { [$0] } ?? [])
            let top = MomentBatch(everything.filter { isFresh($0.date) }).moments.first
            ledger.markSeen(everything.map(\.id).filter { $0 != top?.id } + built.silent)
            if let moment = ftp.moment, moment.id != top?.id { ledger.lastCelebratedFTP = ftpWatts(of: moment) }
            ledger.isInitialized = true
            return Evaluation(batch: top.map { MomentBatch([$0]) } ?? .empty, ledger: ledger)
        }

        let built = build(input, includes: isFresh, recordRide: { isFresh($0.startDate) })
        let candidates = (built.moments + (ftp.moment.map { [$0] } ?? [])).filter { !ledger.hasSeen($0.id) }
        ledger.markSeen(built.silent)
        let batch = MomentBatch(candidates)
        ledger.markSeen(batch.overflow.map(\.id))
        if let overflown = batch.overflow.first(where: { $0.kind == .ftpRise }) { ledger.lastCelebratedFTP = ftpWatts(of: overflown) }
        return Evaluation(batch: batch, ledger: ledger)
    }

    /// Trägt einen gefeierten (oder weggeklickten) Stapel ins Ledger ein: IDs gesehen, eFTP-Basis nachgezogen und die
    /// verwendete Regel der Coach-Notiz für die Abwechslung vermerkt.
    public static func acknowledged(_ batch: MomentBatch, in ledger: MomentLedger, noteRule: String?) -> MomentLedger {
        var ledger = ledger
        ledger.markSeen(batch.allIDs)
        if let ftp = (batch.moments + batch.overflow).first(where: { $0.kind == .ftpRise }) { ledger.lastCelebratedFTP = ftpWatts(of: ftp) }
        if let noteRule { ledger.recordNoteRule(noteRule) }
        return ledger
    }

    /// Die Momente, die zu einer Fahrt gehören – ohne Frische und ohne Ledger (für „Gipfelmoment dieser Fahrt ansehen“).
    public static func moments(forRide rideID: Int, input: MomentInput, now: Date) -> [Moment] {
        let built = build(input, includes: { _ in true }, recordRide: { $0.id == rideID })
        return MomentBatch(built.moments.filter { $0.rideID == rideID }).moments
    }

    // MARK: eFTP

    /// 95 % der besten gemessenen 20 Minuten der letzten 28 Tage bis `date` (wie `FTPHistory`).
    static func eftp(rides: [RideSummary], at date: Date) -> (watts: Int, ride: RideSummary)? {
        let from = date.addingTimeInterval(-Double(FTPHistory.windowDays) * 86_400)
        let best = rides.filter { $0.startDate > from && $0.startDate <= date && ($0.powerCurve?[1200] ?? 0) > 0 }
            .max { ($0.powerCurve?[1200] ?? 0) < ($1.powerCurve?[1200] ?? 0) }
        guard let best, let watts = best.powerCurve?[1200] else { return nil }
        return (Int((watts * 0.95).rounded()), best)
    }

    private static func ftpWatts(of moment: Moment) -> Int? {
        let parts = moment.id.split(separator: "-")
        return parts.count >= 2 ? Int(parts[1]) : nil
    }

    private static func ftpStep(_ input: MomentInput, ledger: MomentLedger, now: Date, since: Date,
                                isFresh: (Date) -> Bool) -> (moment: Moment?, baseline: Int?) {
        guard let current = eftp(rides: input.rides, at: now) else { return (nil, nil) }
        let base = ledger.lastCelebratedFTP ?? eftp(rides: input.rides, at: since)?.watts ?? current.watts
        guard Double(current.watts) >= Double(base) * ftpRiseShare else { return (nil, ledger.lastCelebratedFTP == nil ? base : nil) }
        guard isFresh(current.ride.startDate) else { return (nil, current.watts) } // alter Sprung: nur die Basis anheben
        let moment = Moment(id: Moment.Key.ftp(current.watts, season: input.season), kind: .ftpRise, date: current.ride.startDate,
                            headline: "Deine Schwelle ist gestiegen: \(base) → \(current.watts) W",
                            detail: "geschätzt aus deiner besten 20-Minuten-Leistung, ohne Test", rideID: current.ride.id)
        return (moment, ledger.lastCelebratedFTP == nil ? base : nil)
    }

    // MARK: Kandidaten

    struct Built {
        var moments: [Moment] = []
        /// IDs, die nicht gefeiert, aber als gesehen zu vermerken sind (niedrigere Level, weitere Bestleistungsdauern …).
        var silent: [String] = []
    }

    /// Alle Momente, die `includes` (Datum) erlaubt. Bestleistungen werden nur für Fahrten berechnet, die `recordRide`
    /// erlaubt (sie kosten je Fahrt einen Durchlauf über das 90-Tage-Fenster).
    static func build(_ input: MomentInput, includes: (Date) -> Bool, recordRide: (RideSummary) -> Bool) -> Built {
        var built = Built()
        let calendar = input.calendar
        let season = input.season
        let rides = input.rides.sorted { $0.startDate < $1.startDate }

        func rideID(onDayOf date: Date) -> Int? { rides.last { calendar.isDate($0.startDate, inSameDayAs: date) }?.id }

        /// Stufen eines Trophäen-Typs: nur die höchste frische wird gefeiert, die anderen still gesehen.
        func tiers(_ kind: Trophy.Kind, prefix: String) -> [(n: Int, trophy: Trophy)] {
            input.trophies.compactMap { t in
                guard t.kind == kind, t.id.hasPrefix(prefix), let on = t.earnedOn, includes(on),
                      let n = Int(t.id.dropFirst(prefix.count)) else { return nil }
                return (n, t)
            }
        }
        func collapse(_ list: [(n: Int, trophy: Trophy)], key: (Int) -> String, make: (Int, Trophy) -> Moment) {
            guard let top = list.max(by: { $0.n < $1.n }) else { return }
            built.moments.append(make(top.n, top.trophy))
            built.silent += list.filter { $0.n != top.n }.map { key($0.n) }
        }

        // levelUp (= Etappe): Level 1 ist der Start, kein Aufstieg.
        collapse(tiers(.level, prefix: "level-").filter { $0.n >= 2 }, key: { Moment.Key.level($0, season: season) }) { n, t in
            let stage = WinterJourney.stages[min(WinterJourney.stages.count, max(1, n)) - 1]
            return Moment(id: Moment.Key.level(n, season: season), kind: .levelUp, date: t.earnedOn ?? .now, headline: t.title,
                          detail: "Etappe \(stage.number) von \(WinterJourney.stages.count): \(stage.place), \(stage.elevation) m",
                          rideID: rideID(onDayOf: t.earnedOn ?? .now))
        }

        // record: je Fahrt eine Karte über die längste Dauer, die anderen Dauern still gesehen.
        for ride in rides where ride.powerCurve != nil && includes(ride.startDate) && recordRide(ride) {
            let points = PowerCurve.records(for: ride, among: input.rides, now: ride.startDate)
            guard let top = points.max(by: { $0.duration < $1.duration }) else { continue }
            built.moments.append(recordMoment(top, ride: ride, rides: input.rides, calendar: calendar))
            built.silent += points.filter { $0.duration != top.duration }.map { Moment.Key.record(duration: $0.duration, rideID: ride.id) }
        }

        // challengeCompleted
        for challenge in input.challenges {
            guard case .completed(let on) = challenge.state, includes(on) else { continue }
            built.moments.append(Moment(id: Moment.Key.challenge(challenge.id), kind: .challengeCompleted, date: on,
                                        headline: "\(challenge.title) geschafft", detail: challenge.rule, rideID: challenge.completedByRideID))
        }

        // comeback: die erste Aktivität nach einer Lücke von mindestens 10 Tagen
        for index in rides.indices.dropFirst() {
            let ride = rides[index], previous = rides[index - 1]
            guard includes(ride.startDate) else { continue }
            let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: previous.startDate),
                                              to: calendar.startOfDay(for: ride.startDate)).day ?? 0
            guard gap >= comebackGapDays else { continue }
            built.moments.append(Moment(id: Moment.Key.comeback(rideID: ride.id), kind: .comeback, date: ride.startDate,
                                        headline: "Du bist zurück", detail: "Nach \(gap) Tagen Pause wieder im Sattel.", rideID: ride.id))
        }

        // streak
        collapse(tiers(.streak, prefix: "streak-"), key: { Moment.Key.streak($0, season: season) }) { n, t in
            Moment(id: Moment.Key.streak(n, season: season), kind: .streak, date: t.earnedOn ?? .now, headline: "\(n) Wochen in Folge",
                   detail: "Du hältst dein Wochenziel, Woche für Woche.", rideID: nil)
        }

        // firstRide: die erste Radfahrt der Saison
        let seasonStart = calendar.startOfDay(for: input.seasonStart)
        if let first = rides.first(where: { !$0.isForeignSport && $0.startDate >= seasonStart }), includes(first.startDate) {
            let start = WinterJourney.stages[0]
            built.moments.append(Moment(id: Moment.Key.firstRide(season: season), kind: .firstRide, date: first.startDate,
                                        headline: "Start in \(start.place)", detail: "Deine erste Fahrt dieser Saison. Etappe 1 von \(WinterJourney.stages.count).",
                                        rideID: first.id))
        }

        // weekPlanDone: mindestens zwei geplante Einheiten, alle erledigt; Datum der letzten Fahrt der Woche
        for week in input.weeks where week.planned >= 2 && week.done == week.planned {
            let end = calendar.date(byAdding: .day, value: 7, to: week.start) ?? week.start
            guard let last = rides.last(where: { $0.startDate >= week.start && $0.startDate < end }), includes(last.startDate) else { continue }
            built.moments.append(Moment(id: Moment.Key.week(start: dayKey(week.start, calendar)), kind: .weekPlanDone, date: last.startDate,
                                        headline: "Plan der Woche geschafft · \(week.done)/\(week.planned)",
                                        detail: "Alle geplanten Einheiten dieser Woche sind erledigt.", rideID: last.id))
        }

        // strengthTier
        collapse(tiers(.strength, prefix: "strengthWinter-"), key: { Moment.Key.strength($0, season: season) }) { n, t in
            Moment(id: Moment.Key.strength(n, season: season), kind: .strengthTier, date: t.earnedOn ?? .now, headline: "Kraft-Winter · \(n)",
                   detail: "\(n) Krafteinheiten in diesem Winter.", rideID: nil)
        }

        // secondData: erste Fahrt mit Sekundendaten
        if let t = input.trophies.first(where: { $0.kind == .secondData }), let on = t.earnedOn, includes(on) {
            built.moments.append(Moment(id: Moment.Key.secondsFirst, kind: .secondData, date: on, headline: "Sekundengenau",
                                        detail: "Deine erste Fahrt mit Sekundendaten.", rideID: rides.first { $0.powerCurve != nil }?.id))
        }
        return built
    }

    private static func recordMoment(_ point: PowerCurve.Point, ride: RideSummary, rides: [RideSummary], calendar: Calendar) -> Moment {
        let label = Trophies.durationText(point.duration)
        let watts = Int(point.watts.rounded())
        let from = ride.startDate.addingTimeInterval(-90 * 86_400)
        let others = rides.filter { $0.id != ride.id }
        let previous = PowerCurve.aggregate(rides: others, from: from, to: ride.startDate).best(point.duration)
        let detail: String
        if let previous, previous.source == .measured, Int(previous.watts.rounded()) < watts {
            detail = "+\(watts - Int(previous.watts.rounded())) W gegenüber deiner bisherigen Bestleistung (\(shortDate(previous.date, calendar)))"
        } else {
            detail = "Deine stärksten \(label) der letzten 90 Tage."
        }
        return Moment(id: Moment.Key.record(duration: point.duration, rideID: ride.id), kind: .record, date: ride.startDate,
                      headline: "Neue Bestleistung: \(label) · \(watts) W", detail: detail, rideID: ride.id)
    }

    private static func shortDate(_ date: Date, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale.de
        f.timeZone = calendar.timeZone
        f.dateFormat = "d. MMM"
        return f.string(from: date)
    }

    /// `yyyy-MM-dd` im Kalender des Nutzers (nicht UTC): der Wochenstart bleibt der Montag.
    private static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
