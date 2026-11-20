import Foundation

/// Erholungswerte, die ein Anbieter (z. B. Apple Health, später `AppModel+Wellness`) liefert: Mittel der letzten 14 Tage
/// gegen die eigene Basis. Bleibt auf dem Gerät; nur `RecoverySummary` (relativ, gerundet) darf an Claude gehen.
public struct RecoveryWellness: Sendable, Equatable {
    public var sleepRecentHours: Double?
    public var sleepBaselineHours: Double?
    public var restingHRRecent: Double?
    public var restingHRBaseline: Double?
    public var hrvRecent: Double?
    public var hrvBaseline: Double?
    /// Trend-Wächter (Auffälligkeit über mehrere Tage) ist aktiv.
    public var trendGuardActive: Bool

    public init(sleepRecentHours: Double? = nil, sleepBaselineHours: Double? = nil,
                restingHRRecent: Double? = nil, restingHRBaseline: Double? = nil,
                hrvRecent: Double? = nil, hrvBaseline: Double? = nil, trendGuardActive: Bool = false) {
        self.sleepRecentHours = sleepRecentHours; self.sleepBaselineHours = sleepBaselineHours
        self.restingHRRecent = restingHRRecent; self.restingHRBaseline = restingHRBaseline
        self.hrvRecent = hrvRecent; self.hrvBaseline = hrvBaseline
        self.trendGuardActive = trendGuardActive
    }
}

/// Verbindung zum Wellness-Paket: der PO setzt `AppModel.recoveryWellnessProvider`.
public protocol RecoveryWellnessProviding {
    func recoveryWellness(today: Date) -> RecoveryWellness?
}

/// Erholungskontext für Claude (docs/17 §9.7): relative 14-Tage-Aggregate.
/// Keine Rohwerte, keine Gerätenamen, keine Diagnosebegriffe; alles gerundet und aus festen Bausteinen gebaut.
public struct RecoverySummary: Sendable, Equatable {
    public enum HRVTrend: String, Sendable, Equatable { case below, within, above }
    public enum WarmupTrend: String, Sendable, Equatable { case stable, falling, higher }

    public struct CheckInDigest: Sendable, Equatable {
        public var total = 0
        public var legsHeavy = 0
        public var sleepBad = 0
        public var moodBad = 0
        public var infection = 0

        public var hasFindings: Bool { legsHeavy + sleepBad + moodBad + infection > 0 }
    }

    public struct Input: Sendable {
        public var wellness: RecoveryWellness?
        public var checkIns: [CheckIn.Answers]
        public var warmup: WarmupCheck.Trend.Direction?

        public init(wellness: RecoveryWellness? = nil, checkIns: [CheckIn.Answers] = [], warmup: WarmupCheck.Trend.Direction? = nil) {
            self.wellness = wellness; self.checkIns = checkIns; self.warmup = warmup
        }
    }

    /// Schlaf Δ Stunden gegen die Basis, auf 0,5 h gerundet.
    public var sleepDeltaHours: Double?
    /// Ruhepuls Δ bpm gegen die Basis, ganzzahlig.
    public var restingHRDeltaBpm: Int?
    public var hrv: HRVTrend?
    public var checkIns: CheckInDigest
    public var warmup: WarmupTrend?
    public var trendGuardActive: Bool

    /// HRV-Toleranz um die Basis (±10 %).
    static let hrvTolerance = 0.10

    /// `nil`, wenn es nichts zu sagen gibt (dann entfällt der Prompt-Abschnitt).
    public static func make(_ input: Input) -> RecoverySummary? {
        let w = input.wellness
        var digest = CheckInDigest()
        digest.total = input.checkIns.count
        for a in input.checkIns {
            if a.legs == .bad { digest.legsHeavy += 1 }
            if a.sleep == .bad { digest.sleepBad += 1 }
            if a.mood == .bad { digest.moodBad += 1 }
            if a.hasInfection { digest.infection += 1 }
        }
        var sleep: Double?
        if let r = w?.sleepRecentHours, let b = w?.sleepBaselineHours {
            sleep = ((r - b) * 2).rounded() / 2
        }
        var rhr: Int?
        if let r = w?.restingHRRecent, let b = w?.restingHRBaseline { rhr = Int((r - b).rounded()) }
        var hrv: HRVTrend?
        if let r = w?.hrvRecent, let b = w?.hrvBaseline, b > 0 {
            let ratio = r / b
            hrv = ratio < 1 - hrvTolerance ? .below : (ratio > 1 + hrvTolerance ? .above : .within)
        }
        let warmup: WarmupTrend? = switch input.warmup {
        case .stable: .stable
        case .falling: .falling
        case .rising: .higher
        case .notEnough, nil: nil
        }
        let guardActive = w?.trendGuardActive ?? false
        let summary = RecoverySummary(sleepDeltaHours: sleep, restingHRDeltaBpm: rhr, hrv: hrv, checkIns: digest,
                                      warmup: warmup, trendGuardActive: guardActive)
        return summary.isEmpty ? nil : summary
    }

    public var isEmpty: Bool {
        sleepDeltaHours == nil && restingHRDeltaBpm == nil && hrv == nil && checkIns.total == 0 && warmup == nil && !trendGuardActive
    }

    /// Die Zeilen des Prompt-Abschnitts „Erholung (14 Tage, relativ)“ (ohne Überschrift).
    public var promptLines: [String] {
        var lines: [String] = []
        if let d = sleepDeltaHours {
            lines.append(abs(d) < 0.5 ? "- Schlaf: wie gewohnt" : "- Schlaf: \(Self.signed(d, digits: 1)) h gegenüber eigener Basis")
        }
        if let d = restingHRDeltaBpm {
            lines.append(abs(d) <= 1 ? "- Ruhepuls: wie gewohnt" : "- Ruhepuls: \(Self.signed(Double(d), digits: 0)) bpm gegenüber eigener Basis")
        }
        if let h = hrv {
            lines.append("- HRV: " + (h == .below ? "unter eigener Basis" : (h == .above ? "über eigener Basis" : "im Normalbereich")))
        }
        if checkIns.total > 0 {
            var parts: [String] = []
            if checkIns.legsHeavy > 0 { parts.append("\(checkIns.legsHeavy)× Beine schwer") }
            if checkIns.sleepBad > 0 { parts.append("\(checkIns.sleepBad)× Schlaf schlecht") }
            if checkIns.moodBad > 0 { parts.append("\(checkIns.moodBad)× Laune mies") }
            if checkIns.infection > 0 { parts.append("\(checkIns.infection)× Infekt") }
            lines.append("- Check-ins (\(checkIns.total)): " + (parts.isEmpty ? "keine Auffälligkeiten" : parts.joined(separator: ", ")))
        }
        if let wu = warmup {
            lines.append("- Aufwärm-Check (Puls bei gleicher Leistung): " + (wu == .falling ? "sinkend" : (wu == .higher ? "höher" : "stabil")))
        }
        lines.append("- Trend-Wächter: " + (trendGuardActive ? "aktiv" : "nicht aktiv"))
        return lines
    }

    private static func signed(_ v: Double, digits: Int) -> String {
        let magnitude = String(format: "%.\(digits)f", locale: Locale.de, abs(v))
        return (v < 0 ? "−" : "+") + magnitude
    }
}
