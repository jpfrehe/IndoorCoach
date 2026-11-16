import Foundation

/// Persistence-independent view of a completed ride.
public struct RideSummary: Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var sportType: String
    public var startDate: Date
    public var movingTime: Int
    public var distance: Double
    public var averageWatts: Double?
    public var weightedAverageWatts: Double?
    public var kilojoules: Double?
    public var averageHeartrate: Double?
    public var maxHeartrate: Double?
    public var trainer: Bool

    public init(id: Int, name: String, sportType: String, startDate: Date, movingTime: Int, distance: Double,
                averageWatts: Double? = nil, weightedAverageWatts: Double? = nil, kilojoules: Double? = nil,
                averageHeartrate: Double? = nil, maxHeartrate: Double? = nil, trainer: Bool = false) {
        self.id = id
        self.name = name
        self.sportType = sportType
        self.startDate = startDate
        self.movingTime = movingTime
        self.distance = distance
        self.averageWatts = averageWatts
        self.weightedAverageWatts = weightedAverageWatts
        self.kilojoules = kilojoules
        self.averageHeartrate = averageHeartrate
        self.maxHeartrate = maxHeartrate
        self.trainer = trainer
    }

    public var isIndoor: Bool { trainer || sportType == "VirtualRide" }
}

public enum TSSSource: String, Sendable {
    case power, heartRate, duration
}

public struct TSSEstimate: Hashable, Sendable {
    public var tss: Double
    public var intensityFactor: Double?
    public var source: TSSSource
}

public enum TrainingLoad {
    /// Estimates TSS for a ride. Prefers weighted average power (≈ NP), then average power, then HR, then duration.
    public static func estimateTSS(for ride: RideSummary, ftp: Int, thresholdHeartRate: Int? = nil) -> TSSEstimate {
        let hours = Double(ride.movingTime) / 3600
        guard hours > 0 else { return TSSEstimate(tss: 0, intensityFactor: nil, source: .duration) }
        if ftp > 0, let np = ride.weightedAverageWatts ?? ride.averageWatts.map({ $0 * 1.05 }), np > 0 {
            let intensity = np / Double(ftp)
            return TSSEstimate(tss: hours * intensity * intensity * 100, intensityFactor: intensity, source: .power)
        }
        if let hr = ride.averageHeartrate, let lthr = thresholdHeartRate, lthr > 0 {
            let ratio = hr / Double(lthr)
            return TSSEstimate(tss: hours * ratio * ratio * 100, intensityFactor: nil, source: .heartRate)
        }
        // Unknown intensity: assume endurance (IF ≈ 0.7 → ~50 TSS/h).
        return TSSEstimate(tss: hours * 50, intensityFactor: nil, source: .duration)
    }

    public struct DayLoad: Hashable, Sendable, Identifiable {
        public var date: Date
        public var tss: Double
        public var ctl: Double   // fitness (42-day EWMA)
        public var atl: Double   // fatigue (7-day EWMA)
        public var tsb: Double   // form = yesterday's CTL − yesterday's ATL
        public var id: Date { date }
    }

    /// Computes the daily CTL/ATL/TSB series from `startingCTL/ATL` over every day in `range`.
    public static func series(dailyTSS: [Date: Double], from start: Date, to end: Date,
                              calendar: Calendar = .current,
                              startingCTL: Double = 0, startingATL: Double = 0) -> [DayLoad] {
        var result: [DayLoad] = []
        var ctl = startingCTL, atl = startingATL
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            let tss = dailyTSS[day] ?? 0
            let tsb = ctl - atl
            ctl += (tss - ctl) / 42
            atl += (tss - atl) / 7
            result.append(DayLoad(date: day, tss: tss, ctl: ctl, atl: atl, tsb: tsb))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Sums TSS per calendar day.
    public static func dailyTSS(rides: [RideSummary], ftp: Int, thresholdHeartRate: Int? = nil,
                                calendar: Calendar = .current) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for ride in rides {
            let day = calendar.startOfDay(for: ride.startDate)
            result[day, default: 0] += estimateTSS(for: ride, ftp: ftp, thresholdHeartRate: thresholdHeartRate).tss
        }
        return result
    }

    public struct WeekSummary: Hashable, Sendable, Identifiable {
        public var weekStart: Date
        public var rides: Int
        public var seconds: Int
        public var tss: Double
        public var kilojoules: Double
        public var indoorSeconds: Int
        public var id: Date { weekStart }
    }

    /// Aggregates rides into ISO weeks (Monday start). Weeks without rides inside the range are included as zero.
    public static func weeks(rides: [RideSummary], ftp: Int, thresholdHeartRate: Int? = nil, from start: Date, to end: Date,
                             calendar baseCalendar: Calendar = .current) -> [WeekSummary] {
        var calendar = baseCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        func weekStart(_ d: Date) -> Date {
            calendar.dateInterval(of: .weekOfYear, for: d)?.start ?? calendar.startOfDay(for: d)
        }
        var buckets: [Date: WeekSummary] = [:]
        var w = weekStart(start)
        let lastWeek = weekStart(end)
        while w <= lastWeek {
            buckets[w] = WeekSummary(weekStart: w, rides: 0, seconds: 0, tss: 0, kilojoules: 0, indoorSeconds: 0)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: w) else { break }
            w = next
        }
        for ride in rides {
            let key = weekStart(ride.startDate)
            guard var bucket = buckets[key] else { continue }
            bucket.rides += 1
            bucket.seconds += ride.movingTime
            bucket.tss += estimateTSS(for: ride, ftp: ftp, thresholdHeartRate: thresholdHeartRate).tss
            bucket.kilojoules += ride.kilojoules ?? 0
            if ride.isIndoor { bucket.indoorSeconds += ride.movingTime }
            buckets[key] = bucket
        }
        return buckets.values.sorted { $0.weekStart < $1.weekStart }
    }
}
