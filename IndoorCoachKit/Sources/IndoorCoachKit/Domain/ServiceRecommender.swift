import Foundation

// Empfehlungslogik der Einführung (docs/20-KONZEPT-ONBOARDING-DIENSTE.md, Abschnitt 5).
// Reine Funktionen: ohne SwiftUI, ohne AppModel, ohne Netzwerk. Die Antworten der Einführung gehen hinein,
// eine nach Stufen sortierte Liste mit je einem Nutzen-Satz kommt heraus.

// MARK: - Antworten

public enum RideApp: String, Codable, CaseIterable, Sendable { case myWhoosh, zwift, rouvy, other, none }
public enum RideDevice: String, Codable, CaseIterable, Sendable { case mac, windows, tablet, appleTV, phone, unknown }
public enum ExtraGear: String, Codable, CaseIterable, Sendable { case appleWatch, garminWahoo, heartStrap, strava, none }

/// Antworten der Einführung. Leere Mengen = keine Angabe.
public struct ServiceAnswers: Codable, Equatable, Sendable {
    public var rideApps: Set<RideApp> = []
    /// nil = nicht gefragt oder nicht beantwortet.
    public var myWhooshDevice: RideDevice?
    public var extras: Set<ExtraGear> = []
    /// „Ich kenne mich aus – alle Dienste zeigen“.
    public var showAll = false

    public init(rideApps: Set<RideApp> = [], myWhooshDevice: RideDevice? = nil, extras: Set<ExtraGear> = [], showAll: Bool = false) {
        self.rideApps = rideApps
        self.myWhooshDevice = myWhooshDevice
        self.extras = extras
        self.showAll = showAll
    }
}

/// Was auf diesem Gerät und in diesem Build überhaupt angeboten werden kann.
public struct ServiceAvailability: Equatable, Sendable {
    /// `intervalsConfig.isOAuthAvailable` (ohne Client-ID bleibt nur der API-Schlüssel, und der gehört nicht in die Einführung).
    public var intervalsOAuth: Bool
    /// `AppConfig.bridgeDownloadURL != nil` (E1).
    public var bridgeDownload: Bool
    /// `healthSource.isAvailable`.
    public var health: Bool

    public init(intervalsOAuth: Bool, bridgeDownload: Bool, health: Bool) {
        self.intervalsOAuth = intervalsOAuth
        self.bridgeDownload = bridgeDownload
        self.health = health
    }
}

// MARK: - Ergebnis

public enum RecommendationTier: Int, Codable, Comparable, Sendable {
    /// „Für dich passt“, oben, großer Verbinden-Knopf.
    case recommended = 0
    /// „Auch möglich“, sichtbar, kompakt.
    case optional = 1
    /// „Für Fortgeschrittene“, sichtbar, ohne Verbinden im Intro.
    case advanced = 2
    /// Eingeklappt unter „Alle Dienste“.
    case more = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum RecommendationReason: String, Codable, Sendable {
    case myWhooshPlansAndRides, bridgeMac, bridgeMaybeMac,
         intervalsZwift, intervalsRouvy, intervalsDevice, intervalsOther,
         healthWatch, healthGarmin, strapPulse, stravaAdvanced,
         fitOther, fitNoIntervals, catalog
}

public struct ServiceRecommendation: Identifiable, Equatable, Sendable {
    public let id: ConnectionID
    public let tier: RecommendationTier
    /// In Regelreihenfolge, ohne Dubletten.
    public let reasons: [RecommendationReason]
    /// Genau ein Satz (Abschnitt 5.5).
    public let benefit: String
    /// Zusatzhinweis, z. B. die Strava-Lücke bei intervals.icu.
    public let note: String?

    public init(id: ConnectionID, tier: RecommendationTier, reasons: [RecommendationReason], benefit: String, note: String? = nil) {
        self.id = id
        self.tier = tier
        self.reasons = reasons
        self.benefit = benefit
        self.note = note
    }
}

// MARK: - Logik

public enum ServiceRecommender {
    /// Mehr „Für dich passt“ wirkt wieder wie eine Liste aller Dienste (E6).
    public static let maxRecommended = 4

    /// Reihenfolge innerhalb einer Stufe: zuerst Pläne und Fahrten, dann Erholung, dann Geräte.
    static let order: [ConnectionID] = [.myWhoosh, .intervalsICU, .macBridge, .appleHealth, .strap, .fitImport, .strava]

    // MARK: Normalisierung (N1–N4)

    /// N1/N2: „Noch keine App“ und „Nichts davon“ weichen konkreten Angaben. N3: Ein Gerät ohne MyWhoosh gilt nicht.
    /// N4: `showAll` lässt die Antworten stehen (sie werden erst in `recommend` ignoriert).
    public static func normalized(_ answers: ServiceAnswers) -> ServiceAnswers {
        var result = answers
        if result.rideApps.count > 1 { result.rideApps.remove(.none) }
        if result.extras.count > 1 { result.extras.remove(.none) }
        if !result.rideApps.contains(.myWhoosh) { result.myWhooshDevice = nil }
        return result
    }

    /// Die Frage „Worauf läuft MyWhoosh bei dir?“ ändert heute nur die Empfehlung der Mac-Brücke.
    public static func asksDevice(_ answers: ServiceAnswers, _ availability: ServiceAvailability) -> Bool {
        answers.rideApps.contains(.myWhoosh) && availability.bridgeDownload && !answers.showAll
    }

    // MARK: Empfehlung

    public static func recommend(_ answers: ServiceAnswers, _ availability: ServiceAvailability) -> [ServiceRecommendation] {
        let a = normalized(answers)
        var hits: [ConnectionID: [Hit]] = [:]

        func add(_ id: ConnectionID, _ tier: RecommendationTier, _ reason: RecommendationReason, _ sentence: Sentence? = nil) {
            hits[id, default: []].append(Hit(tier: tier, reason: reason, part: sentence))
        }

        if a.showAll {
            // R15: alles, was es gibt, ohne Rangfolge; Strava bleibt „für Fortgeschrittene“.
            for id in order where isAvailable(id, availability) {
                if id == .strava { add(.strava, .advanced, .stravaAdvanced) } else { add(id, .optional, .catalog) }
            }
        } else {
            applyRules(a, availability, add)
        }

        // R16: jeder verfügbare Dienst ohne Treffer steht eingeklappt unter „Alle Dienste“.
        for id in order where hits[id] == nil && isAvailable(id, availability) { add(id, .more, .catalog) }

        var result: [ServiceRecommendation] = order.compactMap { id in
            guard let list = hits[id], let tier = list.map(\.tier).min() else { return nil }
            var reasons: [RecommendationReason] = []
            for hit in list where !reasons.contains(hit.reason) { reasons.append(hit.reason) }
            return ServiceRecommendation(id: id, tier: tier, reasons: reasons, benefit: benefit(for: id, reasons: reasons, hits: list),
                                         note: note(for: id, answers: a, availability: availability))
        }

        // Obergrenze: weitere Empfehlungen rutschen in der Reihenfolge nach „Auch möglich“.
        var recommended = 0
        result = result.map { entry in
            guard entry.tier == .recommended else { return entry }
            recommended += 1
            guard recommended > maxRecommended else { return entry }
            return ServiceRecommendation(id: entry.id, tier: .optional, reasons: entry.reasons, benefit: entry.benefit, note: entry.note)
        }
        return result.enumerated().sorted { l, r in
            (l.element.tier, l.offset) < (r.element.tier, r.offset)
        }.map(\.element)
    }

    // MARK: Regeln R1–R13

    private static func applyRules(_ a: ServiceAnswers, _ availability: ServiceAvailability,
                                   _ add: (ConnectionID, RecommendationTier, RecommendationReason, Sentence?) -> Void) {
        let myWhoosh = a.rideApps.contains(.myWhoosh)
        if myWhoosh { add(.myWhoosh, .recommended, .myWhooshPlansAndRides, nil) }                       // R1
        if myWhoosh && availability.bridgeDownload {
            switch a.myWhooshDevice {
            case .mac?: add(.macBridge, .recommended, .bridgeMac, nil)                                  // R2
            case nil, .unknown?: add(.macBridge, .optional, .bridgeMaybeMac, nil)                       // R3
            default: break                                                                              // andere Geräte: nur R16
            }
        }
        if availability.intervalsOAuth {
            if a.rideApps.contains(.zwift) { add(.intervalsICU, .recommended, .intervalsZwift, .target("in Zwift")) }             // R4
            if a.rideApps.contains(.rouvy) { add(.intervalsICU, .recommended, .intervalsRouvy, .target("in Rouvy")) }             // R5
            if a.extras.contains(.garminWahoo) {                                                                                   // R6
                add(.intervalsICU, .optional, .intervalsDevice, .target("auf deinem Garmin- oder Wahoo-Radcomputer"))
            }
            if a.rideApps.contains(.other) { add(.intervalsICU, .optional, .intervalsOther, nil) }                                // R7
        }
        if a.rideApps.contains(.other) { add(.fitImport, .optional, .fitOther, .source("deiner App")) }                         // R7b
        if availability.health {
            if a.extras.contains(.appleWatch) { add(.appleHealth, .recommended, .healthWatch, nil) }                            // R8
            if a.extras.contains(.garminWahoo) { add(.appleHealth, .recommended, .healthGarmin, nil) }                          // R9
        }
        if a.extras.contains(.heartStrap) { add(.strap, .recommended, .strapPulse, nil) }                                       // R10
        if a.extras.contains(.strava) { add(.strava, .advanced, .stravaAdvanced, nil) }                                         // R11
        if !availability.intervalsOAuth {                                                                                       // R13
            if a.rideApps.contains(.zwift) { add(.fitImport, .optional, .fitNoIntervals, .source("Zwift")) }
            if a.rideApps.contains(.rouvy) { add(.fitImport, .optional, .fitNoIntervals, .source("Rouvy")) }
        }
    }

    private static func isAvailable(_ id: ConnectionID, _ availability: ServiceAvailability) -> Bool {
        switch id {
        case .intervalsICU: availability.intervalsOAuth
        case .macBridge: availability.bridgeDownload
        case .appleHealth: availability.health
        case .myWhoosh, .strap, .fitImport, .strava: true
        }
    }

    // MARK: Texte (Abschnitt 5.5)

    /// Baustein eines Satzes: intervals.icu-Ziel („in Zwift“) oder Quelle einer Datei („Zwift“).
    private enum Sentence { case target(String), source(String) }
    private struct Hit { var tier: RecommendationTier; var reason: RecommendationReason; var part: Sentence? }

    private static func benefit(for id: ConnectionID, reasons: [RecommendationReason], hits: [Hit]) -> String {
        switch id {
        case .myWhoosh:
            return "Deine Einheiten landen automatisch in MyWhoosh, deine Fahrten kommen von dort zurück."
        case .macBridge:
            if !reasons.contains(.bridgeMac), reasons.contains(.bridgeMaybeMac) {
                return "Falls MyWhoosh auf einem Mac läuft: jede Fahrt im Detail, ganz automatisch."
            }
            return "Jede Fahrt im Detail: Watt und Puls für jede Sekunde, ohne dass du etwas tun musst."
        case .intervalsICU:
            let targets = hits.compactMap { hit -> String? in if case .target(let text)? = hit.part { text } else { nil } }
            if !targets.isEmpty { return "Damit landen deine Einheiten automatisch \(Formatters.germanList(targets))." }
            if reasons.contains(.intervalsOther) {
                return "Viele Trainings-Apps schicken Fahrten an intervals.icu – dann kommen sie auch hierher."
            }
            return "Kostenloser Trainingskalender: schickt deine Einheiten an Zwift, Rouvy, Garmin oder Wahoo."
        case .appleHealth:
            switch (reasons.contains(.healthWatch), reasons.contains(.healthGarmin)) {
            case (true, true):
                return "Ruhepuls, Schlaf und Workouts deiner Apple Watch zeigen dem Coach, wie erholt du bist – dazu kommen Workouts aus Garmin Connect."
            case (false, true):
                return "Workouts aus Garmin Connect kommen über Apple Health auch hierher."
            case (true, false):
                return "Ruhepuls, Schlaf und Workouts deiner Apple Watch zeigen dem Coach, wie erholt du bist."
            default:
                return "Erholung und Workouts aus der Health-App."
            }
        case .strap:
            return "Dein Puls bei Krafttraining und Morgenmessung, direkt in der App, auch ohne Uhr."
        case .fitImport:
            let sources = hits.compactMap { hit -> String? in if case .source(let text)? = hit.part { text } else { nil } }
            if !sources.isEmpty { return "Fahrten als Datei aus \(Formatters.germanList(sources, conjunction: "oder")) übernehmen." }
            return "Fahrten als Datei aus jeder Trainings-App übernehmen."
        case .strava:
            return "Braucht eine eigene Strava-Entwickler-App und seit Juni 2026 ein Strava-Abo; einrichten kannst du es nach der Einführung."
        }
    }

    /// R12: Wer Zwift oder Rouvy fährt und Strava nutzt, muss das Spiel direkt mit intervals.icu verbinden.
    private static func note(for id: ConnectionID, answers a: ServiceAnswers, availability: ServiceAvailability) -> String? {
        guard id == .intervalsICU, !a.showAll, availability.intervalsOAuth, a.extras.contains(.strava) else { return nil }
        var apps: [String] = []
        if a.rideApps.contains(.zwift) { apps.append("Zwift") }
        if a.rideApps.contains(.rouvy) { apps.append("Rouvy") }
        guard !apps.isEmpty else { return nil }
        return "Wichtig: Verbinde \(Formatters.germanList(apps)) in intervals.icu direkt. Fahrten, die nur über Strava ankommen, gibt intervals.icu nicht weiter."
    }
}
