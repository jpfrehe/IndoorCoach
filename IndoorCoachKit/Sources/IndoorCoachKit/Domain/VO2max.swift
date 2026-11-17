import Foundation

/// VO2max estimates (ml/kg/min). Estimates only – not a lab test.
public enum VO2max {
    public enum Method: String, Sendable { case power, ftp, heartRate }

    /// Typical 5-minute power relative to FTP (VO2max efforts sit at ~106–120 % FTP; 5 min ≈ 120 %).
    public static let fiveMinuteToFTP = 1.2

    public struct Estimate: Hashable, Sendable {
        public var value: Double
        public var method: Method
        /// Power method: the 5-min power used (W); HR method: the max HR used.
        public var inputWatts: Double?
        public var inputMaxHR: Int?
        public var inputRestingHR: Int?
        /// The 5-min power is only a floor from a long ride's average (true value is at least this high).
        public var isLowerBound: Bool
        /// The max HR was estimated rather than taken from the profile.
        public var maxHRIsEstimated: Bool
    }

    public struct TrendPoint: Hashable, Sendable, Identifiable {
        public var windowStart: Date
        public var windowEnd: Date
        public var value: Double
        public var id: Date { windowStart }
    }

    /// ACSM cycle-ergometer equation: VO2 = 10.8 × (P / kg) + 7, applied to the best 5-minute power.
    public static func fromPower(fiveMinuteWatts: Double, weightKg: Double) -> Double {
        10.8 * (fiveMinuteWatts / weightKg) + 7
    }

    /// Uth–Sørensen: VO2max = 15.3 × HRmax / HRrest.
    public static func fromHeartRate(maxHR: Int, restingHR: Int) -> Double {
        15.3 * Double(maxHR) / Double(restingHR)
    }

    /// 1. a *measured* 5-minute best → ACSM; 2. the profile FTP (5 min ≈ 120 % FTP) → ACSM – unless a ride's
    /// average already proves more; 3. Uth–Sørensen from the profile heart rates.
    /// A floor from a long ride's *average* is far below a real 5-minute effort, so it never stands alone
    /// (it would report e.g. 26 ml/kg/min for a fit rider who only has MyWhoosh list data).
    public static func estimate(curve: PowerCurve.Aggregate, profile: AthleteProfile) -> Estimate? {
        let p5 = curve.points[300]
        if let p5, p5.source == .measured, profile.weightKg > 0 {
            return Estimate(value: fromPower(fiveMinuteWatts: p5.watts, weightKg: profile.weightKg), method: .power,
                            inputWatts: p5.watts, inputMaxHR: nil, inputRestingHR: nil,
                            isLowerBound: false, maxHRIsEstimated: false)
        }
        if profile.ftp > 0, profile.weightKg > 0 {
            let fromFTP = Double(profile.ftp) * fiveMinuteToFTP
            if let p5, p5.watts > fromFTP {        // a ride already proves more than the FTP suggests
                return Estimate(value: fromPower(fiveMinuteWatts: p5.watts, weightKg: profile.weightKg), method: .power,
                                inputWatts: p5.watts, inputMaxHR: nil, inputRestingHR: nil,
                                isLowerBound: true, maxHRIsEstimated: false)
            }
            return Estimate(value: fromPower(fiveMinuteWatts: fromFTP, weightKg: profile.weightKg), method: .ftp,
                            inputWatts: fromFTP, inputMaxHR: nil, inputRestingHR: nil,
                            isLowerBound: false, maxHRIsEstimated: false)
        }
        if let maxHR = profile.maxHeartRate, maxHR > 0, profile.restingHeartRate > 0 {
            return Estimate(value: fromHeartRate(maxHR: maxHR, restingHR: profile.restingHeartRate), method: .heartRate,
                            inputWatts: nil, inputMaxHR: maxHR, inputRestingHR: profile.restingHeartRate,
                            isLowerBound: false, maxHRIsEstimated: false)
        }
        return nil
    }

    /// One power-based value per 6-week window over the last `windows` windows (default 4 ≈ 6 months), oldest first.
    /// Windows without a measured 5-minute value are skipped.
    public static func trend(rides: [RideSummary], profile: AthleteProfile, now: Date = .now, windows: Int = 4) -> [TrendPoint] {
        let length = 42.0 * 86_400
        guard profile.weightKg > 0 else { return [] }
        return (0..<windows).reversed().compactMap { i in
            let end = now.addingTimeInterval(-Double(i) * length)
            let start = end.addingTimeInterval(-length)
            let agg = PowerCurve.aggregate(rides: rides, from: i == 0 ? start : start.addingTimeInterval(1), to: end)
            // Measured values only: summary floors would make the trend follow ride length, not fitness.
            guard let p5 = agg.points[300], p5.source == .measured else { return nil }
            return TrendPoint(windowStart: start, windowEnd: end,
                              value: fromPower(fiveMinuteWatts: p5.watts, weightKg: profile.weightKg))
        }
    }
}
