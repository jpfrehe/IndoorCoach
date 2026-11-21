import Foundation

// Postkarten von der Alpenüberquerung (docs/22, B2) – AP0: Signatur und Platzhaltertexte. Agent B füllt Texte,
// Szene, Album und Teilen. Das Ankunftsdatum kommt aus `Trophies.levelDates`, es gibt keine neue Speicherung.

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
    /// Alle zehn Karten. Auf Level n sind 1…n frei (Garmisch immer), die Karte n+1 trägt die Prozentangabe.
    /// - Parameters:
    ///   - level: Winter-Arc-Level (wird auf 1…10 begrenzt).
    ///   - levelProgress: 0…1 innerhalb des Levels.
    ///   - levelDates: Tag je Level (`Trophies.levelDates`).
    public static func all(level: Int, levelProgress: Double, levelDates: [Int: Date]) -> [Postcard] {
        let current = min(WinterJourney.stages.count, max(1, level))
        let percent = Int((min(1, max(0, levelProgress)) * 100).rounded())
        return WinterJourney.stages.map { stage in
            let unlocked = stage.number <= current
            return Postcard(stage: stage.number, place: stage.place, elevation: stage.elevation,
                            text: placeholderText(for: stage.place), unlocked: unlocked,
                            arrivedOn: unlocked ? levelDates[stage.number] : nil,
                            percentToNext: stage.number == current + 1 ? 100 - percent : nil)
        }
    }

    /// Platzhalter bis AP4 (die echten Texte stehen in docs/22 §B2).
    static func placeholderText(for place: String) -> String { "Grüße aus \(place)." }
}
