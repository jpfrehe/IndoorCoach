import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Postkarten · Vertrag (AP0)")
struct PostcardsContractTests {
    private let dates: [Int: Date] = [1: Date(timeIntervalSince1970: 1_000), 2: Date(timeIntervalSince1970: 2_000),
                                      3: Date(timeIntervalSince1970: 3_000), 4: Date(timeIntervalSince1970: 4_000)]

    @Test func tenCardsFollowTheJourney() {
        let cards = Postcards.all(level: 1, levelProgress: 0, levelDates: [:])
        #expect(cards.count == 10)
        #expect(cards.map(\.stage) == Array(1...10))
        #expect(cards.map(\.place) == WinterJourney.stages.map(\.place))
        #expect(cards.map(\.elevation) == WinterJourney.stages.map(\.elevation))
        #expect(cards.allSatisfy { !$0.text.isEmpty })
        #expect(cards.map(\.id) == Array(1...10))
    }

    @Test func levelNUnlocksOneToNAndGarmischAlways() {
        let cards = Postcards.all(level: 4, levelProgress: 0.62, levelDates: dates)
        #expect(cards.filter(\.unlocked).map(\.stage) == [1, 2, 3, 4])
        #expect(cards[3].arrivedOn == dates[4])
        #expect(cards[4].arrivedOn == nil)
        let start = Postcards.all(level: 0, levelProgress: 0, levelDates: [:])
        #expect(start[0].unlocked)
        #expect(start[0].arrivedOn == nil) // no date known, none invented
        #expect(start.dropFirst().allSatisfy { !$0.unlocked })
    }

    @Test func nextLockedCardCarriesThePercentToGo() {
        let cards = Postcards.all(level: 4, levelProgress: 0.62, levelDates: dates)
        #expect(cards[4].percentToNext == 38)
        #expect(cards[5].percentToNext == nil)
        #expect(cards[3].percentToNext == nil)
        let done = Postcards.all(level: 10, levelProgress: 1, levelDates: [:])
        #expect(done.allSatisfy { $0.unlocked && $0.percentToNext == nil })
    }

    @Test func outOfRangeInputIsClamped() {
        #expect(Postcards.all(level: 99, levelProgress: 7, levelDates: [:]).allSatisfy { $0.unlocked })
        let low = Postcards.all(level: -3, levelProgress: -1, levelDates: [:])
        #expect(low.filter(\.unlocked).count == 1)
        #expect(low[1].percentToNext == 100)
    }
}
