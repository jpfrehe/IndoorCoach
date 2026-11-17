import Foundation
import SwiftData

extension AppModel {
    /// Konstanz-Serie (K1): evaluates the weeks since the Winter Arc start from rides and the saved plan.
    public func consistency(rides: [RideSummary], now: Date = .now) -> Consistency.Result {
        let calendar = Calendar.current
        let season = WinterArc.defaultSeason(containing: now, calendar: calendar)
        let start = calendar.startOfDay(for: profile.arcStart ?? season.start)
        return Consistency.evaluate(weeklyBudgetSeconds: profile.weeklyHours * 3600,
                                    rides: consistencyRides(rides.filter { $0.startDate >= start }),
                                    planned: consistencyPlanned(), seasonStart: start, now: now, calendar: calendar)
    }

    func consistencyRides(_ rides: [RideSummary]) -> [Consistency.Ride] {
        rides.map {
            Consistency.Ride(date: $0.startDate, seconds: Double($0.movingTime),
                             tss: TrainingLoad.estimateTSS(for: $0, ftp: profile.ftp, thresholdHeartRate: profile.thresholdHeartRate).tss)
        }
    }

    func consistencyPlanned() -> [Consistency.PlannedItem] {
        ((try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? []).map {
            Consistency.PlannedItem(date: $0.date, tss: $0.definition.estimatedTSS, done: $0.status == .done || $0.linkedRideID != nil)
        }
    }
}
