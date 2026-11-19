import Foundation

extension DemoData {
    /// Lays an Aufwärm-Check onto a demo ride's seconds: the first 6 minutes steady at the default reference power,
    /// pulse settling lower the more recent the ride is (an aerobic base that improves over the demo winter).
    /// Rides with their own structure (the Soll/Ist demo rides) stay untouched. Deterministic, synthetic.
    static func applyingWarmupCheck(_ seconds: RideSeconds, for ride: RideSummary, ftp: Int, now: Date = .now) -> RideSeconds {
        guard !ride.name.contains("2×20"), !ride.name.contains("5×3"), ride.movingTime >= 40 * 60,
              seconds.count >= 600, var heart = seconds.heartRate else { return seconds }
        let ref = Double(WarmupCheck.defaultWatts(ftp: ftp))
        guard ref > 0 else { return seconds }
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: ride.id) &* 53)
        let daysAgo = max(0, now.timeIntervalSince(ride.startDate) / 86_400)
        let progress = min(1, max(0, 1 - daysAgo / 84))
        let target = 129 - 9 * progress + Double.random(in: -1...1, using: &rng)
        let start = Double(heart[0] > 0 ? heart[0] : 95)
        var power = seconds.power
        for t in 0..<WarmupCheck.blockSeconds {
            power[t] = UInt16((ref * Double.random(in: 0.985...1.015, using: &rng)).rounded())
            let level = t < 240 ? start + (target - start) * Double(t) / 240 : target + Double.random(in: -0.6...0.6, using: &rng)
            heart[t] = UInt8(max(1, min(255, level.rounded())))
        }
        return RideSeconds(power: power, heartRate: heart)
    }
}
