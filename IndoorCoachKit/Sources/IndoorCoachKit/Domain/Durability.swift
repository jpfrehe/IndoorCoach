import Foundation

/// A7 "Ermüdungsresistenz": how much of your best 5-minute power you can still deliver in the last hour of a ride.
///
/// durability = best 5-min power within the last 3600 s ÷ best 5-min power of the whole ride × 100 (max. 100 %).
/// Only rides with a 1 Hz power series of at least 60 minutes count.
public enum Durability {
    public static let minimumSeconds = 3600
    static let window = 300

    /// Percent from a 1 Hz power series; nil when it is shorter than 60 minutes or has no 5-min power.
    public static func percent(power: [Double]) -> Double? {
        guard power.count >= minimumSeconds else { return nil }
        guard let overall = PowerCurve.meanMaximal(watts: power)[window], overall > 0,
              let late = PowerCurve.meanMaximal(watts: Array(power.suffix(minimumSeconds)))[window] else { return nil }
        return min(100, late / overall * 100)
    }

    /// Mean of the rides' values starting in the last `days` days; nil without any value.
    public static func average(rides: [RideSummary], days: Int = 90, now: Date = .now) -> (percent: Double, count: Int)? {
        let from = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let values = rides.filter { $0.startDate >= from && $0.startDate <= now }.compactMap(\.durability)
        guard !values.isEmpty else { return nil }
        return (values.reduce(0, +) / Double(values.count), values.count)
    }

    public enum Rating: Sendable {
        case high, medium, low
        public var label: String {
            switch self { case .high: "stark"; case .medium: "solide"; case .low: "ausbaufähig" }
        }
    }

    /// ≥ 90 % strong, ≥ 80 % solid, below that room to grow.
    public static func rating(percent: Double) -> Rating { percent >= 90 ? .high : percent >= 80 ? .medium : .low }
}
