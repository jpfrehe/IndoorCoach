import Foundation

/// Decides what an incoming FIT-derived ride means for the rides already stored: a new ride, or measured seconds data
/// for a ride that came earlier from Strava or the MyWhoosh list (same ride, start within ±5 minutes).
public enum RideMerge {
    public enum Decision: Equatable, Sendable {
        /// Nothing comparable stored.
        case insert
        /// Same ride, stored without a power curve: fill in the seconds data (existing ride id).
        case enrich(Int)
        /// Same ride, and it already has a power curve: nothing to do.
        case alreadyComplete(Int)
        /// Same ride, but the incoming one brings no seconds data either (list/Strava summary): skip it.
        case duplicate(Int)
    }

    /// Starts closer than this are the same ride (the old duplicate rule of `storeImportedRides`).
    public static let matchWindow: TimeInterval = 300

    public static func decide(_ incoming: RideSummary, existing: [RideSummary]) -> Decision {
        func gap(_ r: RideSummary) -> TimeInterval { abs(r.startDate.timeIntervalSince(incoming.startDate)) }
        let match = existing.first { $0.id == incoming.id }
            ?? existing.filter { gap($0) < matchWindow }.min { gap($0) < gap($1) }
        guard let match else { return .insert }
        if hasCurve(match) { return .alreadyComplete(match.id) }
        return hasCurve(incoming) ? .enrich(match.id) : .duplicate(match.id)
    }

    /// `existing` plus the measured data of `incoming`. Identity (id, name, start, duration, distance, perceived
    /// exertion …) stays; NP, kJ, curve, decoupling and durability come from the file; max power keeps the higher
    /// value; averages and heart rate only fill gaps.
    public static func enriched(_ existing: RideSummary, with incoming: RideSummary) -> RideSummary {
        var r = existing
        if let curve = incoming.powerCurve, !curve.isEmpty { r.powerCurve = curve }
        if let m = incoming.maxWatts { r.maxWatts = max(m, existing.maxWatts ?? 0) }
        if let np = incoming.weightedAverageWatts { r.weightedAverageWatts = np }
        if let kj = incoming.kilojoules { r.kilojoules = kj }
        if let d = incoming.decoupling { r.decoupling = d }
        if let d = incoming.durability { r.durability = d }
        if r.averageWatts == nil { r.averageWatts = incoming.averageWatts }
        if r.averageHeartrate == nil { r.averageHeartrate = incoming.averageHeartrate }
        if r.maxHeartrate == nil { r.maxHeartrate = incoming.maxHeartrate }
        return r
    }

    static func hasCurve(_ ride: RideSummary) -> Bool { !(ride.powerCurve ?? [:]).isEmpty }
}
