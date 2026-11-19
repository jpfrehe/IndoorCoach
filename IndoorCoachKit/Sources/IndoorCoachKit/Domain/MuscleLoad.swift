import Foundation

/// Muskel-Spur (docs/17 §8.2): Muskel-Last = Härte (CR-10, 0–10) × Minuten (Session-RPE nach Foster).
/// Unabhängig von der Rad-PMC (`TrainingLoad`): nichts hier verändert CTL/ATL/TSB.
///
/// Zeitbezug: Eine Einheit gehört zu einem Fenster, wenn ihr **Ende** im Fenster liegt. Die Fenstergrenze zählt noch dazu.
/// Alle Regeln sind Faustregeln aus der Praxis, keine harten Sperren.
public enum MuscleLoad {
    /// Akutes Fenster der Muskel-Spur in Stunden.
    public static let acuteWindowHours: Double = 72
    /// Abstand schwere Beine → Schlüsseleinheit, darunter gilt die Faustregel als verletzt.
    public static let keySessionGapHours: Double = 24
    /// Mindestabstand Intervalle → Kraft am selben Tag.
    public static let sameDayGapHours: Double = 3

    public enum Status: Equatable, Sendable {
        case value(Double)
        /// Härte (oder Dauer) fehlt: nicht berechnen, in der UI „fehlt“.
        case missing
    }

    public struct Sum: Equatable, Sendable {
        public var total: Double
        /// Einheiten mit berechneter Last.
        public var counted: Int
        /// Einheiten im Fenster ohne Härte.
        public var missing: Int
    }

    public static func status(of session: StrengthSession) -> Status {
        guard let e = session.validExertion, session.durationSeconds > 0 else { return .missing }
        return .value(Double(e) * session.durationMinutes)
    }

    public static func load(of session: StrengthSession) -> Double? {
        if case .value(let v) = status(of: session) { return v }
        return nil
    }

    /// Summe im Fenster `[now − hours, now]` (Ende der Einheit).
    public static func sum(of sessions: [StrengthSession], withinHours hours: Double = acuteWindowHours,
                           endingAt now: Date) -> Sum {
        accumulate(sessions.filter { isWithin($0, hours: hours, now: now) })
    }

    /// Summe der Kalenderwoche, die `date` enthält (Zeitzone und Wochenstart aus `calendar`, Start der Einheit).
    public static func weeklySum(of sessions: [StrengthSession], weekContaining date: Date, calendar: Calendar) -> Sum {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return Sum(total: 0, counted: 0, missing: 0) }
        return accumulate(sessions.filter { $0.start >= week.start && $0.start < week.end })
    }

    /// Mindestens eine Einheit mit schweren Beinen im Fenster. Unabhängig von der Härte.
    public static func heavyLegsWithin(hours: Double, of sessions: [StrengthSession], now: Date) -> Bool {
        sessions.contains { $0.effectiveLegShare == .heavy && isWithin($0, hours: hours, now: now) }
    }

    // MARK: Planungsfolgerungen

    public enum KeyIntensity: String, Codable, Sendable, CaseIterable {
        case vo2, threshold, anaerobic

        /// Alle Schlüsselintensitäten sollen nicht kurz nach schweren Beinen liegen.
        public var avoidAfterHeavyLegs: Bool { true }
    }

    public struct Conflict: Equatable, Sendable {
        public var sessionID: UUID
        public var intensity: KeyIntensity
        /// Stunden zwischen Ende der Krafteinheit und geplanter Schlüsseleinheit (< 24).
        public var hoursBetween: Double

        public var reasonKey: String { "muscle.conflict.heavyLegsBeforeKeySession" }

        /// Begründung für Plan-Banner und Claude, als Faustregel gekennzeichnet.
        public var reasonText: String {
            let h = Int(hoursBetween.rounded(.down))
            return "Faustregel: Schwere Beinarbeit liegt nur \(h) h zurück. Vor VO₂, Schwelle oder anaerober Einheit "
                + "besser Grundlage oder Ruhe, sonst fehlt die Frische."
        }
    }

    /// Konflikt, wenn die jüngste Einheit mit schweren Beinen vor `plannedKeySessionAt` endet und weniger als 24 h
    /// zurückliegt (genau 24 h ist kein Konflikt). Einheiten nach dem geplanten Beginn zählen nicht.
    public static func keySessionConflict(sessions: [StrengthSession], plannedKeySessionAt planned: Date,
                                          intensity: KeyIntensity = .vo2) -> Conflict? {
        let candidate = sessions
            .filter { $0.effectiveLegShare == .heavy && $0.end <= planned }
            .max(by: { $0.end < $1.end })
        guard let s = candidate else { return nil }
        let hours = planned.timeIntervalSince(s.end) / 3600
        guard hours < keySessionGapHours else { return nil }
        return Conflict(sessionID: s.id, intensity: intensity, hoursBetween: hours)
    }

    public enum SameDayHint: String, Codable, Sendable {
        /// Intervalle zuerst, Kraft danach, mit ≥ 3 h Abstand.
        case intervalsFirst

        public var reasonKey: String { "muscle.sameDay.intervalsFirst" }

        public var reasonText: String {
            "Faustregel: Am selben Tag Intervalle zuerst, Kraft danach, mit mindestens 3 Stunden Abstand."
        }
    }

    /// Hinweis, wenn die Krafteinheit am selben (Kalender-)Tag vor den Intervallen liegt und weniger als 3 h
    /// Abstand zum Intervallbeginn hat (Überlappung eingeschlossen). Genau 3 h: kein Hinweis.
    public static func sameDayOrder(strength: StrengthSession, intervalsAt: Date, calendar: Calendar) -> SameDayHint? {
        guard calendar.isDate(strength.start, inSameDayAs: intervalsAt), strength.start < intervalsAt else { return nil }
        let gapHours = intervalsAt.timeIntervalSince(strength.end) / 3600
        return gapHours < sameDayGapHours ? .intervalsFirst : nil
    }

    // MARK: Intern

    private static func isWithin(_ s: StrengthSession, hours: Double, now: Date) -> Bool {
        let end = s.end
        return end <= now && now.timeIntervalSince(end) <= hours * 3600
    }

    private static func accumulate(_ sessions: [StrengthSession]) -> Sum {
        var sum = Sum(total: 0, counted: 0, missing: 0)
        for s in sessions {
            if let v = load(of: s) { sum.total += v; sum.counted += 1 } else { sum.missing += 1 }
        }
        return sum
    }
}
