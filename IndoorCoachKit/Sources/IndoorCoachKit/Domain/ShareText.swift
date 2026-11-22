import Foundation

/// Texte für das Teilen-Bild und den Begleittext eines Gipfelmoments (docs/22, B1). Auf geteilten Bildern stehen keine
/// Namen von Diensten, und Leistungswerte nur, wenn der Nutzer „Werte auf dem Bild zeigen“ einschaltet.
public enum ShareText {
    /// Bekannte Dienste und Marken, die nie auf einem Bild oder in einem Begleittext stehen.
    public static let serviceNames: [String] = [
        "MyWhoosh", "Zwift", "Strava", "Garmin", "intervals.icu", "Intervals.icu", "Intervals ICU", "TrainerRoad", "TrainingPeaks",
        "TrainerDay", "Wahoo", "SYSTM", "Rouvy", "Peloton", "Whoop", "Oura", "Suunto", "Coros", "Komoot", "Runna", "Apple Health",
        "Apple Fitness", "Apple Watch", "Claude", "Anthropic",
        // „Polar“ allein ist auch ein Wort („Polar-Nacht“): nur die Marken-Produkte.
        "Polar Flow", "Polar Beat", "Polar Verity Sense", "Polar Verity", "Polar OH1", "Polar H10", "Polar H9", "Polar Vantage", "Polar Grit X",
    ]

    /// Entfernt Dienstnamen (ohne Beachtung der Groß-/Kleinschreibung) samt anhängendem Trennzeichen und räumt Lücken,
    /// leere Klammern und führende/abschließende Trennzeichen auf.
    public static func neutral(_ text: String) -> String {
        var result = text
        for name in serviceNames.sorted(by: { $0.count > $1.count }) {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}])[-–—:·]?"
            result = result.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        result = result.replacingOccurrences(of: "\\(\\s*\\)", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: separators)
        return result
    }

    private static let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—:·,;|/"))

    /// Fahrtname für ein Bild: ohne Dienstnamen, bei leerem Rest neutral „Einheit“.
    public static func rideLabel(_ name: String) -> String {
        let cleaned = neutral(name)
        return cleaned.isEmpty ? "Einheit" : cleaned
    }

    // MARK: Werte

    /// Streicht Wattangaben aus einer Überschrift („Neue Bestleistung: 5 min · 268 W“ → „Neue Bestleistung: 5 min“).
    public static func valueFree(_ headline: String) -> String {
        headline.replacingOccurrences(of: "\\s*[·:]\\s*\\d[\\d.,]*(\\s*→\\s*\\d[\\d.,]*)?\\s*W\\b", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func mentionsWatts(_ text: String) -> Bool { text.range(of: "\\d\\s*W\\b", options: .regularExpression) != nil }

    /// Überschrift fürs Bild: ohne Dienstnamen, Werte nur mit dem Schalter.
    public static func headline(for moment: Moment, showValues: Bool) -> String {
        neutral(showValues ? moment.headline : valueFree(moment.headline))
    }

    /// Unterzeile fürs Bild; Zeilen mit Wattangaben und die Pausen-Dauer („Nach 12 Tagen Pause …“) entfallen ohne den Schalter.
    public static func detail(for moment: Moment, showValues: Bool) -> String? {
        guard let detail = moment.detail, showValues || (!mentionsWatts(detail) && moment.kind != .comeback) else { return nil }
        let cleaned = neutral(detail)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Der Name aus dem Profil steht nur auf dem Bild, wenn der Nutzer „Namen zeigen“ einschaltet (Standard: aus).
    public static func shareName(_ profileName: String?, show: Bool) -> String? {
        guard show, let trimmed = profileName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: Begleittext

    /// Stufennummer eines Level-Moments (`level-4-2026`, `demo-level-4`); sonst nil.
    public static func levelNumber(of moment: Moment) -> Int? {
        guard moment.kind == .levelUp, let range = moment.id.range(of: "level-\\d+", options: .regularExpression) else { return nil }
        return Int(moment.id[range].dropFirst("level-".count))
    }

    /// „Gipfelmoment: Level 4 · Rollen-Routine – Etappe Stilfser Joch.“
    public static func caption(for moment: Moment, showValues: Bool) -> String {
        var text = "Gipfelmoment: \(headline(for: moment, showValues: showValues))"
        if let n = levelNumber(of: moment), n >= 1 {
            text += " – Etappe \(WinterJourney.stages[min(WinterJourney.stages.count, n) - 1].place)"
        }
        return text + "."
    }
}
