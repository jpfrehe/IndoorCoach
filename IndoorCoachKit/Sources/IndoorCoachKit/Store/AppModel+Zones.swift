import Foundation

/// What is derived from one ride's 1 Hz data; cached because decoding ~50 rides must not slow the lists down.
struct RideSecondsDigest: Equatable, Sendable {
    var zones: ZoneTime.Result
    var trimp: Double?
}

@MainActor
private enum ZoneDigestCache {
    struct Key: Hashable {
        var model: ObjectIdentifier
        var rideID: Int
        var ftp: Int
        var resting: Int
        var maxHR: Int
        var threshold: Int
    }
    static var entries: [Key: RideSecondsDigest] = [:]
}

extension AppModel {
    public func heartRateZones() -> HeartRateZones {
        HeartRateZones(maxHeartRate: profile.heartRateProfile.max, thresholdHeartRate: profile.thresholdHeartRate)
    }

    /// Digest of the ride's seconds for the current FTP and HR profile; nil when the ride has no stored seconds
    /// (those lookups are not cached, so an import that adds seconds later shows up at once).
    func secondsDigest(for ride: RideSummary) -> RideSecondsDigest? {
        let hr = profile.heartRateProfile
        let key = ZoneDigestCache.Key(model: ObjectIdentifier(self), rideID: ride.id, ftp: profile.ftp, resting: hr.resting,
                                      maxHR: hr.max, threshold: profile.thresholdHeartRate ?? 0)
        if let cached = ZoneDigestCache.entries[key] { return cached }
        guard let seconds = rideSeconds(id: ride.id) else { return nil }
        let digest = RideSecondsDigest(zones: ZoneTime.compute(seconds, ftp: profile.ftp, heartRate: heartRateZones()),
                                       trimp: RelativeEffort.trimp(seconds: seconds, heartRate: hr))
        if ZoneDigestCache.entries.count > 2_000 { ZoneDigestCache.entries.removeAll() }
        ZoneDigestCache.entries[key] = digest
        return digest
    }

    /// Time per power and heart-rate zone of a ride with stored seconds.
    public func zoneTimes(for ride: RideSummary) -> ZoneTime.Result? {
        secondsDigest(for: ride)?.zones
    }

    /// Training distribution where rides inside the window use their measured time per band.
    public func trainingDistribution(rides: [RideSummary], weeks: Int, now: Date = .now) -> TrainingDistribution.Result {
        TrainingDistribution.distribution(rides: rides, ftp: profile.ftp, weeks: weeks, now: now) { [self] ride in
            zoneTimes(for: ride)
        }
    }
}
