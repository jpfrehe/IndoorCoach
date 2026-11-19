import Foundation

/// A workout as proposed by the coach (Claude or demo planner), before it is persisted.
public struct PlannedWorkoutProposal: Codable, Hashable, Sendable {
    public var date: Date
    public var definition: WorkoutDefinition
    public var rationale: String

    public init(date: Date, definition: WorkoutDefinition, rationale: String) {
        self.date = date
        self.definition = definition
        self.rationale = rationale
    }
}

public struct PlanProposal: Sendable, Hashable {
    public var weekFocus: String
    public var notes: String
    public var workouts: [PlannedWorkoutProposal]
    /// Items the validator dropped, shown to the user for transparency.
    public var rejected: [String]
}

/// Everything the coach needs to know – built from local data, no personal identifiers.
public struct PlanContext: Sendable {
    public var profile: AthleteProfile
    public var today: Date
    public var horizonStart: Date
    public var horizonEnd: Date
    public var load: TrainingLoad.DayLoad?
    public var weeks: [TrainingLoad.WeekSummary]
    public var recentRides: [RideSummary]
    public var alreadyPlanned: [PlannedWorkoutProposal]
    public var wish: String
    /// Season progress towards the spring goal (optional, gives the coach the long-term frame).
    public var winterArc: WinterArc.Status? = nil

    public init(profile: AthleteProfile, today: Date, horizonStart: Date, horizonEnd: Date,
                load: TrainingLoad.DayLoad?, weeks: [TrainingLoad.WeekSummary], recentRides: [RideSummary],
                alreadyPlanned: [PlannedWorkoutProposal], wish: String) {
        self.profile = profile
        self.today = today
        self.horizonStart = horizonStart
        self.horizonEnd = horizonEnd
        self.load = load
        self.weeks = weeks
        self.recentRides = recentRides
        self.alreadyPlanned = alreadyPlanned
        self.wish = wish
    }
}

public enum PlanPrompt {
    public static let system = """
    Du bist ein erfahrener Radsport-Trainer (Leistungsdiagnostik, Trainingssteuerung nach Coggan/TSS) und planst \
    strukturierte Indoor-Einheiten für einen ambitionierten Hobby-Radfahrer auf einem Smart Trainer (Wahoo, ERG-Modus, MyWhoosh).

    Regeln für den Plan:
    - Plane nur an den verfügbaren Wochentagen und nur im angegebenen Zeitraum, höchstens eine Einheit pro Tag.
    - Halte das Wochen-Zeitbudget und die maximale Einheitendauer ein.
    - Steuere die Belastung über TSS: Form (TSB) unter −25 bedeutet Erholung priorisieren; über +10 darf die Last steigen.
      Steigere die Wochenlast gegenüber dem Schnitt der letzten Wochen um höchstens ~10 %.
    - Maximal zwei intensive Einheiten (Sweet Spot und härter) hintereinander; nach VO₂max/Anaerob folgt ein lockerer Tag oder Ruhe.
    - Überwiegend polarisiert/pyramidal: viel Grundlage (Z2), gezielte Qualität (Sweet Spot, Schwelle, VO₂max) passend zum Ziel.
    - Jede Einheit beginnt mit Einfahren (warmup, 8–15 min) und endet mit Ausfahren (cooldown, 5–10 min).
    - Leistung immer als Anteil der FTP (1.0 = 100 % FTP). Intervalle als kind "intervals" mit repeat/onDuration/offDuration/onPower/offPower.
    - Dauer in Sekunden. Felder, die für ein Segment nicht gelten, sind null.
    - Indoor-Einheiten eher kompakt: 45–90 Minuten, lange Grundlage nur am Wochenende, falls Zeit vorhanden.
    - Berücksichtige bereits geplante Einheiten (nicht doppelt planen) und den Freitext-Wunsch des Athleten.
    - Schreibe alle Texte auf Deutsch, knapp und motivierend. "summary": 1 Satz zum Ablauf. "rationale": 1–2 Sätze, warum diese Einheit an diesem Tag.
    - Aufwärm-Check: Direkt nach dem Einfahren (warmup) steht in jeder Einheit ein Block kind "steady", 360 Sekunden, \
    power = Referenzleistung des Athleten als Anteil der FTP (siehe Abschnitt Athlet), cadence 90, text "Aufwärm-Check". \
    Ändere diese Leistung nie und lass den Block nicht weg; er ist ein fester Vergleichspunkt, kein Training.
    - Optional "text" in Segmenten für kurze Hinweise, die während der Fahrt eingeblendet werden (max. 60 Zeichen).
    """

    /// JSON schema for structured output. All objects closed, nullable fields expressed via anyOf.
    public static var schema: [String: Any] {
        func nullable(_ type: String) -> [String: Any] { ["anyOf": [["type": type], ["type": "null"]]] }
        let segment: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "kind": ["type": "string", "enum": Segment.Kind.allCases.map(\.rawValue)],
                "duration": ["type": "integer", "description": "Sekunden"],
                "power": nullable("number"),
                "powerLow": nullable("number"),
                "powerHigh": nullable("number"),
                "repeat": nullable("integer"),
                "onDuration": nullable("integer"),
                "offDuration": nullable("integer"),
                "onPower": nullable("number"),
                "offPower": nullable("number"),
                "cadence": nullable("integer"),
                "text": nullable("string")
            ],
            "required": ["kind", "duration", "power", "powerLow", "powerHigh", "repeat", "onDuration", "offDuration",
                         "onPower", "offPower", "cadence", "text"]
        ]
        let workout: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "date": ["type": "string", "format": "date"],
                "title": ["type": "string"],
                "type": ["type": "string", "enum": WorkoutType.allCases.map(\.rawValue)],
                "summary": ["type": "string"],
                "rationale": ["type": "string"],
                "segments": ["type": "array", "items": segment]
            ],
            "required": ["date", "title", "type", "summary", "rationale", "segments"]
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "weekFocus": ["type": "string"],
                "notes": ["type": "string"],
                "workouts": ["type": "array", "items": workout]
            ],
            "required": ["weekFocus", "notes", "workouts"]
        ]
    }

    public static func userMessage(_ ctx: PlanContext, calendar: Calendar = .current) -> String {
        let p = ctx.profile
        let day = Formatters.isoDay
        var lines: [String] = []
        lines.append("## Athlet")
        lines.append("- FTP: \(p.ftp) W, Gewicht: \(Formatters.decimal(p.weightKg, digits: 1)) kg (\(Formatters.decimal(p.wattsPerKg, digits: 2)) W/kg)")
        if let lthr = p.thresholdHeartRate { lines.append("- Schwellen-Herzfrequenz: \(lthr) bpm") }
        lines.append("- Ziel: \(p.goal.isEmpty ? "allgemeine Fitness" : p.goal)")
        if let goalDate = p.goalDate {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: ctx.today),
                                               to: calendar.startOfDay(for: goalDate)).day ?? 0
            lines.append("- Zieldatum: \(day.string(from: goalDate)) (in \(days) Tagen)")
        }
        let available = p.trainingDays.sorted().compactMap { AthleteProfile.weekdayLongNames[$0] }.joined(separator: ", ")
        lines.append("- Verfügbare Tage: \(available.isEmpty ? "keine Angabe" : available)")
        lines.append("- Zeitbudget: \(Formatters.decimal(p.weeklyHours, digits: 1)) h/Woche, maximal \(p.longestSessionMinutes) min pro Einheit")
        if p.ftp > 0 {
            let ref = p.effectiveWarmupCheckWatts
            let fraction = WarmupCheck.fraction(refWatts: ref, ftp: p.ftp)
            lines.append("- Aufwärm-Check: \(ref) W = \(Int((fraction * 100).rounded())) % FTP (power \(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), fraction)))")
        }
        if !p.notes.isEmpty { lines.append("- Hinweise: \(p.notes)") }

        lines.append("")
        lines.append("## Aktueller Zustand (\(day.string(from: ctx.today)))")
        if let arc = ctx.winterArc {
            let goal = arc.goal.formatted(.dateTime.day().month(.twoDigits).year().locale(Locale(identifier: "de_DE")))
            lines.append("- Winter Arc: Level \(arc.level.number)/10 („\(arc.level.name)“), Fitness \(Formatters.decimal(arc.currentCTL)) → Ziel \(Formatters.decimal(arc.targetCTL)) bis \(goal), \(arc.daysLeft) Tage übrig, Status: \(arc.pace.label), Kurslinie heute \(Formatters.decimal(arc.paceCTL))")
        }
        if let load = ctx.load {
            lines.append("- Fitness (CTL): \(Formatters.decimal(load.ctl)), Ermüdung (ATL): \(Formatters.decimal(load.atl)), Form (TSB): \(Formatters.decimal(load.tsb))")
        } else {
            lines.append("- Keine Belastungsdaten vorhanden.")
        }

        lines.append("")
        lines.append("## Wochen (Mo–So): Fahrten, Zeit, TSS, davon indoor")
        for w in ctx.weeks.suffix(6) {
            lines.append("- \(day.string(from: w.weekStart)): \(w.rides) Fahrten, \(Formatters.duration(w.seconds)), TSS \(Formatters.decimal(w.tss)), indoor \(Formatters.duration(w.indoorSeconds))")
        }

        lines.append("")
        lines.append("## Letzte Einheiten (neueste zuerst)")
        if ctx.recentRides.isEmpty { lines.append("- keine") }
        for r in ctx.recentRides.sorted(by: { $0.startDate > $1.startDate }).prefix(14) {
            let est = TrainingLoad.estimateTSS(for: r, ftp: p.ftp, thresholdHeartRate: p.thresholdHeartRate)
            var parts = ["\(day.string(from: r.startDate))", r.isIndoor ? "indoor" : "outdoor", Formatters.duration(r.movingTime)]
            if let np = r.weightedAverageWatts { parts.append("NP \(Int(np)) W") }
            else if let avg = r.averageWatts { parts.append("Ø \(Int(avg)) W") }
            if let hr = r.averageHeartrate { parts.append("Ø HF \(Int(hr))") }
            parts.append("TSS \(Int(est.tss.rounded()))")
            if let intensity = est.intensityFactor { parts.append("IF \(Formatters.decimal(intensity, digits: 2))") }
            lines.append("- " + parts.joined(separator: ", "))
        }

        if !ctx.alreadyPlanned.isEmpty {
            lines.append("")
            lines.append("## Bereits geplant (nicht erneut planen)")
            for w in ctx.alreadyPlanned.sorted(by: { $0.date < $1.date }) {
                lines.append("- \(day.string(from: w.date)): \(w.definition.title) (\(w.definition.type.label), \(Formatters.duration(w.definition.totalDuration)), TSS \(Int(w.definition.estimatedTSS.rounded())))")
            }
        }

        lines.append("")
        lines.append("## Auftrag")
        lines.append("Plane die Indoor-Einheiten von \(day.string(from: ctx.horizonStart)) bis einschließlich \(day.string(from: ctx.horizonEnd)).")
        let wish = ctx.wish.trimmingCharacters(in: .whitespacesAndNewlines)
        if !wish.isEmpty { lines.append("Wunsch des Athleten: \(wish)") }
        return lines.joined(separator: "\n")
    }

    // MARK: Response parsing & validation

    struct RawPlan: Decodable {
        let weekFocus: String
        let notes: String
        let workouts: [RawWorkout]
    }

    struct RawWorkout: Decodable {
        let date: String
        let title: String
        let type: String
        let summary: String
        let rationale: String
        let segments: [Segment]
    }

    /// Decodes the JSON text returned by Claude and drops anything implausible.
    public static func parse(_ json: String, context ctx: PlanContext, calendar: Calendar = .current) throws -> PlanProposal {
        let raw = try JSONDecoder().decode(RawPlan.self, from: Data(json.utf8))
        var accepted: [PlannedWorkoutProposal] = []
        var rejected: [String] = []
        let start = calendar.startOfDay(for: ctx.horizonStart)
        let end = calendar.startOfDay(for: ctx.horizonEnd)
        var usedDays = Set(ctx.alreadyPlanned.map { calendar.startOfDay(for: $0.date) })

        for w in raw.workouts.prefix(31) {
            guard let parsed = Formatters.isoDay.date(from: w.date) else {
                rejected.append("\(w.title): ungültiges Datum \(w.date)"); continue
            }
            let date = calendar.startOfDay(for: parsed)
            guard date >= start, date <= end else {
                rejected.append("\(w.title): Datum \(w.date) außerhalb des Zeitraums"); continue
            }
            guard !usedDays.contains(date) else {
                rejected.append("\(w.title): am \(w.date) ist schon eine Einheit geplant"); continue
            }
            let segments = WarmupCheck.ensuringBlock(in: w.segments.prefix(60).compactMap(sanitize),
                                                     refWatts: ctx.profile.effectiveWarmupCheckWatts, ftp: ctx.profile.ftp)
            let definition = WorkoutDefinition(title: clean(w.title, max: 80), type: WorkoutType(rawValue: w.type) ?? .mixed,
                                               summary: clean(w.summary, max: 400), segments: segments)
            guard definition.totalDuration >= 10 * 60, definition.totalDuration <= 5 * 3600 else {
                rejected.append("\(w.title): unplausible Dauer"); continue
            }
            usedDays.insert(date)
            accepted.append(PlannedWorkoutProposal(date: date, definition: definition, rationale: clean(w.rationale, max: 500)))
        }
        return PlanProposal(weekFocus: clean(raw.weekFocus, max: 120), notes: clean(raw.notes, max: 800),
                            workouts: accepted.sorted { $0.date < $1.date }, rejected: rejected)
    }

    /// Removes control characters (keeps newlines) and clamps length – LLM text ends up in XML and calendar notes.
    static func clean(_ s: String, max: Int) -> String {
        let scalars = s.unicodeScalars.filter { $0 == "\n" || !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > max ? String(text.prefix(max - 1)) + "…" : text
    }

    /// Clamps powers to a sane range and drops broken segments.
    static func sanitize(_ s: Segment) -> Segment? {
        var s = s
        func clamp(_ v: Double?) -> Double? { v.map { min(max($0, 0.3), 2.5) } }
        s.power = clamp(s.power); s.powerLow = clamp(s.powerLow); s.powerHigh = clamp(s.powerHigh)
        s.onPower = clamp(s.onPower); s.offPower = clamp(s.offPower)
        s.cadence = s.cadence.flatMap { (40...140).contains($0) ? $0 : nil }
        s.text = s.text.map { clean($0, max: 60) }.flatMap { $0.isEmpty ? nil : $0 }
        switch s.kind {
        case .intervals:
            guard let r = s.repeatCount, r > 0, r <= 40, let on = s.onDuration, (5...3600).contains(on),
                  let off = s.offDuration, (0...3600).contains(off), s.onPower != nil else { return nil }
            s.offPower = s.offPower ?? 0.5
            s.duration = r * (on + off)
        case .steady:
            guard s.duration > 0, s.power != nil else { return nil }
        case .warmup, .ramp, .cooldown:
            guard s.duration > 0 else { return nil }
            if s.powerLow == nil || s.powerHigh == nil {
                s.powerLow = s.powerLow ?? s.power ?? 0.45
                s.powerHigh = s.powerHigh ?? s.power ?? 0.7
            }
        case .freeRide:
            guard s.duration > 0 else { return nil }
        }
        guard s.effectiveDuration <= 4 * 3600 else { return nil }
        return s
    }
}
