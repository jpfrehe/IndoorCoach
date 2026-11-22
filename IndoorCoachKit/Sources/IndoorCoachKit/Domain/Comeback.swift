import Foundation

/// Willkommen zurück (docs/22, B4): nach mindestens 10 Tagen ohne Aktivität empfängt die App freundlich, ohne Urteil.
/// Rein regelbasiert und lokal. Tonregel: nie „verpasst“, „gesunken“, „verloren“ oder „Rückstand“, keine Formkurve.
public enum Comeback {
    /// Ab so vielen Kalendertagen seit der letzten Aktivität erscheint die Karte (bei 9 noch nicht).
    public static let thresholdDays = 10

    /// UserDefaults-Schlüssel: Tag („yyyy-MM-dd“), an dem „Später“ getippt wurde; die Karte bleibt für diesen Tag aus.
    public static let dismissedKey = "comeback.dismissedDay"

    /// Zeitliche Marke der Rückkehr (Fresh-Start-Effekt): ergänzt die Karte um einen Satz.
    public enum Landmark: Equatable, Sendable { case newWeek, newMonth, newYear }

    public enum State: Equatable, Sendable {
        case none
        case returning(days: Int, landmark: Landmark?)
    }

    /// - Parameters:
    ///   - lastActivity: Beginn der jüngsten Einheit (Rad, Kraft, andere, Fremdsport aus Health); nil = noch nie etwas.
    ///   - now: heute (`AppModel.today`).
    ///   - calendar: bestimmt, wo der Tag endet (lokale Zeitzone).
    public static func state(lastActivity: Date?, now: Date, calendar: Calendar = .current) -> State {
        guard let lastActivity else { return .none }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastActivity), to: calendar.startOfDay(for: now)).day ?? 0
        guard days >= thresholdDays else { return .none }
        return .returning(days: days, landmark: landmark(on: now, calendar: calendar))
    }

    /// Neujahr schlägt Monatserster, Monatserster schlägt Montag.
    static func landmark(on date: Date, calendar: Calendar) -> Landmark? {
        let c = calendar.dateComponents([.month, .day, .weekday], from: date)
        if c.month == 1 && c.day == 1 { return .newYear }
        if c.day == 1 { return .newMonth }
        if c.weekday == 2 { return .newWeek }
        return nil
    }

    // MARK: Texte

    public struct Texts: Equatable, Sendable {
        public var title: String
        /// „12 Tage Pause. Das gehört zum Winter dazu.“
        public var lead: String
        /// Joker-Satz oder „Deine nächste Serie beginnt mit der nächsten Einheit.“
        public var streak: String
        /// „Du hast geschrieben: „…““ – nur mit gesetztem Warum.
        public var quote: String?
        public var quoteSpoken: String?
        public var landmark: String?
        public var hint: String
        public var start: String
        public var later: String
        /// Die ganze Karte für VoiceOver in Lesereihenfolge.
        public var accessibility: String
    }

    /// - Parameters:
    ///   - jokerWeek: Montag der Woche, die ein Joker aufgefangen hat (nur wenn es sie in der Pause gab).
    ///   - why: der Satz aus „Dein Warum“, wörtlich.
    public static func texts(state: State, jokerWeek: Date?, why: String?, calendar: Calendar = .current) -> Texts {
        guard case .returning(let days, let landmarkKind) = state else {
            return Texts(title: "", lead: "", streak: "", quote: nil, quoteSpoken: nil, landmark: nil, hint: "", start: "", later: "",
                         accessibility: "")
        }
        let title = "Schön, dass du wieder da bist"
        let lead = "\(days) Tage Pause. Das gehört zum Winter dazu."
        let streak: String
        if let jokerWeek {
            let style = Date.FormatStyle(locale: Locale.de, calendar: calendar, timeZone: calendar.timeZone)
            streak = "Dein Joker hat die Woche ab \(style.day().month(.abbreviated).format(jokerWeek)) aufgefangen, deine Serie steht."
        } else {
            streak = "Deine nächste Serie beginnt mit der nächsten Einheit."
        }
        let sentence = WhyNote.normalize(why)
        let quote = sentence.map(WhyNote.writtenLine)
        let spoken = sentence.map(WhyNote.spokenQuote)
        let landmark: String? = switch landmarkKind {
        case .newWeek: "Neue Woche, neuer Anfang."
        case .newMonth: "Neuer Monat, neues Kapitel."
        case .newYear: "Neues Jahr. Dein Frühling kommt trotzdem pünktlich."
        case nil: nil
        }
        let hint = "Die ersten zwei Einheiten dürfen ruhig locker sein."
        let start = "Heute locker einsteigen", later = "Später"
        let spokenParts = ["\(title).", lead, landmark, streak, spoken, hint].compactMap { $0 }
        return Texts(title: title, lead: lead, streak: streak, quote: quote, quoteSpoken: spoken, landmark: landmark, hint: hint,
                     start: start, later: later, accessibility: spokenParts.joined(separator: " "))
    }

    // MARK: Startaktion „Heute locker einsteigen“

    public enum StartAction: Equatable, Sendable {
        /// Geplante leichte Einheit: „Einheit anpassen“ vorausgewählt auf 30 min und 10 % leichter (`WorkoutAdjust`).
        case adjust(minutes: Int, easierBy: Int)
        /// Geplante harte Einheit: der vorhandene Tausch gegen Grundlage (`WorkoutSwap`).
        case swapToBase
        /// Ohne Plan: „Grundlage 30 min“ als neue Einheit, mit Senden und Export wie gewohnt.
        case easyRide(minutes: Int)
    }

    public static let easyMinutes = 30
    public static let easierPercent = 10

    /// - Parameter planned: die geplante Einheit heute oder morgen, falls es eine gibt.
    public static func startAction(planned: WorkoutDefinition?) -> StartAction {
        guard let planned else { return .easyRide(minutes: easyMinutes) }
        let isEasy = [WorkoutType.endurance, .recovery].contains(planned.type)
        if !isEasy, WorkoutSwap.base(for: planned) != nil { return .swapToBase }
        return .adjust(minutes: easyMinutes, easierBy: easierPercent)
    }

    /// Lockere Grundlage ohne Plan: Warm-up, Z2, Cool-down, zusammen `minutes` lang.
    public static func easyRide(minutes: Int = easyMinutes) -> WorkoutDefinition {
        let total = max(15, minutes) * 60
        let warm = 300, cool = 300
        let segments = [
            Segment(kind: .warmup, duration: warm, powerLow: 0.45, powerHigh: 0.60),
            Segment(kind: .steady, duration: total - warm - cool, power: WorkoutSwap.basePower, text: "Grundlage, locker (Z2)"),
            Segment(kind: .cooldown, duration: cool, powerLow: 0.40, powerHigh: 0.60),
        ]
        return WorkoutDefinition(title: "Grundlage \(total / 60) min", type: .endurance,
                                 summary: "Lockerer Wiedereinstieg: \(total / 60) Minuten Grundlage in Z2, ohne Druck.", segments: segments)
    }

    // MARK: Highlight-Slot auf Heute

    public enum Highlight: Equatable, Sendable {
        case comeback(state: State)
        /// Einmalig nach der ersten Fahrt der Saison: „Magst du deinem Winter einen Satz geben?“
        case whyPrompt
    }

    /// Was im Highlight-Slot vor Wochenrückblick und Challenge steht (höchste Priorität), oder nil.
    /// Das Willkommen zurück hat Vorrang vor der Warum-Frage; „Später“ blendet es nur für heute aus.
    public static func highlight(state: State, today: Date, dismissedDay: String?, whyNote: String?, whyPromptDismissed: Bool,
                                 rodeThisSeason: Bool, arcActive: Bool, calendar: Calendar = .current) -> Highlight? {
        guard arcActive else { return nil }
        if case .returning = state {
            return dismissedDay == dayKey(today, calendar: calendar) ? nil : .comeback(state: state)
        }
        if rodeThisSeason, !whyPromptDismissed, WhyNote.normalize(whyNote) == nil { return .whyPrompt }
        return nil
    }

    /// Lokaler Kalendertag als „yyyy-MM-dd“ (Speicherform von „Später“).
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
