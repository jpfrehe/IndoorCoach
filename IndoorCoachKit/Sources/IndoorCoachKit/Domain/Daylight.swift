import Foundation

/// Winterlicht (docs/22, B3): wie viel länger es hell ist als am kürzesten Tag. Rein rechnerisch, ohne Ortung und ohne
/// Verbindung: Sonnendeklination nach NOAA, Tageslänge aus dem Stundenwinkel, Breitengrad als grobe Näherung je Zeitzone (E3).
public enum Daylight {
    /// Mitte Deutschlands; auch die Näherung für jede andere Zeitzone.
    public static let defaultLatitude = 50.0

    // MARK: Breitengrad je Zeitzone (keine Ortung)

    public enum Region: Equatable, Sendable { case germany, austria, switzerland, other }

    public static func region(for zone: TimeZone) -> Region {
        switch zone.identifier {
        case "Europe/Berlin", "Europe/Busingen": .germany
        case "Europe/Vienna": .austria
        case "Europe/Zurich", "Europe/Vaduz": .switzerland
        default: .other
        }
    }

    /// Berlin 50°, Wien 48°, Zürich 47°, sonst 50° (Näherung, auch für die Südhalbkugel: die Saison der App ist der Nordwinter).
    public static func latitude(for zone: TimeZone) -> Double {
        switch region(for: zone) {
        case .austria: 48
        case .switzerland: 47
        case .germany, .other: defaultLatitude
        }
    }

    /// Ehrliche Fußnote: nennt die Näherung, nie einen Ort.
    public static func footnote(for zone: TimeZone) -> String {
        switch region(for: zone) {
        case .germany: "Berechnet für die Mitte Deutschlands (50° N)."
        case .austria: "Berechnet für Österreich (48° N)."
        case .switzerland: "Berechnet für die Schweiz (47° N)."
        case .other: "Berechnet für 50° N (Näherung, ohne Ortung)."
        }
    }

    // MARK: Tageslänge

    /// Länge des hellen Tages in Sekunden (0 in der Polarnacht, 86 400 bei Mitternachtssonne). Es zählt nur der Kalendertag
    /// in `calendar` (lokale Zone), nicht die Uhrzeit.
    public static func length(on date: Date, latitude: Double, calendar: Calendar = .current) -> TimeInterval {
        let day = calendar.startOfDay(for: date)
        let ordinal = calendar.ordinality(of: .day, in: .year, for: day) ?? 1
        let daysInYear = Double(calendar.range(of: .day, in: .year, for: day)?.count ?? 365)
        let g = 2 * Double.pi / daysInYear * Double(ordinal - 1)      // Bruchteil des Jahres in Bogenmaß (Mittag)
        let declination = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g)
            + 0.000907 * sin(2 * g) - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let phi = min(89.9, max(-89.9, latitude)) * Double.pi / 180
        let horizon = -0.833 * Double.pi / 180                         // Refraktion und Sonnenradius
        let cosOmega = (sin(horizon) - sin(phi) * sin(declination)) / (cos(phi) * cos(declination))
        let omega = acos(min(1, max(-1, cosOmega)))                    // Halbtagbogen in Bogenmaß
        return min(86_400, max(0, 2 * omega * 180 / Double.pi / 15 * 3600))
    }

    /// Erster Tag des Jahresendes: der 21.12., an dem das Licht wieder zunimmt.
    static func lastSolstice(onOrBefore date: Date, calendar: Calendar) -> Date {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year = c.year ?? 2026
        let thisYear = (c.month ?? 1) == 12 && (c.day ?? 1) >= 21
        return calendar.date(from: DateComponents(year: thisYear ? year : year - 1, month: 12, day: 21, hour: 12)) ?? date
    }

    /// Wie viel länger der Tag heute ist als am letzten 21.12., in Sekunden. Auf der Südhalbkugel rechnerisch negativ.
    public static func gainSinceSolstice(now: Date, latitude: Double, calendar: Calendar = .current) -> TimeInterval {
        let solstice = lastSolstice(onOrBefore: now, calendar: calendar)
        return length(on: now, latitude: latitude, calendar: calendar) - length(on: solstice, latitude: latitude, calendar: calendar)
    }

    // MARK: Phasen

    public enum Phase: Equatable, Sendable {
        /// Tage bis zur Wintersonnenwende (1…).
        case beforeSolstice(days: Int)
        case solstice
        /// Minuten Tageslicht seit der Wintersonnenwende (nie negativ).
        case lengthening(gainMinutes: Int)
        /// Ab dem 20.3.: die Tage sind länger als die Nächte.
        case afterEquinox
    }

    /// 21.12. = `.solstice`; 22.12. bis 19.3. = `.lengthening`; 20.3. bis 31.7. = `.afterEquinox`; sonst Countdown.
    public static func phase(now: Date, latitude: Double = defaultLatitude, calendar: Calendar = .current) -> Phase {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = c.year, let month = c.month, let day = c.day else { return .afterEquinox }
        if month == 12 && day == 21 { return .solstice }
        if (month == 12 && day > 21) || month <= 2 || (month == 3 && day < 20) {
            let gain = gainSinceSolstice(now: now, latitude: latitude, calendar: calendar)
            return .lengthening(gainMinutes: max(0, Int((gain / 60).rounded())))
        }
        if month <= 7 { return .afterEquinox }
        let solstice = calendar.date(from: DateComponents(year: year, month: 12, day: 21, hour: 12)) ?? now
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: solstice)).day ?? 0
        return .beforeSolstice(days: max(1, days))
    }

    // MARK: Texte

    /// Die Zeile für Hub und Heute (Identifier `winterlight.line`).
    public static func line(for phase: Phase) -> String {
        switch phase {
        case .beforeSolstice(let days):
            "Noch \(days) \(days == 1 ? "Tag" : "Tage") bis zur Wintersonnenwende. Danach wird jeder Tag ein bisschen heller."
        case .solstice:
            "Heute ist Wintersonnenwende, der kürzeste Tag des Jahres. Ab morgen geht’s bergauf."
        case .lengthening(let minutes):
            minutes < 1 ? "Seit der Wintersonnenwende werden die Tage wieder länger."
                : "+\(minutes) min Tageslicht seit der Wintersonnenwende"
        case .afterEquinox:
            "Die Tage sind jetzt länger als die Nächte. Frühling!"
        }
    }

    /// Kurzfassung für den Chip in der Winter-Arc-Karte auf Heute.
    public static func chip(for phase: Phase) -> String {
        switch phase {
        case .beforeSolstice(let days): "Noch \(days) \(days == 1 ? "Tag" : "Tage") bis zur Sonnenwende"
        case .solstice: "Heute Sonnenwende"
        case .lengthening(let minutes): minutes < 1 ? "Tage werden länger" : "+\(minutes) min Licht"
        case .afterEquinox: "Tage länger als Nächte"
        }
    }

    /// VoiceOver: „34 Minuten“ statt „plus 34 min“.
    public static func spokenLine(for phase: Phase) -> String {
        if case .lengthening(let minutes) = phase, minutes >= 1 {
            return "\(minutes) \(minutes == 1 ? "Minute" : "Minuten") mehr Tageslicht seit der Wintersonnenwende"
        }
        return line(for: phase)
    }

    /// „Bis zu deinem Ziel am 21. März: noch 86 Tage. Dann hast du 4 h 10 min mehr Licht als heute.“ – nil ab dem Zieltag.
    public static func goalLine(now: Date, goal: Date, latitude: Double, calendar: Calendar = .current) -> String? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: goal)).day ?? 0
        guard days > 0 else { return nil }
        let extra = length(on: goal, latitude: latitude, calendar: calendar) - length(on: now, latitude: latitude, calendar: calendar)
        let when = goal.formatted(.dateTime.day().month(.wide).locale(Locale.de))
        let head = "Bis zu deinem Ziel am \(when): noch \(days) \(days == 1 ? "Tag" : "Tage")."
        let minutes = Int((extra / 60).rounded())
        guard minutes >= 1 else { return head }
        return head + " Dann hast du \(durationText(minutes: minutes)) mehr Licht als heute."
    }

    /// „4 h 10 min“, „45 min“, „2 h“.
    static func durationText(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    // MARK: Sonne und Verlauf

    /// 0…1: wie weit der Tageslicht-Gewinn seit dem 21.12. schon auf dem Weg zum Ziel-Tag ist (steuert die Höhe der Sonne).
    public static func sunFraction(now: Date, goal: Date, latitude: Double, calendar: Calendar = .current) -> Double {
        switch Self.phase(now: now, latitude: latitude, calendar: calendar) {
        case .beforeSolstice, .solstice: return 0
        case .afterEquinox, .lengthening: break
        }
        let solstice = lastSolstice(onOrBefore: now, calendar: calendar)
        let base = length(on: solstice, latitude: latitude, calendar: calendar)
        let total = length(on: goal, latitude: latitude, calendar: calendar) - base
        guard total > 0 else { return 0 }
        let todayGain = length(on: min(now, goal), latitude: latitude, calendar: calendar) - base
        if calendar.startOfDay(for: now) > calendar.startOfDay(for: goal) { return 1 }
        return min(1, max(0, todayGain / total))
    }

    public struct LengthPoint: Equatable, Sendable {
        public var date: Date
        public var hours: Double
    }

    /// Tageslänge in Stunden von `from` bis `to` im Abstand von `stepDays`; der letzte Punkt ist immer `to`.
    public static func lengthSeries(from: Date, to: Date, latitude: Double, stepDays: Int = 7,
                                    calendar: Calendar = .current) -> [LengthPoint] {
        guard from <= to else { return [] }
        var points: [LengthPoint] = []
        var date = from
        while date < to {
            points.append(LengthPoint(date: date, hours: length(on: date, latitude: latitude, calendar: calendar) / 3600))
            guard let next = calendar.date(byAdding: .day, value: max(1, stepDays), to: date) else { break }
            date = next
        }
        points.append(LengthPoint(date: to, hours: length(on: to, latitude: latitude, calendar: calendar) / 3600))
        return points
    }
}
