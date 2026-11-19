import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Check-in (Domain)")
struct CheckInTests {
    typealias A = CheckIn.Answers

    @Test func ruleNeedsTwoNegativesOrInfection() {
        #expect(!A(legs: .good, sleep: .good, mood: .good).offerNeeded)
        #expect(!A(legs: .bad, sleep: .ok, mood: .good).offerNeeded)
        #expect(A(legs: .bad, sleep: .bad, mood: .good).offerNeeded)
        #expect(A(legs: .bad, sleep: .bad, mood: .bad).negativeCount == 3)
        #expect(A(legs: .good, sleep: .good, mood: .good, tags: [.infekt]).offerNeeded)
        // Other tags alone are context, not a trigger.
        #expect(!A(legs: .good, sleep: .ok, mood: .good, tags: [.heiss, .koffein, .stress]).offerNeeded)
    }

    @Test func dueOnlyOncePerDayAndWithPlannedWorkout() {
        #expect(CheckIn.isDue(hasPlannedWorkoutToday: true, alreadyAnswered: false))
        #expect(!CheckIn.isDue(hasPlannedWorkoutToday: true, alreadyAnswered: true))
        #expect(!CheckIn.isDue(hasPlannedWorkoutToday: false, alreadyAnswered: false))   // Ruhetag
    }

    @Test func offersForNegativeCheckIn() {
        let a = A(legs: .bad, sleep: .bad, mood: .ok)
        let offers = CheckIn.offers(for: a, plannedMinutes: 75, jokersAvailable: 1)
        #expect(offers == [.shorten(minutes: 45, easierBy: 5), .swapToBase, .joker])
    }

    @Test func jokerOnlyWhenAvailableAndShortenOnlyWhenPossible() {
        let a = A(legs: .bad, sleep: .bad, mood: .ok)
        #expect(CheckIn.offers(for: a, plannedMinutes: 75, jokersAvailable: 0) == [.shorten(minutes: 45, easierBy: 5), .swapToBase])
        // 40 min plan: 45 is no shortening, 30 is.
        #expect(CheckIn.offers(for: a, plannedMinutes: 40, jokersAvailable: 0).first == .shorten(minutes: 30, easierBy: 5))
        // 30 min plan: nothing to shorten, only easier.
        #expect(CheckIn.offers(for: a, plannedMinutes: 30, jokersAvailable: 0).first == .easier(percent: 10))
    }

    @Test func noOffersWhenFine() {
        #expect(CheckIn.offers(for: A(legs: .good, sleep: .ok, mood: .good), plannedMinutes: 75, jokersAvailable: 2).isEmpty)
    }

    @Test func infectionOffersNoTrainingOnlyJokerAndHint() {
        let a = A(legs: .bad, sleep: .bad, mood: .bad, tags: [.infekt])
        #expect(CheckIn.offers(for: a, plannedMinutes: 75, jokersAvailable: 1) == [.joker])
        #expect(CheckIn.offers(for: a, plannedMinutes: 75, jokersAvailable: 0).isEmpty)
        #expect(CheckIn.healthHint(for: a) == "Bei Fieber nicht trainieren. Gute Besserung.")
        #expect(CheckIn.healthHint(for: A(legs: .bad, sleep: .bad, mood: .bad)) == nil)
    }

    @Test func labelsAreGerman() {
        #expect(CheckIn.Question.legs.title == "Beine")
        #expect(CheckIn.Level.bad.label(for: .legs) == "schwer")
        #expect(CheckIn.Tag.infekt.label == "Infekt")
    }

    @Test func actionRawValueRoundTrips() {
        for action in [CheckIn.Action.shorten(minutes: 45, easierBy: 5), .easier(percent: 10), .swapToBase, .joker] {
            #expect(CheckIn.Action(raw: action.raw) == action)
        }
        #expect(CheckIn.Action(raw: "unsinn") == nil)
    }
}
