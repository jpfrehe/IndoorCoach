import Foundation

/// „Dein Warum“ (docs/22, B4): ein eigener Satz zum Saisonbeginn, den die App im richtigen Moment wörtlich zurückgibt
/// (Willkommen zurück, Level 5 und 10, Postkarte Gardasee). Der Satz bleibt auf dem Gerät: Er liegt in `UserDefaults`
/// (`why.note`), wird von „Alle Daten löschen“ erfasst und ist **nie** Teil des Claude-Prompts oder des Diagnose-Exports
/// (Regressionstest `WhyNotePrivacyTests`). Kein Quelltext, der mit Claude spricht, darf dieses Paar lesen.
public enum WhyNote {
    /// Höchstens so viele Zeichen (Grapheme), damit der Satz auf Karten und Bilder passt.
    public static let maxLength = 140

    /// UserDefaults-Schlüssel des Tages, an dem der Satz geschrieben wurde („Dein Satz vom 4. November“).
    public static let savedOnKey = "why.note.date"
    /// UserDefaults-Schlüssel: Die einmalige Frage „Magst du deinem Winter einen Satz geben?“ wurde beantwortet oder weggetippt.
    public static let promptDismissedKey = "why.prompt.dismissed"

    public static let question = "Warum fährst du diesen Winter?"
    public static let privacyNote = "Bleibt auf deinem iPhone. Geht nicht an Claude."
    public static let promptTitle = "Magst du deinem Winter einen Satz geben?"

    public struct Suggestion: Equatable, Sendable, Identifiable {
        /// Beschriftung des Chips.
        public var label: String
        /// Text, der ins Feld übernommen wird.
        public var text: String
        /// Der offene Chip („Ein Ziel: ______“) ist erst mit eigenem Text ein Satz.
        public var needsCompletion: Bool
        public var id: String { label }
    }

    public static let suggestions: [Suggestion] = [
        Suggestion(label: "Im Frühling mit meiner Gruppe mithalten", text: "Im Frühling mit meiner Gruppe mithalten", needsCompletion: false),
        Suggestion(label: "Fit durch den Winter, ohne Stress", text: "Fit durch den Winter, ohne Stress", needsCompletion: false),
        Suggestion(label: "Ein Ziel: ______", text: "Mein Ziel: ", needsCompletion: true),
        Suggestion(label: "Rad und Studio kombinieren", text: "Rad und Studio kombinieren", needsCompletion: false),
    ]

    /// Trimmt, macht aus Zeilenumbrüchen und Leerräumen ein Leerzeichen, kürzt auf 140 Zeichen; leer → nil.
    public static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let joined = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let cut = String(joined.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? nil : cut
    }

    /// Ein Satz, den die App zitieren darf: nicht leer und nicht nur der offene Chip („Mein Ziel:“).
    public static func isComplete(_ text: String?) -> Bool {
        guard let sentence = normalize(text) else { return false }
        return !suggestions.filter(\.needsCompletion).contains { normalize($0.text) == sentence }
    }

    // MARK: Zitate (wörtlich)

    /// „…“ mit deutschen Anführungszeichen.
    public static func quote(_ sentence: String) -> String { "„\(sentence)“" }

    /// VoiceOver: „Zitat: …“.
    public static func spokenQuote(_ sentence: String) -> String { "Zitat: \(sentence)" }

    /// Willkommen-zurück-Karte: „Du hast geschrieben: „…““.
    public static func writtenLine(_ sentence: String) -> String { "Du hast geschrieben: \(quote(sentence))" }

    /// Gipfelmoment bei Level 5 und 10: „Du hast im November geschrieben: „…““; ohne bekannten Tag ohne Monat. nil ohne Satz.
    public static func momentLine(_ note: String?, savedOn: Date?, calendar: Calendar = .current) -> String? {
        guard let sentence = normalize(note) else { return nil }
        guard let savedOn else { return writtenLine(sentence) }
        let style = Date.FormatStyle(locale: Locale.de, calendar: calendar, timeZone: calendar.timeZone)
        return "Du hast im \(style.month(.wide).format(savedOn)) geschrieben: \(quote(sentence))"
    }
}
