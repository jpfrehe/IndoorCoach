import Foundation

/// Heart-rate zones (5 zones). The app had no HR zone model yet, so this documents one:
/// with a threshold heart rate (LTHR) the Friel zones in % of LTHR (lower bounds 0 / 81 / 89 / 94 / 100 %),
/// otherwise % of maximum heart rate (0 / 60 / 70 / 80 / 90 %).
public struct HeartRateZones: Equatable, Sendable {
    public static let names = ["Erholung", "Grundlage", "Tempo", "Schwelle", "Maximal"]

    /// Lower bounds in bpm of zones 2…5 (a bpm below the first belongs to zone 1).
    public let lowerBounds: [Int]

    public init(maxHeartRate: Int, thresholdHeartRate: Int?) {
        let fractions: [Double]
        let base: Double
        if let lthr = thresholdHeartRate, lthr > 0 {
            fractions = [0.81, 0.89, 0.94, 1.0]
            base = Double(lthr)
        } else {
            fractions = [0.60, 0.70, 0.80, 0.90]
            base = Double(maxHeartRate)
        }
        lowerBounds = fractions.map { Int((base * $0 - 1e-9).rounded(.up)) }
    }

    /// Zero-based zone index (0 = Z1 … 4 = Z5).
    public func zone(forBPM bpm: Int) -> Int {
        var z = 0
        for bound in lowerBounds where bpm >= bound { z += 1 }
        return z
    }
}

/// Time in zones of one ride, computed from its 1 Hz data in a single pass.
public enum ZoneTime {
    public struct Result: Equatable, Sendable {
        /// Seconds per power zone Z1…Z7 (0 W excluded).
        public var power: [Int]
        /// Seconds per heart-rate zone Z1…Z5 (0 bpm excluded); nil without heart-rate data.
        public var heart: [Int]?
        /// Seconds per training-distribution band (Grundlage, Tempo, Schwelle+), cut at the IF thresholds 0,75 and 0,95.
        public var bands: [Int]

        public var powerTotal: Int { power.reduce(0, +) }
        public var heartTotal: Int { heart?.reduce(0, +) ?? 0 }
    }

    public static func compute(_ seconds: RideSeconds, ftp: Int, heartRate zones: HeartRateZones?) -> Result {
        var power = [Int](repeating: 0, count: PowerZone.allCases.count)
        var bands = [0, 0, 0]
        if ftp > 0 {
            let f = Double(ftp)
            for w in seconds.power where w > 0 {
                let fraction = Double(w) / f
                power[PowerZone(fractionOfFTP: fraction).rawValue - 1] += 1
                bands[fraction < 0.75 ? 0 : (fraction < 0.95 ? 1 : 2)] += 1
            }
        }
        var heart: [Int]?
        if let zones, let hr = seconds.heartRate {
            var counts = [Int](repeating: 0, count: 5)
            for bpm in hr where bpm > 0 { counts[zones.zone(forBPM: Int(bpm))] += 1 }
            heart = counts
        }
        return Result(power: power, heart: heart, bands: bands)
    }
}
