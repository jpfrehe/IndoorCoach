import Testing
@testable import IndoorCoachKit

@Suite("Feature tour")
struct FeatureTourTests {
    @Test func hasFivePagesInOrder() {
        #expect(TourPage.allCases.count == 5)
        #expect(TourPage.allCases.first?.title == "Claude plant deine Woche")
        #expect(TourPage.allCases.last?.title == "Fortschritt sehen")
    }

    @Test func everyPageHasTextsAndLabel() {
        for page in TourPage.allCases {
            #expect(!page.title.isEmpty)
            #expect(page.body.count > 20)
            #expect(page.illustrationLabel.count > 20)
        }
        #expect(Set(TourPage.allCases.map(\.title)).count == 5)
        #expect(Set(TourPage.allCases.map(\.illustrationLabel)).count == 5)
    }

    @Test func primaryButtonTitleDependsOnPositionAndContext() {
        #expect(TourPage.primaryTitle(index: 0, context: .onboarding) == "Weiter")
        #expect(TourPage.primaryTitle(index: 3, context: .help) == "Weiter")
        #expect(TourPage.primaryTitle(index: 4, context: .onboarding) == "Los geht’s")
        #expect(TourPage.primaryTitle(index: 4, context: .help) == "Fertig")
    }

    @Test func lastPageDetection() {
        #expect(!TourPage.isLast(index: 3))
        #expect(TourPage.isLast(index: 4))
    }

    @Test func indicatorLabel() {
        #expect(TourPage.indicatorLabel(index: 0) == "Seite 1 von 5")
        #expect(TourPage.indicatorLabel(index: 4) == "Seite 5 von 5")
    }

    @Test func progressHelpersClampAndEase() {
        #expect(TourMath.segment(0.5, from: 0.5, to: 1.0) == 0)
        #expect(TourMath.segment(1.2, from: 0.5, to: 1.0) == 1)
        #expect(abs(TourMath.segment(0.75, from: 0.5, to: 1.0) - 0.5) < 1e-9)
        #expect(TourMath.easeInOut(0) == 0 && TourMath.easeInOut(1) == 1)
        #expect(TourMath.pop(0) == 0)
        #expect(abs(TourMath.pop(1) - 1) < 0.01)
        #expect((0..<100).map { TourMath.pop(Double($0) / 100) }.max()! > 1.02) // overshoots
    }
}

@Suite("App tips")
struct AppTipsTests {
    @Test func ruleKeyMatchesAppModelKey() {
        #expect(AppTips.onboardingCompletedKey == "onboarding.completed.v1")
    }

    @Test func tipCopyIsPresentAndShort() {
        for tip in AppTips.copy {
            #expect(!tip.title.isEmpty)
            #expect(tip.message.count > 10 && tip.message.count < 90)
        }
        #expect(AppTips.copy.count == 4)
        #expect(AppTips.copy.first?.title == "Woche planen")
    }

    @Test func debugModeDecision() {
        #expect(AppTips.testingMode(uiSeed: "demo", uiOnboarding: nil, uiTips: nil) == .hide)
        #expect(AppTips.testingMode(uiSeed: nil, uiOnboarding: "YES", uiTips: nil) == .hide)
        #expect(AppTips.testingMode(uiSeed: "demo", uiOnboarding: nil, uiTips: "YES") == .show)
        #expect(AppTips.testingMode(uiSeed: nil, uiOnboarding: nil, uiTips: nil) == .normal)
    }
}
