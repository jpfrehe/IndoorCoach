import Foundation

// Postkarten von der Alpenüberquerung (docs/22, B2): zehn eigene Karten, eine je Etappe der `WinterJourney`. Das
// Ankunftsdatum kommt aus `Trophies.levelDates`, es gibt keine neue Speicherung. Keine Fotos, keine Ortung, keine Werte.

/// Eine Karte je Etappe der `WinterJourney`.
public struct Postcard: Equatable, Identifiable, Sendable {
    /// Etappennummer 1…10.
    public var stage: Int
    public var place: String
    /// Höhe in Metern.
    public var elevation: Int
    public var text: String
    public var unlocked: Bool
    /// Tag des Aufstiegs auf diese Stufe; nil, wenn gesperrt oder unbekannt.
    public var arrivedOn: Date?
    /// Nur an der nächsten gesperrten Karte: wie viel Prozent der laufenden Stufe noch fehlen („Noch 38 % bis Bormio“).
    public var percentToNext: Int?

    public var id: Int { stage }

    public init(stage: Int, place: String, elevation: Int, text: String, unlocked: Bool, arrivedOn: Date? = nil,
                percentToNext: Int? = nil) {
        self.stage = stage
        self.place = place
        self.elevation = elevation
        self.text = text
        self.unlocked = unlocked
        self.arrivedOn = arrivedOn
        self.percentToNext = percentToNext
    }
}

public enum Postcards {
    /// Die zehn Kartentexte aus docs/22 §B2 (Du-Form, höchstens 160 Zeichen, keine Marken), in Etappenreihenfolge.
    static let texts: [String] = [
        "Start in Garmisch. Die Zugspitze schaut zu, der Winter fängt gerade erst an. Der erste Tritt ist der schwerste, und der liegt hinter dir.",
        "Grüße vom Fernpass. Unten glitzern die Seen. Du rollst ruhig und gleichmäßig. Genau so gewinnt man einen Winter.",
        "Am Reschensee schaut ein Kirchturm aus dem Eis. Hier oben ist es kalt, aber deine Beine sind warm.",
        "48 Kehren, 2757 Meter: das Dach deiner Reise. Ab hier geht es dem Frühling entgegen.",
        "Bormio, die Thermen dampfen. Halbzeit. Und ab der Wintersonnenwende werden die Tage wieder länger.",
        "Über Aprica blinzelt die Sonne jeden Tag ein bisschen länger hinter den Gipfeln hervor.",
        "In Edolo tropft es von den Dächern. Tauwetter in den Bergen und in deinen Beinen.",
        "Der Passo Crocedomini: einsam, steil, ehrlich. Hier zeigt sich, was der Winter gebracht hat.",
        "Am Idrosee riecht es schon nach Frühling. Nur noch eine Etappe.",
        "Riva am Gardasee. Zitronenbäume, Wasser, Sonne. Du bist angekommen, in Frühlingsform.",
    ]

    /// Grußzeile fürs Teilen („Grüße vom Stilfser Joch“), je Etappe.
    static let greetings: [String] = [
        "Grüße aus Garmisch", "Grüße vom Fernpass", "Grüße vom Reschensee", "Grüße vom Stilfser Joch", "Grüße aus Bormio",
        "Grüße aus Aprica", "Grüße aus Edolo", "Grüße vom Passo Crocedomini", "Grüße vom Idrosee", "Grüße vom Gardasee",
    ]

    /// Alle zehn Karten. Auf Level n sind 1…n frei (Garmisch immer), die Karte n+1 trägt die Prozentangabe.
    /// - Parameters:
    ///   - level: Winter-Arc-Level (wird auf 1…10 begrenzt).
    ///   - levelProgress: 0…1 innerhalb des Levels.
    ///   - levelDates: Tag je Level (`Trophies.levelDates`).
    public static func all(level: Int, levelProgress: Double, levelDates: [Int: Date]) -> [Postcard] {
        let current = min(WinterJourney.stages.count, max(1, level))
        let progress = levelProgress.isNaN ? 0 : min(1, max(0, levelProgress))
        let percent = Int((progress * 100).rounded())
        return WinterJourney.stages.map { stage in
            let unlocked = stage.number <= current
            return Postcard(stage: stage.number, place: stage.place, elevation: stage.elevation,
                            text: texts[stage.number - 1], unlocked: unlocked,
                            arrivedOn: unlocked ? levelDates[stage.number] : nil,
                            // Nie „Noch 0 %“, solange die Karte noch gesperrt ist.
                            percentToNext: stage.number == current + 1 ? max(1, 100 - percent) : nil)
        }
    }

    // MARK: Teilen

    public static func greeting(for stage: Int) -> String {
        greetings[min(greetings.count, max(1, stage)) - 1]
    }

    /// „Grüße vom Stilfser Joch. Etappe 4 von 10 meiner Winter-Alpenüberquerung.“ – ohne Werte.
    public static func shareText(for card: Postcard) -> String {
        "\(greeting(for: card.stage)). Etappe \(card.stage) von \(WinterJourney.stages.count) meiner Winter-Alpenüberquerung."
    }

    // MARK: Album

    public static func unlockedCount(in cards: [Postcard]) -> Int { cards.filter(\.unlocked).count }

    /// „Deine Postkarten · 4 von 10“.
    public static func albumTitle(_ cards: [Postcard]) -> String {
        "Deine Postkarten · \(unlockedCount(in: cards)) von \(cards.count)"
    }

    /// „Noch 38 % bis Bormio“ oder, wenn alles gesammelt ist, der Abschluss.
    public static func albumSubtitle(_ cards: [Postcard]) -> String {
        if let next = cards.first(where: { $0.percentToNext != nil }) { return lockedCaption(next) }
        if cards.allSatisfy(\.unlocked) { return "Alle zehn Karten gesammelt: Du bist am Gardasee." }
        return "Noch nicht erreicht"
    }

    /// Unter einer gesperrten Karte: nur die nächste nennt den Prozentwert (Goal Gradient).
    public static func lockedCaption(_ card: Postcard) -> String {
        guard let percent = card.percentToNext else { return "Noch nicht erreicht" }
        return "Noch \(percent) % bis \(card.place)"
    }

    // MARK: Lesen und Beschriften

    /// VoiceOver liest die Karte als ein Element: Ort, Höhe, Ankunft, Text. Die Illustration ist dekorativ.
    public static func accessibilityLabel(_ card: Postcard, calendar: Calendar = .current) -> String {
        guard card.unlocked else { return shortAccessibilityLabel(card, calendar: calendar) }
        return shortAccessibilityLabel(card, calendar: calendar) + " Text: \(card.text)"
    }

    /// Ohne den Kartentext: für die Kacheln im Album („Postkarte, Etappe 4 von 10, Stilfser Joch, …, angekommen am 18. Dezember.“).
    public static func shortAccessibilityLabel(_ card: Postcard, calendar: Calendar = .current) -> String {
        let head = "Postkarte, Etappe \(card.stage) von \(WinterJourney.stages.count), \(card.place)"
        guard card.unlocked else {
            guard let percent = card.percentToNext else { return head + ". Noch nicht erreicht." }
            return head + ". Noch nicht erreicht, noch \(percent) Prozent bis \(card.place)."
        }
        var spoken = head + ", \(card.elevation) Meter"
        if let arrived = card.arrivedOn { spoken += ", angekommen am " + longDate(arrived, calendar: calendar) }
        return spoken + "."
    }

    /// Poststempel „18. DEZ. 2026“; nil ohne bekanntes Ankunftsdatum (es wird keins erfunden).
    public static func postmarkDate(_ card: Postcard, calendar: Calendar = .current) -> String? {
        guard card.unlocked, let arrived = card.arrivedOn else { return nil }
        return dateStyle(calendar).day().month(.abbreviated).year().format(arrived).uppercased()
    }

    /// Briefmarke: „Etappe 4/10“.
    public static func stampLabel(_ card: Postcard) -> String { "Etappe \(card.stage)/\(WinterJourney.stages.count)" }

    // MARK: Dein Warum auf der letzten Karte

    /// Nur die Gardasee-Karte zeigt den Satz des Fahrers, und erst, wenn sie freigeschaltet ist.
    public static func showsWhy(_ card: Postcard) -> Bool { card.unlocked && card.stage == WinterJourney.stages.count }

    /// „Dein Satz vom 4. November: „…““ – wörtlich, nur lokal; nil ohne Satz.
    public static func whyAddendum(note: String?, savedOn: Date?, calendar: Calendar = .current) -> String? {
        guard let sentence = WhyNote.normalize(note) else { return nil }
        guard let savedOn else { return "Dein Satz: \(WhyNote.quote(sentence))" }
        return "Dein Satz vom \(dayMonth(savedOn, calendar: calendar)): \(WhyNote.quote(sentence))"
    }

    // MARK: Datum

    private static func dateStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: Locale.de, calendar: calendar, timeZone: calendar.timeZone)
    }

    static func dayMonth(_ date: Date, calendar: Calendar) -> String { dateStyle(calendar).day().month(.wide).format(date) }
    static func longDate(_ date: Date, calendar: Calendar) -> String { dayMonth(date, calendar: calendar) }
}
