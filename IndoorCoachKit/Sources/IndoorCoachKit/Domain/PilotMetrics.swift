import Foundation

/// Pilot-Kennzahlen für den Diagnose-Export (docs/17 §7.1 Ziele Z1–Z6, B58): nur Zähler und Quoten, nie Werte
/// (kein Puls, kein Gewicht, keine Namen, kein Freitext). Die Berechnung ist rein; `AppModel+Diagnostics` füllt die Eingabe.
public struct PilotMetrics: Sendable {
    public enum OfferKind: String, CaseIterable, Sendable {
        case shorten, easier, swap, joker

        public var label: String {
            switch self {
            case .shorten: "kürzer"
            case .easier: "leichter"
            case .swap: "tauschen"
            case .joker: "Joker"
            }
        }

        init(_ action: CheckIn.Action) {
            switch action {
            case .shorten: self = .shorten
            case .easier: self = .easier
            case .swapToBase: self = .swap
            case .joker: self = .joker
            }
        }
    }

    public struct Offer: Equatable, Sendable {
        public var shown = 0
        public var accepted = 0
    }

    public struct CheckInRecord: Sendable {
        public var skipped: Bool
        public var offered: [CheckIn.Action]
        public var chosen: CheckIn.Action?
    }

    public struct WorkoutRecord: Sendable {
        public var status: WorkoutStatus
        /// Über „Anpassen“ oder „Gegen Grundlage tauschen“ verändert.
        public var adjusted: Bool
    }

    public struct StrengthRecord: Sendable {
        public var hasExertion: Bool
        public var hasLegShare: Bool
    }

    public struct Feedback: Equatable, Sendable {
        public var up: Int
        public var down: Int
    }

    public struct Input: Sendable {
        public var checkIns: [CheckInRecord] = []
        public var workouts: [WorkoutRecord] = []
        /// Aufwärm-Checks, bei denen ein Block gefunden wurde (gültig oder nicht).
        public var warmupChecks: [WarmupCheck] = []
        /// Lückensekunden je iPhone-Aufzeichnung (angehängte und wartende).
        public var recordingGapSeconds: [Int] = []
        public var strength: [StrengthRecord] = []
        public var healthImported = 0
        public var healthMerged = 0
        public var guardShadowHits = 0
        public var guardShadowDays = 0
        /// nil = es gibt (noch) keine Plan-Rückmeldung in der App.
        public var planFeedback: Feedback?
        public var claudeConsent = false
    }

    /// Lücken länger als so viele Sekunden zählen (Z5).
    public static let gapThresholdSeconds = 30

    public var checkIns = 0
    public var checkInsSkipped = 0
    public var offers: [OfferKind: Offer] = [:]
    public var notAsPlanned = 0
    public var adjusted = 0
    public var warmupTotal = 0
    public var warmupUsable = 0
    public var recordings = 0
    public var recordingsWithGap = 0
    public var strengthTotal = 0
    public var strengthComplete = 0
    public var input = Input()

    /// Anteil „angepasst“ an nicht wie geplant gefahrenen Einheiten (Z1); nil ohne solche Einheiten.
    public var adjustedShare: Double? { notAsPlanned > 0 ? Double(adjusted) / Double(notAsPlanned) : nil }

    public static func compute(_ input: Input) -> PilotMetrics {
        var m = PilotMetrics()
        m.input = input
        m.checkIns = input.checkIns.count
        m.checkInsSkipped = input.checkIns.filter(\.skipped).count
        for kind in OfferKind.allCases { m.offers[kind] = Offer() }
        for record in input.checkIns {
            for kind in Set(record.offered.map(OfferKind.init)) { m.offers[kind, default: Offer()].shown += 1 }
            if let chosen = record.chosen { m.offers[OfferKind(chosen), default: Offer()].accepted += 1 }
        }
        // Nicht wie geplant: ausgelassen oder verändert und gefahren; geplante (offene) Einheiten zählen nicht.
        m.notAsPlanned = input.workouts.filter { $0.status == .skipped || ($0.status == .done && $0.adjusted) }.count
        m.adjusted = input.workouts.filter { $0.adjusted && $0.status != .planned }.count
        m.warmupTotal = input.warmupChecks.count
        m.warmupUsable = input.warmupChecks.filter(\.valid).count
        m.recordings = input.recordingGapSeconds.count
        m.recordingsWithGap = input.recordingGapSeconds.filter { $0 > gapThresholdSeconds }.count
        m.strengthTotal = input.strength.count
        m.strengthComplete = input.strength.filter { $0.hasExertion && $0.hasLegShare }.count
        return m
    }

    /// Abschnitt für den Export, eine Zeile je Kennzahl; fehlende Quellen (Plan-Feedback) entfallen.
    public var lines: [String] {
        var out = ["== Pilot-Kennzahlen =="]
        out.append("Check-ins gesamt: \(checkIns) (übersprungen \(checkInsSkipped))")
        let offerText = OfferKind.allCases.map { kind -> String in
            let o = offers[kind] ?? Offer()
            return "\(kind.label) \(o.shown)/\(o.accepted)"
        }.joined(separator: ", ")
        out.append("Angebote gezeigt/angenommen: \(offerText)")
        if let share = adjustedShare {
            out.append("Angepasst an nicht wie geplant gefahrenen Einheiten: \(adjusted) von \(notAsPlanned) (\(Int((share * 100).rounded())) %)")
        } else {
            out.append("Angepasst an nicht wie geplant gefahrenen Einheiten: keine solchen Einheiten")
        }
        out.append("Aufwärm-Checks auswertbar: \(warmupUsable) von \(warmupTotal)")
        out.append("iPhone-Aufzeichnungen: \(recordings) gesamt, \(recordingsWithGap) mit Lücke über \(Self.gapThresholdSeconds) s")
        out.append("Krafteinheiten: \(strengthTotal) gesamt, \(strengthComplete) mit Härte und Beinen")
        out.append("Health-Workouts: \(input.healthImported) importiert, \(input.healthMerged) zusammengeführt")
        out.append("Trend-Wächter: sichtbar nicht erfasst, Schatten \(input.guardShadowHits) Treffer an \(input.guardShadowDays) Tagen")
        if let feedback = input.planFeedback { out.append("Plan-Feedback: \(feedback.up) positiv, \(feedback.down) negativ") }
        out.append("Claude-Einwilligung: \(input.claudeConsent ? "ja" : "nein")")
        return out
    }
}
