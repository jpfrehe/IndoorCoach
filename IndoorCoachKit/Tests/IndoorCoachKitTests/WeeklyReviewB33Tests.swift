import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// B33-Rest: Wochenrückblick würdigt „angepasst statt ausgefallen“, nennt den Aufwärm-Check-Trend und nimmt Plan-Feedback auf.
@MainActor
@Suite("Wochenrückblick B33")
struct WeeklyReviewB33Tests {
    typealias T = WeeklyReviewTests
    private static var keepAlive: [ModelContainer] = []

    private func item(_ day: Int, done: Bool = true, adjusted: Bool) -> WeeklyReview.PlannedItem {
        .init(date: T.at(2026, 11, day, 18), tss: 60, done: done, adjusted: adjusted)
    }

    private func review(rides: [RideSummary], planned: [WeeklyReview.PlannedItem] = [],
                        warmup: WarmupCheck.Trend.Direction? = nil) -> WeeklyReview {
        WeeklyReview.build(weekStart: T.monday, rides: rides, planned: planned,
                           series: FitnessFreshness.Series(points: [], effortFactor: nil), ftp: T.ftp,
                           thresholdHeartRate: nil, heartRate: T.hr, now: T.at(2026, 11, 23, 9), calendar: T.calendar(),
                           warmup: warmup)
    }

    // MARK: Angepasst statt ausgefallen

    @Test func countsAdjustedUnitsOfTheWeekOnly() {
        let r = review(rides: [T.ride(1, day: 17)], planned: [
            item(17, adjusted: true), item(19, adjusted: true), item(20, adjusted: false),
            .init(date: T.at(2026, 11, 10, 18), tss: 60, done: true, adjusted: true),   // Vorwoche
        ])
        #expect(r.adjustedCount == 2)
        #expect(r.adjustedLine == "2 Einheiten angepasst statt ausgefallen – so bleibst du dran.")
    }

    @Test func singularAndNone() {
        let one = review(rides: [T.ride(1, day: 17)], planned: [item(17, adjusted: true)])
        #expect(one.adjustedLine == "1 Einheit angepasst statt ausgefallen – so bleibst du dran.")
        let none = review(rides: [T.ride(1, day: 17)], planned: [item(17, adjusted: false)])
        #expect(none.adjustedCount == 0)
        #expect(none.adjustedLine == nil)
    }

    @Test func defaultIsNotAdjusted() {
        #expect(WeeklyReview.PlannedItem(date: .now, tss: 50, done: true).adjusted == false)
    }

    // MARK: Aufwärm-Check-Trend

    @Test func warmupTrendInOneSentence() {
        func line(_ direction: WarmupCheck.Trend.Direction?) -> String? {
            review(rides: [T.ride(1, day: 17)], warmup: direction).warmupLine
        }
        #expect(line(.falling) == "Aufwärm-Check: Der Puls bei deiner Referenzleistung sinkt – ein gutes Zeichen.")
        #expect(line(.stable) == "Aufwärm-Check: Der Puls bei deiner Referenzleistung bleibt stabil.")
        #expect(line(.rising) == "Aufwärm-Check: Der Puls bei deiner Referenzleistung steigt etwas – gönn dir genug Erholung.")
        #expect(line(.notEnough) == nil)
        #expect(line(nil) == nil)
    }

    @Test func restWeekHasNoWarmupLine() {
        #expect(review(rides: [], warmup: .falling).warmupLine == nil)
    }

    // MARK: Plan-Feedback (Modell)

    private func makeModel() throws -> (AppModel, UserDefaults) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let defaults = UserDefaults(suiteName: "b33-\(UUID().uuidString)")!
        return (AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults), defaults)
    }

    @Test func planFeedbackIsStoredPerWeekAndReplaceable() throws {
        let (model, defaults) = try makeModel()
        let other = T.at(2026, 11, 9, 0)
        #expect(model.planFeedback(forWeek: T.monday) == nil)
        model.setPlanFeedback(.up, forWeek: T.monday)
        model.setPlanFeedback(.down, forWeek: other)
        #expect(model.planFeedback(forWeek: T.monday) == .up)
        #expect(model.planFeedback(forWeek: other) == .down)
        model.setPlanFeedback(.down, forWeek: T.monday)      // umentschieden
        #expect(model.planFeedback(forWeek: T.monday) == .down)
        #expect(model.planFeedbackTotals == PilotMetrics.Feedback(up: 0, down: 2))
        model.setPlanFeedback(nil, forWeek: T.monday)        // zurücknehmen
        #expect(model.planFeedback(forWeek: T.monday) == nil)
        #expect(model.planFeedbackTotals == PilotMetrics.Feedback(up: 0, down: 1))
        // Neues Modell mit denselben Defaults sieht die Antwort (persistiert).
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let again = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        #expect(again.planFeedback(forWeek: other) == .down)
    }

    @Test func noFeedbackMeansNoTotalsAndPilotLineAppearsWithFeedback() throws {
        let (model, _) = try makeModel()
        #expect(model.planFeedbackTotals == nil)
        #expect(!model.pilotMetrics().lines.contains { $0.contains("Plan-Feedback") })
        model.setPlanFeedback(.up, forWeek: T.monday)
        #expect(model.pilotMetrics().lines.contains("Plan-Feedback: 1 positiv, 0 negativ"))
    }

    @Test func planFeedbackKeyIsPartOfDeleteAll() throws {
        let (model, defaults) = try makeModel()
        model.setPlanFeedback(.up, forWeek: T.monday)
        #expect(AppModel.Keys.all.contains(AppModel.Keys.planFeedback))
        #expect(defaults.object(forKey: AppModel.Keys.planFeedback) != nil)
    }

    // MARK: Trend-Wächter: Karte angezeigt

    @Test func shownCardIsCountedOncePerDay() throws {
        let (model, _) = try makeModel()
        let day = T.at(2026, 11, 17, 9)
        #expect(model.trendGuardCardShownDays == 0)
        model.recordTrendHintShown(now: day)
        model.recordTrendHintShown(now: day.addingTimeInterval(3600))
        #expect(model.trendGuardCardShownDays == 1)
        model.recordTrendHintShown(now: T.at(2026, 11, 18, 9))
        #expect(model.trendGuardCardShownDays == 2)
        #expect(model.pilotMetrics().lines.contains { $0.hasPrefix("Trend-Wächter: Karte angezeigt an 2 Tagen") })
    }

    @Test func shownCounterIsResetWithWellnessState() throws {
        let (model, defaults) = try makeModel()
        model.recordTrendHintShown(now: T.at(2026, 11, 17, 9))
        model.resetWellnessState()
        #expect(model.trendGuardCardShownDays == 0)
        for key in AppModel.wellnessStateKeys { #expect(defaults.object(forKey: key) == nil) }
    }

    // MARK: Pilot-Zeile

    @Test func pilotLineMentionsShownDays() {
        var input = PilotMetrics.Input()
        input.guardShadowHits = 3
        input.guardShadowDays = 20
        input.guardCardShownDays = 4
        #expect(PilotMetrics.compute(input).lines.contains("Trend-Wächter: Karte angezeigt an 4 Tagen, Schatten 3 Treffer an 20 Tagen"))
    }
}
