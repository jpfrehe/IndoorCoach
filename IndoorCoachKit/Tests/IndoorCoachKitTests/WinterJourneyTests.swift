import Testing
@testable import IndoorCoachKit

@Suite("Winter-Reise")
struct WinterJourneyTests {
    @Test func tenStagesMatchTheTenLevels() {
        #expect(WinterJourney.stages.count == WinterArc.levels.count)
        #expect(WinterJourney.stages.map(\.number) == Array(1...10))
        #expect(WinterJourney.stages.first?.place == "Garmisch")
        #expect(WinterJourney.stages[1].place == "Fernpass")
        #expect(WinterJourney.stages.last?.place == "Gardasee")
        #expect(Set(WinterJourney.stages.map(\.place)).count == 10)
    }

    @Test func positionFollowsLevelAndLevelProgress() {
        let p = WinterJourney.position(level: 2, levelProgress: 0.4)
        #expect(p.stage.place == "Fernpass")
        #expect(p.percent == 40)
        #expect(abs(p.routeFraction - (1.4 / 9)) < 1e-9)
        #expect(p.next?.place == "Reschen")
    }

    @Test func startAndFinish() {
        let start = WinterJourney.position(level: 1, levelProgress: 0)
        #expect(start.routeFraction == 0 && start.percent == 0)
        let end = WinterJourney.position(level: 10, levelProgress: 1)
        #expect(end.routeFraction == 1 && end.percent == 100 && end.next == nil)
    }

    @Test func outOfRangeInputIsClamped() {
        #expect(WinterJourney.position(level: 0, levelProgress: -3).stage.number == 1)
        #expect(WinterJourney.position(level: 99, levelProgress: 7).stage.number == 10)
        #expect(WinterJourney.position(level: 3, levelProgress: 7).percent == 100)
    }

    @Test func voiceOverLabel() {
        let p = WinterJourney.position(level: 2, levelProgress: 0.4)
        #expect(p.accessibilityLabel == "Etappe 2 von 10: Fernpass, 40 % geschafft")
    }
}
