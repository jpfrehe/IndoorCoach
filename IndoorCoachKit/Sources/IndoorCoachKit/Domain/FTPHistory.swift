import Foundation

/// A6 – eFTP history: 95 % of the best measured 20-minute power inside a 4-week window, evaluated every 7 days
/// over the last 6 months. Only rides with a measured 1 Hz power curve count (no floors from ride averages).
public enum FTPHistory {
    public static let windowDays = 28
    public static let stepDays = 7
    public static let spanDays = 182

    public struct Point: Hashable, Sendable, Identifiable {
        /// End of the 4-week window.
        public var date: Date
        public var eftp: Int
        public var id: Date { date }
    }

    /// Ascending by date; windows without a measured 20-minute value are left out.
    public static func series(rides: [RideSummary], now: Date) -> [Point] {
        let measured = rides.compactMap { ride -> (Date, Double)? in
            guard let w = ride.powerCurve?[1200], w > 0 else { return nil }
            return (ride.startDate, w)
        }
        var points: [Point] = []
        var offset = spanDays - spanDays % stepDays
        while offset >= 0 {
            let end = now.addingTimeInterval(-Double(offset) * 86_400)
            let start = end.addingTimeInterval(-Double(windowDays) * 86_400)
            if let best = measured.filter({ $0.0 > start && $0.0 <= end }).map(\.1).max() {
                points.append(Point(date: end, eftp: Int((best * 0.95).rounded())))
            }
            offset -= stepDays
        }
        return points
    }
}
