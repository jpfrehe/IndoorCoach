import Foundation
import Testing
@testable import IndoorCoachKit

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 18, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func ride(_ date: Date, minutes: Int = 60, indoor: Bool = true, np: Double? = 150, id: Int? = nil) -> RideSummary {
    RideSummary(id: id ?? Int(date.timeIntervalSince1970 / 60), name: "R", sportType: indoor ? "VirtualRide" : "Ride", startDate: date,
                       movingTime: minutes * 60, distance: 30_000, averageWatts: np.map { $0 * 0.95 },
                       weightedAverageWatts: np, trainer: indoor)
}

private func find(_ list: [Challenges.Challenge], _ kind: Challenges.Kind, month: Int? = nil) -> Challenges.Challenge {
    list.first { $0.kind == kind && (month == nil || cal.component(.month, from: $0.start) == month) }!
}

@Suite("Saison-Challenges")
struct ChallengesTests {
    @Test func seasonYearFollowsTheWinter() {
        #expect(Challenges.seasonStartYear(containing: at(2026, 11, 17), calendar: cal) == 2026)
        #expect(Challenges.seasonStartYear(containing: at(2027, 1, 5), calendar: cal) == 2026)
        #expect(Challenges.seasonStartYear(containing: at(2027, 3, 30), calendar: cal) == 2026)
        #expect(Challenges.seasonStartYear(containing: at(2026, 8, 1), calendar: cal) == 2026)
    }

    @Test func seasonHasEightChallengesInOrder() {
        let list = Challenges.season(rides: [], ftp: 250, now: at(2026, 11, 17), calendar: cal)
        #expect(list.count == 8)
        #expect(list.filter { $0.kind == .monatsKonstanz }.count == 5)
        #expect(list.first?.title == "Monats-Konstanz November")
        #expect(list.map(\.start) == list.map(\.start).sorted())
        #expect(find(list, .indoor500).start == at(2026, 12, 24, 0))
        #expect(find(list, .indoor500).end == at(2027, 1, 1, 0))
        #expect(find(list, .kalterJanuar).start == at(2027, 1, 1, 0))
    }

    @Test func monthlyConsistencyCountsIndoorSessionsOnly() {
        let rides = [ride(at(2026, 11, 3)), ride(at(2026, 11, 5)), ride(at(2026, 11, 8, 9), indoor: false),
                     ride(at(2026, 10, 31, 23, 30)), ride(at(2026, 12, 1, 0, 5))]
        let nov = find(Challenges.season(rides: rides, ftp: 250, now: at(2026, 11, 17), calendar: cal), .monatsKonstanz, month: 11)
        #expect(nov.progress == 2)
        #expect(nov.goal == 8)
        #expect(nov.remaining == 6)
        #expect(nov.state == .active(daysLeft: 14))   // 17.–30. Nov
        #expect(nov.progressText == "2 von 8 Einheiten")
        #expect(nov.remainingText == "noch 6 Einheiten")
    }

    @Test func lastDayHasOneDayLeftAndNextDayIsMissed() {
        let rides = (1...3).map { ride(at(2026, 11, $0)) }
        let onLast = find(Challenges.season(rides: rides, ftp: 250, now: at(2026, 11, 30, 23, 0), calendar: cal), .monatsKonstanz, month: 11)
        #expect(onLast.state == .active(daysLeft: 1))
        let after = find(Challenges.season(rides: rides, ftp: 250, now: at(2026, 12, 1, 0, 1), calendar: cal), .monatsKonstanz, month: 11)
        #expect(after.state == .missed)
    }

    @Test func completionDateIsTheRideThatReachedTheGoal() {
        let rides = (0..<9).map { ride(at(2026, 11, 2 + $0 * 2), id: 10 + $0) }   // 2., 4., … 18.
        let nov = find(Challenges.season(rides: rides, ftp: 250, now: at(2026, 11, 20), calendar: cal), .monatsKonstanz, month: 11)
        #expect(nov.state == .completed(on: at(2026, 11, 16)))   // 8th ride
        #expect(nov.completedByRideID == 10 + 7)
        #expect(nov.progress == 9)
        #expect(nov.fraction == 1)
        // Stays completed after the window closed.
        let later = find(Challenges.season(rides: rides, ftp: 250, now: at(2027, 2, 1), calendar: cal), .monatsKonstanz, month: 11)
        #expect(later.isCompleted)
    }

    @Test func completingRideIsFoundForTheRideNote() {
        let rides = (0..<8).map { ride(at(2026, 11, 2 + $0), id: 50 + $0) }
        let list = Challenges.season(rides: rides, ftp: 250, now: at(2026, 11, 20), calendar: cal)
        let last = rides.last!
        #expect(Challenges.completed(by: last, in: list).map(\.title) == ["Monats-Konstanz November"])
        #expect(Challenges.completed(by: rides[0], in: list).isEmpty)
    }

    // MARK: Indoor-500

    @Test func indoor500WindowIsDec24Through31() {
        let rides = [ride(at(2026, 12, 23, 23, 59), minutes: 100),   // too early
                     ride(at(2026, 12, 24, 0, 0), minutes: 120),
                     ride(at(2026, 12, 31, 23, 59), minutes: 130),
                     ride(at(2027, 1, 1, 0, 0), minutes: 200),        // New Year: not in Indoor-500
                     ride(at(2026, 12, 27, 10), minutes: 300, indoor: false)]
        let list = Challenges.season(rides: rides, ftp: 250, now: at(2026, 12, 31, 23, 59), calendar: cal)
        let c = find(list, .indoor500)
        #expect(c.progress == 250)
        #expect(c.state == .active(daysLeft: 1))
        #expect(c.progressText == "250 von 500 Minuten")
        // Jan 1st ride counts for Kalter Januar, not for Indoor-500.
        let later = Challenges.season(rides: rides, ftp: 250, now: at(2027, 1, 2), calendar: cal)
        #expect(find(later, .indoor500).state == .missed)
        #expect(find(later, .kalterJanuar).progress == 1)
    }

    @Test func indoor500CompletesAtTheYearBoundary() {
        let rides = [ride(at(2026, 12, 28), minutes: 250), ride(at(2026, 12, 31, 20), minutes: 250)]
        let c = find(Challenges.season(rides: rides, ftp: 250, now: at(2027, 1, 3), calendar: cal), .indoor500)
        #expect(c.state == .completed(on: at(2026, 12, 31, 20)))
    }

    // MARK: Kalter Januar

    @Test func kalterJanuarBelongsToTheSeasonStartedInNovember() {
        let rides = (1...12).map { ride(at(2027, 1, $0)) }
        let list = Challenges.season(rides: rides, ftp: 250, now: at(2027, 1, 14), calendar: cal)
        #expect(find(list, .kalterJanuar).state == .completed(on: at(2027, 1, 12)))
        // Same date, but asked in December: January is still upcoming (20 days away is > 7 → no highlight).
        let december = Challenges.season(rides: [], ftp: 250, now: at(2026, 12, 25), calendar: cal)
        #expect(find(december, .kalterJanuar).state == .upcoming(daysUntilStart: 7))
    }

    // MARK: Februar-Fundament

    @Test func februaryCountsOnlyEnduranceRidesWithPower() {
        let rides = [ride(at(2027, 2, 2), minutes: 120, np: 150),                         // IF 0.60 ✓
                     ride(at(2027, 2, 4), minutes: 60, np: 190),                          // IF 0.76 ✗
                     ride(at(2027, 2, 6), minutes: 90, np: 187),                          // IF 0.748 ✓
                     ride(at(2027, 2, 8), minutes: 60, np: nil),                          // no power ✗
                     ride(at(2027, 2, 9), minutes: 60, np: 150, id: 5),               // ✓
                     ride(at(2027, 2, 10), minutes: 60, np: 150).withAverageOnly(150),    // avg 150 × 1.05 = 157 → 0.63 ✓
                     ride(at(2027, 2, 11), minutes: 60, np: 150, id: 6).withIndoor(false), // outdoor ✗
                     ride(at(2027, 1, 31, 23), minutes: 60, np: 150)]                      // January ✗
        let c = find(Challenges.season(rides: rides, ftp: 250, now: at(2027, 2, 12), calendar: cal), .februarFundament)
        #expect(c.progress == 120 + 90 + 60 + 60)
        #expect(c.goal == 600)
        #expect(c.progressText == "5,5 von 10 h")
        #expect(c.remainingText == "noch 4,5 h")
        #expect(c.state == .active(daysLeft: 17))   // 12.–28. Feb
    }

    @Test func februaryCompletesAfterTenHours() {
        let rides = (0..<5).map { ride(at(2027, 2, 1 + $0), minutes: 130, np: 140, id: 70 + $0) }
        let c = find(Challenges.season(rides: rides, ftp: 250, now: at(2027, 2, 10), calendar: cal), .februarFundament)
        #expect(c.state == .completed(on: at(2027, 2, 5)))
        #expect(c.completedByRideID == 74)
    }

    @Test func februaryNeedsAFTP() {
        let rides = [ride(at(2027, 2, 2), minutes: 120, np: 150)]
        let c = find(Challenges.season(rides: rides, ftp: 0, now: at(2027, 2, 12), calendar: cal), .februarFundament)
        #expect(c.progress == 0)
    }

    // MARK: States

    @Test func upcomingCountsDays() {
        let list = Challenges.season(rides: [], ftp: 250, now: at(2026, 12, 20, 23), calendar: cal)
        #expect(find(list, .indoor500).state == .upcoming(daysUntilStart: 4))
        #expect(find(list, .monatsKonstanz, month: 12).isActive)
        #expect(find(list, .monatsKonstanz, month: 11).state == .missed)
    }

    @Test func afterTheSeasonEverythingIsMissedOrCompleted() {
        let list = Challenges.season(rides: [], ftp: 250, now: at(2027, 5, 1), calendar: cal)
        #expect(list.allSatisfy { $0.state == .missed })
        #expect(Challenges.highlight(in: list) == nil)
    }

    // MARK: Highlight

    @Test func highlightPrefersTheSoonestEndingActiveChallenge() {
        let list = Challenges.season(rides: [], ftp: 250, now: at(2026, 12, 28), calendar: cal)
        // Dezember-Konstanz and Indoor-500 both end 31.12.; the one further along (both 0) – tie → stable pick of one active.
        #expect(Challenges.highlight(in: list) != nil)
        #expect(Challenges.highlight(in: list)?.isActive == true)
    }

    @Test func highlightShowsUpcomingWithinSevenDaysOnly() {
        // 1 Aug: November starts in 92 days.
        #expect(Challenges.highlight(in: Challenges.season(rides: [], ftp: 250, now: at(2026, 8, 1), calendar: cal)) == nil)
        let near = Challenges.highlight(in: Challenges.season(rides: [], ftp: 250, now: at(2026, 10, 26), calendar: cal))
        #expect(near?.title == "Monats-Konstanz November")
        #expect(near?.state == .upcoming(daysUntilStart: 6))
    }

    @Test func highlightSkipsCompletedChallenges() {
        let rides = (0..<8).map { ride(at(2026, 11, 1 + $0)) }
        let list = Challenges.season(rides: rides, ftp: 250, now: at(2026, 11, 20), calendar: cal)
        #expect(Challenges.highlight(in: list) == nil)
    }

    @Test func summaryIsSpoken() {
        let rides = (0..<3).map { ride(at(2026, 11, 1 + $0)) }
        let c = find(Challenges.season(rides: rides, ftp: 250, now: at(2026, 11, 20), calendar: cal), .monatsKonstanz, month: 11)
        #expect(Challenges.summary(c) == "Monats-Konstanz November, 3 von 8 Einheiten, noch 5 Einheiten, noch 11 Tage.")
    }
}

private extension RideSummary {
    func withAverageOnly(_ avg: Double) -> RideSummary {
        var r = self
        r.weightedAverageWatts = nil
        r.averageWatts = avg
        return r
    }

    func withIndoor(_ indoor: Bool) -> RideSummary {
        var r = self
        r.trainer = indoor
        r.sportType = indoor ? "VirtualRide" : "Ride"
        return r
    }
}
