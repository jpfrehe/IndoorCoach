import Testing
@testable import IndoorCoachKit

/// docs/20 §5.2/§6.3: „Noch keine App“ und „Nichts davon“ sind exklusiv.
@Suite("Auswahlregeln der Kacheln")
struct ChoiceSelectionTests {
    @Test func tappingAnAnswerAddsAndRemovesIt() {
        var set: Set<RideApp> = []
        set = ChoiceSelection.toggled(set, .zwift, exclusive: [.none])
        set = ChoiceSelection.toggled(set, .rouvy, exclusive: [.none])
        #expect(set == [.zwift, .rouvy])
        set = ChoiceSelection.toggled(set, .zwift, exclusive: [.none])
        #expect(set == [.rouvy])
    }

    @Test func theExclusiveTileClearsEverythingElse() {
        let set = ChoiceSelection.toggled([RideApp.zwift, .myWhoosh], .none, exclusive: [.none])
        #expect(set == [.none])
    }

    @Test func anyOtherTileClearsTheExclusiveOne() {
        let set = ChoiceSelection.toggled([ExtraGear.none], .heartStrap, exclusive: [.none])
        #expect(set == [.heartStrap])
    }

    @Test func tappingTheExclusiveTileAgainEmptiesTheSelection() {
        let set = ChoiceSelection.toggled([ExtraGear.none], .none, exclusive: [.none])
        #expect(set.isEmpty)
    }
}
