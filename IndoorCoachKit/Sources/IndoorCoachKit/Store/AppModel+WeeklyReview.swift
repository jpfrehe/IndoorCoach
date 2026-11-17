import Foundation

/// Wochenrückblick (K2): glue between the stored data and the pure `WeeklyReview` domain.
extension AppModel {
    /// Planned workouts reduced to what the review counts (skipped ones are neither planned nor missed).
    func weeklyReviewPlan(from workouts: [StoredWorkout]) -> [WeeklyReview.PlannedItem] {
        workouts.filter { $0.status != .skipped }
            .map { WeeklyReview.PlannedItem(date: $0.date, tss: $0.definition.estimatedTSS, done: $0.status == .done) }
    }

    /// `count` reviews, newest (the `focus` Monday) first.
    func weeklyReviews(rides: [RideSummary], workouts: [StoredWorkout], focus: Date, count: Int,
                       now: Date = .now) -> [WeeklyReview] {
        WeeklyReview.recent(count: count, endingAt: focus, rides: rides, planned: weeklyReviewPlan(from: workouts),
                            series: fitnessSeries(rides: rides, now: now), ftp: profile.ftp,
                            thresholdHeartRate: profile.thresholdHeartRate, heartRate: profile.heartRateProfile, now: now)
    }

    /// Monday of the week the Heute card should show, or nil outside the window / after "Ausblenden".
    func weeklyReviewCardWeek(now: Date = .now) -> Date? {
        _ = weeklyReviewDismissRevision                 // observed: Heute swaps in the challenge after "Ausblenden"
        var week = WeeklyReview.visibleWeekStart(now: now)
        #if DEBUG
        // UI tests: `-uiWeeklyReview YES` forces the card (for the week before the current one).
        if week == nil, UserDefaults.standard.string(forKey: "uiWeeklyReview") == "YES" {
            week = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: WeeklyReview.weekStart(containing: now))
        }
        #endif
        guard let week, !dismissedWeeklyReviews.contains(Self.weekKey(week)) else { return nil }
        return week
    }

    func dismissWeeklyReview(_ weekStart: Date) {
        // Keep the list short: reviews are only offered for a few days anyway.
        let list = (dismissedWeeklyReviews + [Self.weekKey(weekStart)]).suffix(20)
        defaults.set(Array(list), forKey: Keys.weeklyReviewDismissed)
        weeklyReviewDismissRevision += 1
    }

    private var dismissedWeeklyReviews: [String] {
        defaults.stringArray(forKey: Keys.weeklyReviewDismissed) ?? []
    }

    private static func weekKey(_ weekStart: Date) -> String { Formatters.isoDay.string(from: weekStart) }
}
