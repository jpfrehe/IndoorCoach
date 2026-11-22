import Foundation
import SwiftData

// Gipfelmomente (docs/22, B1): Auswertung, Sperren und Aufbereitung für die Feier. Alles lokal; die Erkennung selbst ist
// `MomentDetector`, der Satz kommt aus `CoachNote`. Das Ledger liegt in UserDefaults (`moments.ledger`).

/// Was gerade gegen eine Feier spricht. Die Oberfläche füllt es (Aufzeichnung läuft, ein anderes Blatt ist offen).
public struct MomentGate: Equatable, Sendable {
    public var recordingRunning: Bool
    public var anotherPresentation: Bool

    public init(recordingRunning: Bool = false, anotherPresentation: Bool = false) {
        self.recordingRunning = recordingRunning
        self.anotherPresentation = anotherPresentation
    }
}

/// Alles, was die Feier außer dem Stapel zeigt.
public struct MomentPresentation: Equatable, Sendable {
    public var batch: MomentBatch
    /// Datum des Hauptmoments („GIPFELMOMENT · Do., 18. Dez.“).
    public var date: Date
    public var coachNote: CoachNote?
    /// „Stark, Sabine.“ – nur mit Namen im Profil und jedes zweite Mal.
    public var greeting: String?
    /// Die Postkarte der Etappe bei einem Level-Aufstieg.
    public var postcard: Postcard?
    /// „Dein Warum“ bei Level 5 und 10.
    public var whyQuote: String?
    /// Beispiel mit Demo-Daten (Demo-Modus, UI-Test-Startschalter).
    public var isExample: Bool
    /// Name aus dem Profil für das Teilen-Bild; nil, wenn keiner gesetzt ist.
    public var shareName: String?
    /// 0…1 für den Himmel (`WinterSky`): bei einem Level seine Stufe, sonst der Stand der Saison.
    public var skyProgress: Double
}

@MainActor
private enum MomentEvalCache {
    struct Entry {
        weak var model: AppModel?
        var fingerprint: Int
    }

    /// Letzter ausgewerteter Stand je Modell, damit der Takt der Oberfläche nichts doppelt rechnet. Das schwache Modell
    /// schützt davor, dass ein neues Modell an derselben Adresse einen fremden Stand erbt.
    static var entries: [ObjectIdentifier: Entry] = [:]

    static func isCurrent(_ fingerprint: Int, for model: AppModel) -> Bool {
        guard let entry = entries[ObjectIdentifier(model)] else { return false }
        return entry.model === model && entry.fingerprint == fingerprint
    }

    static func remember(_ fingerprint: Int, for model: AppModel) {
        entries[ObjectIdentifier(model)] = Entry(model: model, fingerprint: fingerprint)
    }
}

extension AppModel {
    static let uiMomentKey = "uiMoment"

    /// Das gespeicherte Ledger (gesehene Momente, Erstauswertung, eFTP-Basis, letzte Regeln der Coach-Notiz).
    public var momentLedger: MomentLedger { MomentLedger.load(from: defaults) }

    // MARK: Auswertung

    /// Wertet die Momente aus und legt höchstens einen Gipfelmoment nach `pendingMoments`. Billig, wenn sich nichts
    /// geändert hat (Fahrtenzahl, neueste Fahrt, Tag). Mit ausgeschaltetem Schalter, während der Einführung oder
    /// solange ein Moment wartet, passiert nichts – die Trophäen bleiben trotzdem verdient.
    public func evaluateMoments(now explicitNow: Date? = nil, force: Bool = false) {
        guard momentsEnabled, pendingMoments.isEmpty, !needsOnboarding else { return }
        let now = explicitNow ?? Self.today
        #if DEBUG
        if let kind = UserDefaults.standard.string(forKey: Self.uiMomentKey) {
            // UI-Tests: ein Beispiel-Moment, ohne die echte Erkennung.
            let batch = DemoMoments.example(kind, now: now)
            if let id = batch.headline?.id, !momentLedger.hasSeen(id) { pendingMoments = batch }
            return
        }
        // Alle übrigen UI-Tests starten mit `-uiSeed`: sie sollen von keiner Feier überdeckt werden.
        if UserDefaults.standard.string(forKey: "uiSeed") != nil { return }
        #endif
        if isDemoMode {
            let example = DemoMoments.example(DemoMoments.defaultKind, now: now)
            if let id = example.headline?.id, !momentLedger.hasSeen(id) { pendingMoments = example }
            return
        }
        let fingerprint = momentFingerprint(now: now)
        guard force || !MomentEvalCache.isCurrent(fingerprint, for: self) else { return }
        MomentEvalCache.remember(fingerprint, for: self)

        let rides = allRides()
        let evaluation = MomentDetector.evaluate(momentInput(rides: rides, now: now), ledger: momentLedger, now: now)
        evaluation.ledger.save(to: defaults)
        pendingMoments = evaluation.batch
    }

    /// Ändert sich, wenn neue Fahrten da sind oder ein neuer Tag beginnt (die Wochen-Serie wächst ohne Fahrt).
    private func momentFingerprint(now: Date) -> Int {
        var newest = FetchDescriptor<StoredRide>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        newest.fetchLimit = 1
        var hasher = Hasher()
        hasher.combine((try? context.fetchCount(FetchDescriptor<StoredRide>())) ?? 0)
        hasher.combine((try? context.fetch(newest))?.first?.startDate)
        hasher.combine(Calendar.current.startOfDay(for: now))
        return hasher.finalize()
    }

    func momentInput(rides: [RideSummary], now: Date) -> MomentInput {
        let calendar = Calendar.current
        let season = WinterArc.defaultSeason(containing: now, calendar: calendar)
        let arc = winterArc(rides: rides, now: now)
        let weeks = consistency(rides: rides, now: now).weeks.map {
            MomentInput.WeekPlan(start: $0.start, planned: $0.adherence.planned, done: $0.adherence.done)
        }
        return MomentInput(season: String(Challenges.seasonStartYear(containing: now, calendar: calendar)),
                           seasonStart: calendar.startOfDay(for: profile.arcStart ?? season.start), rides: rides,
                           trophies: trophies(rides: rides, arc: arc, now: now), challenges: seasonChallenges(rides: rides, now: now),
                           weeks: weeks, calendar: calendar)
    }

    // MARK: Zeigen

    /// Der wartende Stapel, wenn jetzt Zeit für die Feier ist: nichts bei ausgeschaltetem Schalter, während der Einführung,
    /// einer Aufzeichnung, mit anderem offenen Blatt oder kurz vor einer geplanten Einheit (30 Minuten).
    public func momentToPresent(gate: MomentGate = MomentGate(), now explicitNow: Date? = nil) -> MomentBatch? {
        guard momentsEnabled, !pendingMoments.isEmpty, !needsOnboarding, !gate.recordingRunning, !gate.anotherPresentation else { return nil }
        let now = explicitNow ?? Self.today
        if let next = plannedWorkoutToday(now: now), next.date > now, next.date.timeIntervalSince(now) <= 30 * 60 { return nil }
        return pendingMoments
    }

    /// Nach „Weiter“/„Schließen“: Die Momente zählen als gesehen, die verwendete Regel der Coach-Notiz wird vermerkt.
    public func acknowledgeMoments(noteRule: String?) {
        let batch = pendingMoments
        guard !batch.isEmpty else { return }
        MomentDetector.acknowledged(batch, in: momentLedger, noteRule: noteRule).save(to: defaults)
        pendingMoments = .empty
    }

    // MARK: Aufbereitung

    public func momentPresentation(for batch: MomentBatch, now explicitNow: Date? = nil) -> MomentPresentation {
        let now = explicitNow ?? Self.today
        let ledger = momentLedger
        let head = batch.headline
        let isExample = head.map(DemoMoments.isExample) ?? false
        let level = head.flatMap(ShareText.levelNumber(of:))
        let date = head?.date ?? now
        var postcard: Postcard?
        if let level, (1...WinterJourney.stages.count).contains(level) {
            postcard = Postcards.all(level: level, levelProgress: 0, levelDates: [level: date])[level - 1]
        }
        let why = whyNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = isExample ? DemoMoments.coachNote(for: batch, now: now, ledger: ledger)
                             : CoachNote.make(coachNoteContext(for: batch, now: now), ledger: ledger)
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sky: Double
        if let level { sky = Double(min(WinterJourney.stages.count, max(1, level)) - 1) / Double(WinterJourney.stages.count - 1) }
        else {
            let season = WinterArc.defaultSeason(containing: date)
            sky = min(1, max(0, date.timeIntervalSince(season.start) / max(1, season.goal.timeIntervalSince(season.start))))
        }
        return MomentPresentation(batch: batch, date: date, coachNote: note,
                                  greeting: MomentGreeting.make(name: name, ledger: ledger), postcard: postcard,
                                  whyQuote: (level == 5 || level == 10) ? why.flatMap { $0.isEmpty ? nil : $0 } : nil,
                                  isExample: isExample, shareName: name.isEmpty ? nil : name, skyProgress: sky)
    }

    /// Die Momente einer Fahrt für „Gipfelmoment dieser Fahrt ansehen“ (ohne Frische und Ledger); nil ohne Moment, im
    /// Demo-Modus oder mit ausgeschaltetem Schalter.
    public func momentBatch(forRide ride: RideSummary, now explicitNow: Date? = nil) -> MomentBatch? {
        guard momentsEnabled, !isDemoMode else { return nil }
        let now = explicitNow ?? Self.today
        let rides = allRides()
        guard rides.contains(where: { $0.id == ride.id }) else { return nil }
        let moments = MomentDetector.moments(forRide: ride.id, input: momentInput(rides: rides, now: now), now: now)
        return moments.isEmpty ? nil : MomentBatch(moments)
    }

    // MARK: Kontext der Coach-Notiz

    private func coachNoteContext(for batch: MomentBatch, now: Date) -> CoachNoteContext {
        let calendar = Calendar.current
        let rides = allRides()
        var context = CoachNoteContext(now: now, calendar: calendar)
        let rideIDs = batch.moments.compactMap(\.rideID)
        let focus = rides.last { rideIDs.contains($0.id) } ?? rides.last
        let seasonStart = calendar.startOfDay(for: profile.arcStart ?? WinterArc.defaultSeason(containing: now, calendar: calendar).start)

        // Check-in von heute
        if let checkIn = todaysCheckIn(now: now), !checkIn.skipped {
            context.checkIn = checkIn.answers
            if case .shorten? = checkIn.chosen { context.shortened = true }
        }
        // Comeback
        if batch.moments.contains(where: { $0.kind == .comeback }), let focus,
           let previous = rides.last(where: { $0.startDate < focus.startDate }) {
            context.comebackGapDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: previous.startDate),
                                                              to: calendar.startOfDay(for: focus.startDate)).day
        }
        if let focus {
            context.efficiency = CoachNoteContext.efficiency(for: focus, in: rides, seasonStart: seasonStart, calendar: calendar)
        }
        // Aufwärm-Check
        let trend = warmupTrend(rides: rides)
        if trend.direction == .falling, let delta = trend.delta, delta <= -WarmupCheck.trendThreshold {
            let first = rides.filter(\.trainer).compactMap { warmupCheck(for: $0) }
                .filter { $0.valid && $0.refWatts == trend.refWatts }.map(\.date).min()
            let days = first.flatMap { calendar.dateComponents([.day], from: $0, to: now).day } ?? 7
            context.warmup = .init(watts: trend.refWatts, fewerBeats: Int((-delta).rounded()), weeksAgo: max(1, days / 7))
        }
        // Bestleistung: wann es zuletzt etwas Besseres gab
        if let record = batch.moments.first(where: { $0.kind == .record }), let focus,
           let duration = Int(record.id.split(separator: "-").dropFirst().first ?? ""), let watts = focus.powerCurve?[duration] {
            let better = rides.filter { $0.id != focus.id && $0.startDate < focus.startDate && ($0.powerCurve?[duration] ?? 0) >= watts }
                .map(\.startDate).max()
            context.record = .init(duration: duration, betterBefore: better)
        }
        // Serie, Fitness, Saison
        if let arc = winterArc(rides: rides, now: now) {
            if arc.streakWeeks >= 2, let focus, isFirstRideOfItsWeek(focus, in: rides) {
                let thisWeek = Consistency.weekStart(of: now, calendar: calendar)
                if let since = calendar.date(byAdding: .weekOfYear, value: -arc.streakWeeks, to: thisWeek) {
                    context.streak = .init(weeks: arc.streakWeeks, since: since)
                }
            }
            context.fitness = .init(from: Int(arc.startCTL.rounded()), to: Int(arc.currentCTL.rounded()), since: arc.start)
        }
        let inSeason = rides.filter { !$0.isForeignSport && $0.startDate >= seasonStart }
        context.season = .init(sessions: inSeason.count, hours: Int((Double(inSeason.reduce(0) { $0 + $1.movingTime }) / 3600).rounded()),
                               since: seasonStart)
        return context
    }

    private func isFirstRideOfItsWeek(_ ride: RideSummary, in rides: [RideSummary]) -> Bool {
        let week = Consistency.weekStart(of: ride.startDate)
        return rides.filter { Consistency.weekStart(of: $0.startDate) == week }.min { $0.startDate < $1.startDate }?.id == ride.id
    }
}
