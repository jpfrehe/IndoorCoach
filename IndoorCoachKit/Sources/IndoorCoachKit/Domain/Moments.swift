import Foundation

// Gipfelmomente (docs/22, B1) – AP0: nur Typen und Ledger-Logik. Erkennung (`MomentDetector`), Coach-Notiz und UI
// kommen von Agent A. Alles rein lokal, nichts davon verlässt das Gerät.

/// Ein einzelner Moment, der nach einer Fahrt gefeiert wird („Level 4 · Rollen-Routine“, „Neue Bestleistung: 5 min“).
public struct Moment: Codable, Equatable, Sendable, Identifiable {
    /// Moment-Arten in der Reihenfolge ihrer Priorität (wichtigste zuerst, docs/22 §B1).
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case levelUp, record, ftpRise, challengeCompleted, comeback, streak, firstRide, weekPlanDone, strengthTier, secondData

        /// Je größer, desto wichtiger (`levelUp` 10 … `secondData` 1).
        public var priority: Int {
            switch self {
            case .levelUp: 10
            case .record: 9
            case .ftpRise: 8
            case .challengeCompleted: 7
            case .comeback: 6
            case .streak: 5
            case .firstRide: 4
            case .weekPlanDone: 3
            case .strengthTier: 2
            case .secondData: 1
            }
        }
    }

    /// Stabile IDs (docs/22 §B1): dieselbe ID erscheint nie zweimal. `season` ist der Saison-Schlüssel (z. B. „2026“),
    /// `rideID` die `RideSummary.id`, `start` der Wochenstart als `yyyy-MM-dd`.
    public enum Key {
        public static func level(_ n: Int, season: String) -> String { "level-\(n)-\(season)" }
        public static func record(duration seconds: Int, rideID: Int) -> String { "record-\(seconds)-\(rideID)" }
        public static func ftp(_ watts: Int, season: String) -> String { "ftp-\(watts)-\(season)" }
        public static func challenge(_ id: String) -> String { "challenge-\(id)" }
        public static func comeback(rideID: Int) -> String { "comeback-\(rideID)" }
        public static func streak(_ weeks: Int, season: String) -> String { "streak-\(weeks)-\(season)" }
        public static func firstRide(season: String) -> String { "first-\(season)" }
        public static func week(start: String) -> String { "week-\(start)" }
        public static func strength(_ tier: Int, season: String) -> String { "strength-\(tier)-\(season)" }
        public static let secondsFirst = "seconds-first"
    }

    public var id: String
    public var kind: Kind
    /// Wann das Ereignis stattfand (Frische-Regel: höchstens 72 h alt).
    public var date: Date
    public var headline: String
    /// Unterzeile bzw. Detailtext („+7 W gegenüber deiner bisherigen Bestleistung“).
    public var detail: String?
    /// Fahrt, zu der der Moment gehört (für „Gipfelmoment dieser Fahrt ansehen“).
    public var rideID: Int?

    public init(id: String, kind: Kind, date: Date, headline: String, detail: String? = nil, rideID: Int? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.headline = headline
        self.detail = detail
        self.rideID = rideID
    }

    public var priority: Int { kind.priority }
}

/// Ergebnis einer Auswertung: höchstens ein Gipfelmoment mit bis zu 3 Teil-Momenten, der Rest wird still als gesehen
/// markiert.
public struct MomentBatch: Equatable, Sendable {
    public static let maxMoments = 3
    public static let empty = MomentBatch([])

    /// Die gefeierten Teil-Momente, wichtigste zuerst (bei gleicher Art das neueste zuerst).
    public let moments: [Moment]
    /// Alles, was über die Obergrenze hinausging – nicht gefeiert, aber als gesehen zu vermerken.
    public let overflow: [Moment]

    public init(_ candidates: [Moment]) {
        let sorted = candidates.sorted {
            $0.priority != $1.priority ? $0.priority > $1.priority : $0.date > $1.date
        }
        moments = Array(sorted.prefix(Self.maxMoments))
        overflow = Array(sorted.dropFirst(Self.maxMoments))
    }

    public var headline: Moment? { moments.first }
    public var isEmpty: Bool { moments.isEmpty }
    /// IDs aller Momente der Auswertung (gefeiert und übersprungen), zum Eintragen ins Ledger.
    public var allIDs: [String] { (moments + overflow).map(\.id) }
}

/// Gedächtnis der Momente (UserDefaults `moments.ledger`, JSON): gesehene IDs (höchstens 500, die ältesten fallen
/// heraus), ob die Erstauswertung gelaufen ist, zuletzt gefeierte eFTP und die letzten Coach-Notiz-Regeln.
public struct MomentLedger: Codable, Equatable, Sendable {
    public static let defaultsKey = "moments.ledger"
    public static let maxSeen = 500
    /// Abwechslung der Coach-Notiz: dieselbe Regel höchstens 1× in 3 aufeinanderfolgenden Notizen.
    public static let noteWindow = 3

    /// Gesehene IDs, die ältesten zuerst.
    public private(set) var seenIDs: [String]
    /// false bis zur Erstauswertung (Neuinstallation, erster Import): dann werden verdiente IDs still markiert.
    public var isInitialized: Bool
    /// eFTP des letzten gefeierten Sprungs (Basis für `ftpRise`).
    public var lastCelebratedFTP: Int?
    /// Regel-IDs der letzten Coach-Notizen, die älteste zuerst (höchstens `noteWindow`).
    public private(set) var recentNoteRules: [String]

    public init() {
        seenIDs = []
        isInitialized = false
        lastCelebratedFTP = nil
        recentNoteRules = []
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seenIDs = try c.decodeIfPresent([String].self, forKey: .seenIDs) ?? []
        isInitialized = try c.decodeIfPresent(Bool.self, forKey: .isInitialized) ?? false
        lastCelebratedFTP = try c.decodeIfPresent(Int.self, forKey: .lastCelebratedFTP)
        recentNoteRules = try c.decodeIfPresent([String].self, forKey: .recentNoteRules) ?? []
    }

    public func hasSeen(_ id: String) -> Bool { seenIDs.contains(id) }

    public mutating func markSeen(_ id: String) {
        guard !seenIDs.contains(id) else { return }
        seenIDs.append(id)
        if seenIDs.count > Self.maxSeen { seenIDs.removeFirst(seenIDs.count - Self.maxSeen) }
    }

    public mutating func markSeen(_ ids: [String]) { ids.forEach { markSeen($0) } }

    public func canUseNoteRule(_ rule: String) -> Bool { !recentNoteRules.contains(rule) }

    public mutating func recordNoteRule(_ rule: String) {
        recentNoteRules.append(rule)
        if recentNoteRules.count > Self.noteWindow { recentNoteRules.removeFirst(recentNoteRules.count - Self.noteWindow) }
    }

    public mutating func removeAll() { self = MomentLedger() }

    // MARK: Persistence

    /// Fehlt der Eintrag oder ist er unlesbar, beginnt ein leeres Ledger (Erstauswertung).
    public static func load(from defaults: UserDefaults) -> MomentLedger {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(MomentLedger.self, from: $0) } ?? MomentLedger()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
