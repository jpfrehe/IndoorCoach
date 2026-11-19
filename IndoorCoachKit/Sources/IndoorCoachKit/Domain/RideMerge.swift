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
        // ANCHOR-W3B: Ein Health-Workout wurde vorher über `HealthImport` auf Überlappung geprüft, hier zählt nur die eigene ID.
        // Eine echte Fahrt ersetzt dagegen ein schon importiertes Health-Workout, auch bei größerem Startversatz.
        let match = existing.first { $0.id == incoming.id }
            ?? (incoming.healthUUID != nil ? nil : existing.filter { gap($0) < matchWindow || overlapsHealthRide($0, incoming) }
                .min { gap($0) < gap($1) })
        guard let match else { return .insert }
        if match.healthUUID != nil, incoming.healthUUID == nil { return .enrich(match.id) }
        if hasCurve(match) { return .alreadyComplete(match.id) }
        return hasCurve(incoming) ? .enrich(match.id) : .duplicate(match.id)
    }

    /// `existing` plus the measured data of `incoming`. Identity (id, name, start, duration, distance, perceived
    /// exertion …) stays; NP, kJ, curve, decoupling and durability come from the file; max power keeps the higher
    /// value; averages and heart rate only fill gaps.
    public static func enriched(_ existing: RideSummary, with incoming: RideSummary) -> RideSummary {
        var r = existing
        if existing.healthUUID != nil, incoming.healthUUID == nil {
            // ANCHOR-W3B: Die echte Fahrt gibt die Identität; der Puls aus Health füllt nur Lücken (Priorität: FIT/Strava vor Health).
            r.name = incoming.name
            r.sportType = incoming.sportType
            r.startDate = incoming.startDate
            r.movingTime = incoming.movingTime
            r.distance = incoming.distance
            r.trainer = incoming.trainer
            r.averageWatts = incoming.averageWatts
            if hasCurve(incoming) || incoming.isFromStrava {
                r.averageHeartrate = incoming.averageHeartrate ?? existing.averageHeartrate
                r.maxHeartrate = incoming.maxHeartrate ?? existing.maxHeartrate
            }
            r.healthUUID = nil
            r.foreignSport = nil
            r.estimatedTSS = nil
        }
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

    /// Die vorhandene Fahrt stammt aus Health und überlappt die einlaufende zu ≥ 50 % ihrer eigenen Dauer.
    private static func overlapsHealthRide(_ existing: RideSummary, _ incoming: RideSummary) -> Bool {
        guard existing.healthUUID != nil else { return false }
        let end = existing.startDate.addingTimeInterval(TimeInterval(existing.movingTime))
        return HealthImport.overlapFraction(start: existing.startDate, end: end, otherStart: incoming.startDate,
                                            otherEnd: incoming.startDate.addingTimeInterval(TimeInterval(incoming.movingTime)))
            >= HealthImport.overlapThreshold
    }

    static func hasCurve(_ ride: RideSummary) -> Bool { !(ride.powerCurve ?? [:]).isEmpty }
}
