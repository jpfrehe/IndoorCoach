import Foundation

/// Mean-maximal power ("power curve"): the best average power the athlete held for each duration.
///
/// Rides with 1 Hz data (FIT import) contribute *measured* points. Rides with only a summary still prove a
/// lower bound: a ride averaging P watts for D seconds means best(d) >= P for every d <= D (*floor* points).
public enum PowerCurve {
    /// Durations (seconds) the curve is computed for.
    public static let standardDurations: [Int] = [1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300, 420, 600, 900,
                                                  1200, 1800, 2700, 3600, 5400, 7200]
    /// Durations shown in the best-efforts list and checked for new personal records.
    public static let headlineDurations: [Int] = [5, 15, 60, 300, 600, 1200, 3600]

    public enum Source: String, Sendable { case measured, floor }

    public struct Point: Hashable, Sendable {
        public var duration: Int
        public var watts: Double
        public var source: Source
        public var rideID: Int
        public var date: Date
    }

    // MARK: Per-ride curve

    /// Best average power per standard duration from 1 Hz samples (sliding-window sums, O(n·k)).
    /// Durations longer than the ride are omitted.
    public static func meanMaximal(watts: [Double]) -> [Int: Double] {
        var result: [Int: Double] = [:]
        let n = watts.count
        guard n > 0 else { return result }
        for d in standardDurations where d <= n {
            var sum = 0.0
            for i in 0..<d { sum += watts[i] }
            var best = sum
            if n > d {
                for i in d..<n {
                    sum += watts[i] - watts[i - d]
                    if sum > best { best = sum }
                }
            }
            result[d] = best / Double(d)
        }
        return result
    }

    /// Lower bounds a summary-only ride proves: average power for every duration up to its length, max power for 1 s.
    public static func floors(for ride: RideSummary) -> [Int: Double] {
        var result: [Int: Double] = [:]
        if let avg = ride.averageWatts, avg > 0 {
            for d in standardDurations where d <= ride.movingTime { result[d] = avg }
        }
        if let max = ride.maxWatts, max > 0 { result[1] = Swift.max(result[1] ?? 0, max) }
        return result
    }

    // MARK: Persistence helpers (JSON, string keys so it stays readable and stable)

    public static func encode(_ curve: [Int: Double]) -> Data? {
        try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: curve.map { (String($0.key), $0.value) }))
    }

    public static func decode(_ data: Data?) -> [Int: Double]? {
        guard let data, let raw = try? JSONDecoder().decode([String: Double].self, from: data) else { return nil }
        var result: [Int: Double] = [:]
        for (key, value) in raw { if let d = Int(key) { result[d] = value } }
        return result.isEmpty ? nil : result
    }

    // MARK: Aggregation

    public struct Aggregate: Sendable {
        public var points: [Int: Point]
        /// Rides starting inside the range.
        public var totalRides: Int
        /// Of those, rides with a measured (1 Hz) curve.
        public var measuredRides: Int

        public func best(_ duration: Int) -> Point? { points[duration] }

        /// Points in ascending duration order.
        public var sortedPoints: [Point] { points.values.sorted { $0.duration < $1.duration } }

        /// eFTP = 95 % of the best 20-minute power (only when a 20-minute value exists).
        public var estimatedFTP: Int? {
            points[1200].map { Int(($0.watts * 0.95).rounded()) }
        }
    }

    /// Per duration the maximum over all rides starting in `from...to`; measured beats floor at equal watts,
    /// an earlier ride keeps a tie.
    public static func aggregate(rides: [RideSummary], from: Date, to: Date) -> Aggregate {
        var points: [Int: Point] = [:]
        var total = 0, measured = 0
        for ride in rides.sorted(by: { $0.startDate < $1.startDate }) where ride.startDate >= from && ride.startDate <= to {
            total += 1
            let curve: [Int: Double]
            let source: Source
            if let c = ride.powerCurve, !c.isEmpty { curve = c; source = .measured; measured += 1 }
            else { curve = floors(for: ride); source = .floor }
            for (d, w) in curve where w > 0 {
                let candidate = Point(duration: d, watts: w, source: source, rideID: ride.id, date: ride.startDate)
                if let existing = points[d] {
                    if w > existing.watts || (w == existing.watts && source == .measured && existing.source == .floor) {
                        points[d] = candidate
                    }
                } else {
                    points[d] = candidate
                }
            }
        }
        return Aggregate(points: points, totalRides: total, measuredRides: measured)
    }

    public struct Comparison: Sendable {
        public var current: Aggregate
        public var previous: Aggregate
        /// Watts gained (+) or lost (−) at `duration`; nil unless both periods have a value.
        public func delta(at duration: Int) -> Double? {
            guard let c = current.points[duration], let p = previous.points[duration] else { return nil }
            return c.watts - p.watts
        }
    }

    /// The last `days` days versus the `days` days before them.
    public static func comparison(rides: [RideSummary], days: Int, now: Date = .now) -> Comparison {
        let length = TimeInterval(days) * 86_400
        let start = now.addingTimeInterval(-length)
        let previousStart = start.addingTimeInterval(-length)
        return Comparison(current: aggregate(rides: rides, from: start, to: now),
                          previous: aggregate(rides: rides, from: previousStart, to: start.addingTimeInterval(-1)))
    }

    // MARK: Personal records

    /// Headline durations at which `ride` holds the best *measured* value of the last `windowDays` days.
    /// Needs at least one other ride in the window to be a record against.
    public static func records(for ride: RideSummary, among rides: [RideSummary], now: Date = .now,
                               windowDays: Int = 90) -> [Point] {
        let from = now.addingTimeInterval(-TimeInterval(windowDays) * 86_400)
        guard ride.startDate >= from, ride.startDate <= now,
              rides.contains(where: { $0.id != ride.id && $0.startDate >= from && $0.startDate <= now }) else { return [] }
        var window = rides.filter { $0.id != ride.id }
        window.append(ride)
        let agg = aggregate(rides: window, from: from, to: now)
        return headlineDurations.compactMap { d in
            guard let p = agg.points[d], p.rideID == ride.id, p.source == .measured else { return nil }
            return p
        }
    }
}
