import Foundation

/// Trend-Wächter (docs/17 §6.1 P2/P3, §9.7; B55): erkennt, dass die Werte seit ein paar Tagen von der eigenen Basis
/// abweichen, und bietet dann – nur vor einer harten Einheit – sanfte Angebote an. Keine Diagnose, kein Push, nie
/// automatisch etwas ändern. Reine Regeln ohne Zustand.
public enum TrendGuard {
    public enum Variant: String, Equatable, Codable, Sendable {
        /// Ruhepuls-Abweichung plus ein zweites Signal.
        case restingHR
        /// S0 ohne Ruhepuls: zwei negative Check-ins und ein erhöhter Aufwärm-Puls.
        case withoutRestingHR
    }

    public enum Reason: String, Equatable, Codable, Sendable, CaseIterable {
        case restingHR, negativeCheckIn, infectionTag, respiratoryRate, wristTemperature, hrv, morningHRV
        case repeatedNegativeCheckIns, warmupHR
    }

    public enum Result: Equatable, Sendable {
        case quiet
        case triggered(variant: Variant, reasons: [Reason])

        public var isTriggered: Bool { if case .triggered = self { true } else { false } }
        public var reasons: [Reason] { if case .triggered(_, let r) = self { r } else { [] } }
    }

    public struct Input: Sendable {
        public var restingHR: WellnessTrend?
        public var respiratoryRate: WellnessTrend?
        public var wristTemperature: WellnessTrend?
        public var hrv: WellnessTrend?
        /// Die HRV-Quelle ist die Apple Watch und gepinnt (andere Quellen sind für SDNN nicht vergleichbar).
        public var hrvWatchPinned: Bool
        public var lastCheckInNegative: Bool
        public var lastCheckInInfection: Bool
        /// Negative Check-ins der letzten 3 Tage (S0).
        public var negativeCheckIns3Days: Int
        /// Letzter Aufwärm-Puls minus Median der früheren (bpm); nil ohne genug Checks.
        public var warmupDeltaBpm: Double?
        /// Morgen-HRV-Signal aus einem späteren Paket; nil = unbekannt.
        public var morningHRVSignal: Bool?

        public init(restingHR: WellnessTrend? = nil, respiratoryRate: WellnessTrend? = nil, wristTemperature: WellnessTrend? = nil,
                    hrv: WellnessTrend? = nil, hrvWatchPinned: Bool = false, lastCheckInNegative: Bool = false,
                    lastCheckInInfection: Bool = false, negativeCheckIns3Days: Int = 0, warmupDeltaBpm: Double? = nil,
                    morningHRVSignal: Bool? = nil) {
            self.restingHR = restingHR
            self.respiratoryRate = respiratoryRate
            self.wristTemperature = wristTemperature
            self.hrv = hrv
            self.hrvWatchPinned = hrvWatchPinned
            self.lastCheckInNegative = lastCheckInNegative
            self.lastCheckInInfection = lastCheckInInfection
            self.negativeCheckIns3Days = negativeCheckIns3Days
            self.warmupDeltaBpm = warmupDeltaBpm
            self.morningHRVSignal = morningHRVSignal
        }
    }

    // MARK: Parameter

    /// Ruhepuls: 3-Tage-Mittel ≥ Basis + max(5 bpm, 2 × MAD).
    public static let restingHRMinRise = 5.0
    public static let restingHRMADFactor = 2.0
    public static let respiratoryRise = 1.5
    public static let wristTemperatureRise = 0.5
    public static let warmupRise = 5.0
    public static let s0NegativeCheckIns = 2
    /// Gleiche Toleranz für Gleitkomma-Vergleiche an der Grenze.
    private static let epsilon = 1e-9

    // MARK: Regeln

    public static func evaluate(_ input: Input) -> Result {
        if let rhr = input.restingHR, rhr.isReady {
            guard let mean = rhr.mean3, let base = rhr.baseline else { return .quiet }
            let rise = max(restingHRMinRise, restingHRMADFactor * (rhr.mad ?? 0))
            guard mean >= base + rise - epsilon else { return .quiet }
            var reasons: [Reason] = [.restingHR]
            let second = secondSignals(input)
            guard !second.isEmpty else { return .quiet }
            reasons += second
            return .triggered(variant: .restingHR, reasons: reasons)
        }
        // S0: kein verwertbarer Ruhepuls.
        if input.negativeCheckIns3Days >= s0NegativeCheckIns, let delta = input.warmupDeltaBpm, delta >= warmupRise - epsilon {
            return .triggered(variant: .withoutRestingHR, reasons: [.repeatedNegativeCheckIns, .warmupHR])
        }
        return .quiet
    }

    private static func secondSignals(_ input: Input) -> [Reason] {
        var out: [Reason] = []
        if input.lastCheckInNegative { out.append(.negativeCheckIn) }
        if input.lastCheckInInfection { out.append(.infectionTag) }
        if let t = input.respiratoryRate, t.isReady, let m = t.mean3, let b = t.baseline, m >= b + respiratoryRise - epsilon {
            out.append(.respiratoryRate)
        }
        if let t = input.wristTemperature, t.isReady, let m = t.mean3, let b = t.baseline, m >= b + wristTemperatureRise - epsilon {
            out.append(.wristTemperature)
        }
        if input.hrvWatchPinned, let t = input.hrv, t.isReady, let m = t.lnMean7, let b = t.lnBaseline, let sd = t.lnSD,
           m < b - sd - epsilon {
            out.append(.hrv)
        }
        if input.morningHRVSignal == true { out.append(.morningHRV) }
        return out
    }

    /// Letzter gültiger Aufwärm-Puls (bei `refWatts`) minus Median der früheren; nil ohne mindestens
    /// `WarmupCheck.minChecksForTrend` frühere Messungen. Nur gemessene Werte: „angenommen (ERG)“ ist keine Messung.
    public static func warmupDelta(checks: [WarmupCheck], refWatts: Int) -> Double? {
        let used = checks.filter { $0.valid && $0.hrMean != nil && $0.refWatts == refWatts && $0.source == .measured }.sorted { $0.date < $1.date }
        guard let last = used.last?.hrMean else { return nil }
        let earlier = used.dropLast().compactMap(\.hrMean)
        guard earlier.count >= WarmupCheck.minChecksForTrend, let median = Wellness.median(earlier) else { return nil }
        return last - median
    }

    /// Nur vor harten Einheiten meldet sich der Wächter.
    public static func isHard(_ type: WorkoutType) -> Bool {
        switch type {
        case .vo2max, .threshold, .anaerobic, .sweetSpot: true
        case .recovery, .endurance, .tempo, .sprint, .test, .mixed: false
        }
    }

    // MARK: Texte (ohne Diagnose)

    public static let cardTitle = "Deine Basis"
    public static let cardText = "Deine Werte weichen seit 3 Tagen von deiner Basis ab. Wie fühlst du dich? Morgen lieber locker?"
}
