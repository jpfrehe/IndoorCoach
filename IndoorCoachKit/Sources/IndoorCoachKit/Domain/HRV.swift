import Foundation

/// RR artefact filter and short-term HRV (RMSSD) for chest-strap data.
public enum HRV {
    public static let minRR = 300.0
    public static let maxRR = 2000.0
    /// Maximum relative deviation from the local median before a beat counts as an artefact.
    public static let maxDeviation = 0.20

    public struct Result: Equatable, Sendable {
        public var accepted: Int
        public var rejected: Int
        public var rmssd: Double?
        public var lnRMSSD: Double?
        /// Share of kept values, 0...1 (0 without input).
        public var quality: Double
    }

    /// Needs at least two successive differences, otherwise `rmssd` is nil.
    public static func analyze(_ rr: [Double]) -> Result {
        guard !rr.isEmpty else { return Result(accepted: 0, rejected: 0, rmssd: nil, lnRMSSD: nil, quality: 0) }
        let inRange = rr.map { $0 >= minRR && $0 <= maxRR }
        // Median over a centred window of up to five plausible neighbours, ignoring out-of-range values.
        var keep = [Bool](repeating: false, count: rr.count)
        for i in rr.indices where inRange[i] {
            let window = (max(0, i - 2)...min(rr.count - 1, i + 2)).filter { inRange[$0] }.map { rr[$0] }.sorted()
            let mid = window.count / 2
            let median = window.count % 2 == 1 ? window[mid] : (window[mid - 1] + window[mid]) / 2
            keep[i] = abs(rr[i] - median) / median <= maxDeviation
        }
        let accepted = keep.filter { $0 }.count
        var squares = 0.0
        var diffs = 0
        for i in rr.indices.dropFirst() where keep[i] && keep[i - 1] {
            let d = rr[i] - rr[i - 1]
            squares += d * d
            diffs += 1
        }
        let rmssd: Double? = diffs >= 2 ? (squares / Double(diffs)).squareRoot() : nil
        return Result(accepted: accepted, rejected: rr.count - accepted, rmssd: rmssd,
                      lnRMSSD: rmssd.flatMap { $0 > 0 ? log($0) : nil },
                      quality: Double(accepted) / Double(rr.count))
    }
}
