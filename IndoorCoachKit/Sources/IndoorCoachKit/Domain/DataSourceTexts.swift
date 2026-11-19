import Foundation

// Texte und Auswertung für Profil → Datenquellen (docs/17 §5, §9.9, B51). Ehrlich über Lücken, keine Versprechen.

/// Wie oft eine Quelle in letzter Zeit einen Wert geliefert hat. `metric == nil` steht für Workouts.
public struct HealthSourceUsage: Equatable, Sendable {
    public var metric: HealthMetric?
    public var source: HealthSourceRef
    public var days: Int
}

public enum HealthSourceUsageBuilder {
    /// Tage mit Werten je Kennzahl und Quelle im Fenster; häufigste Quelle zuerst.
    public static func usage(dailies: [HealthDaily], workouts: [HealthWorkout] = [], now: Date, windowDays: Int = 28,
                             calendar: Calendar = .current) -> [HealthSourceUsage] {
        guard let from = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: now)) else { return [] }
        var days: [HealthMetric: [HealthSourceRef: Set<Date>]] = [:]
        for d in dailies where d.date > from && d.date <= now {
            days[d.metric, default: [:]][d.source, default: []].insert(calendar.startOfDay(for: d.date))
        }
        var out: [HealthSourceUsage] = []
        var workoutDays: [HealthSourceRef: Set<Date>] = [:]
        for w in workouts where w.start > from && w.start <= now && !w.isOwnSource {
            workoutDays[w.source, default: []].insert(calendar.startOfDay(for: w.start))
        }
        func sorted(_ metric: HealthMetric?, _ map: [HealthSourceRef: Set<Date>]) -> [HealthSourceUsage] {
            map.map { HealthSourceUsage(metric: metric, source: $0.key, days: $0.value.count) }
                .sorted { $0.days != $1.days ? $0.days > $1.days : $0.source.name < $1.source.name }
        }
        out += sorted(nil, workoutDays)
        for metric in HealthMetric.allCases { out += sorted(metric, days[metric] ?? [:]) }
        return out
    }

    /// Mehr als eine Quelle liefert die Kennzahl: dann lohnt eine feste Wahl (Basislinien nicht mischen).
    public static func needsChoice(_ usage: [HealthSourceUsage], metric: HealthMetric) -> Bool {
        usage.filter { $0.metric == metric }.count > 1
    }
}

public enum DataSourceTexts {
    /// Typen mit eigener Erklärung (Puls kommt mit den Workouts mit).
    public static let shownTypes: [HealthReadType] = [.workouts, .restingHR, .sleep, .respiratoryRate, .wristTemperature, .hrvSDNN, .bodyMass]

    public static func title(for type: HealthReadType) -> String {
        switch type {
        case .workouts, .heartRate: "Workouts"
        case .restingHR: "Ruhepuls"
        case .sleep: "Schlafdauer"
        case .respiratoryRate: "Atemfrequenz"
        case .wristTemperature: "Handgelenktemperatur"
        case .hrvSDNN: "Herzratenvariabilität (HRV)"
        case .bodyMass: "Gewicht"
        }
    }

    public static func explanation(for type: HealthReadType) -> String {
        switch type {
        case .workouts, .heartRate:
            "Deine Einheiten anderer Sportarten samt Puls. So kennt der Rad-Plan die ganze Woche, etwa Kraft, Laufen oder Langlauf."
        case .restingHR: "Dein Ruhepuls am Morgen. Er hilft, Erholung und Trend einzuordnen – nie als alleinige Aussage."
        case .sleep: "Die Dauer deines Schlafs je Nacht. Es zählt nur die Schlafzeit, keine Schlafphasen."
        case .respiratoryRate: "Deine Atemfrequenz im Schlaf, als Teil des Erholungsbilds."
        case .wristTemperature: "Die Abweichung deiner nächtlichen Handgelenktemperatur von deiner Basis. Liefert nur die Apple Watch."
        case .hrvSDNN: "Dein HRV-Wert (SDNN) aus der Nacht. Er wird nur mit deiner eigenen Basis verglichen, nie mit anderen."
        case .bodyMass: "Dein Gewicht, als Mittel der letzten 7 Tage. Es fließt in W/kg ein, wenn du es erlaubst."
        }
    }

    public static func metric(for type: HealthReadType) -> HealthMetric? {
        switch type {
        case .restingHR: .restingHR
        case .sleep: .sleepHours
        case .respiratoryRate: .respiratoryRate
        case .wristTemperature: .wristTempDelta
        case .hrvSDNN: .hrvSDNN
        case .bodyMass: .bodyMass
        case .workouts, .heartRate: nil
        }
    }

    public static func title(for metric: HealthMetric) -> String {
        switch metric {
        case .restingHR: "Ruhepuls"
        case .hrvSDNN: "HRV"
        case .sleepHours: "Schlafdauer"
        case .respiratoryRate: "Atemfrequenz"
        case .wristTempDelta: "Handgelenktemperatur"
        case .bodyMass: "Gewicht"
        }
    }

    /// Ehrliche Lücken: was Apple Health von anderen Geräten und Apps nicht bekommt.
    public static let gaps: [String] = [
        "Garmin, Whoop und Polar schreiben kein HRV nach Apple Health. Hast du nur diese Geräte, bleibt die HRV-Karte leer.",
        "MyWhoosh schreibt nicht nach Apple Health – Fahrten kommen über MyWhoosh/Mac-Brücke.",
        "Die Handgelenktemperatur gibt es nur von der Apple Watch.",
        "Ob du den Lesezugriff erlaubt hast, verrät Apple der App nicht. Fehlt ein Wert, prüfe in Health → Profil → Apps → IndoorCoach."
    ]

    public static let pinNote = "Ein Wechsel startet eine neue Basis: ältere Werte der früheren Quelle zählen dann nicht mehr, damit nichts vermischt wird."

    public struct MethodItem: Equatable, Sendable {
        public var title: String
        public var text: String
    }

    /// Methodenseite „So rechnet IndoorCoach“.
    public static let method: [MethodItem] = [
        MethodItem(title: "Puls-TSS (hrTSS)",
                   text: "Ohne Leistungsdaten schätzt IndoorCoach die Last aus dem Puls: Stunden × (Ø-Puls ÷ Schwellen-HF)² × 100. Das ist eine Schätzung und im Etikett als „geschätzt“ markiert."),
        MethodItem(title: "TRIMP und Relative Effort",
                   text: "Die Belastung des Herzkreislaufs rechnen wir nach Banister als TRIMP aus Ruhe-, Max- und Durchschnittspuls. Liegen Pulssekunden vor, wird sekundengenau gerechnet. Der Faktor ist deine Pulsreserve, nicht ein Wert von uns."),
        MethodItem(title: "Muskel-Last",
                   text: "Muskel-Last = Härte × Minuten (Session-RPE, Skala 0–10). Sie steht neben der Rad-Fitness und wird nie in TSS, Fitness oder Ermüdung umgerechnet – ein solcher Faktor wäre erfunden."),
        MethodItem(title: "Aufwärm-Check",
                   text: "Jedes Aufwärmen enthält einen Standardblock mit fester Referenzleistung. Der Durchschnittspuls der letzten 60 Sekunden zeigt über Wochen, ob der Puls bei gleicher Leistung sinkt. Er ist ein Vergleichspunkt, keine Aussage über Müdigkeit."),
        MethodItem(title: "ERG-Annahme",
                   text: "Fehlen Leistungssekunden (nur Puls und Plan), nehmen wir an, dass die Rolle im ERG-Modus die Soll-Leistung gehalten hat. Das gilt nur für stationäre Blöcke ab 2 Minuten und wird als „angenommen“ gekennzeichnet. Angenommene Watt werden nie nach Health geschrieben."),
        MethodItem(title: "Quellenetiketten",
                   text: "gemessen (Gurt oder Gerät) · angenommen (ERG) · geschätzt (aus dem Puls) · angegeben (Check-in, Härte) · Mindestwert (nur ein Teil der Daten liegt vor).")
    ]
}
