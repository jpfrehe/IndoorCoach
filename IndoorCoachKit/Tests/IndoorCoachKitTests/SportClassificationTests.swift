import Testing
@testable import IndoorCoachKit

@Suite("SportClassification")
struct SportClassificationTests {
    @Test func cycling() {
        for n in ["cycling", "indoorCycling", "handCycling", "HKWorkoutActivityTypeCycling", "Rad", "Indoor Cycling"] {
            #expect(SportClassification.category(for: n) == .cycling, "\(n)")
        }
    }

    @Test func aerobic() {
        for n in ["running", "walking", "hiking", "crossCountrySkiing", "downhillSkiing", "snowboarding", "rowing",
                  "elliptical", "swimming", "Laufband", "Rudergerät", "Kurs", "stairClimbing"] {
            #expect(SportClassification.category(for: n) == .aerobic, "\(n)")
        }
    }

    @Test func muscular() {
        for n in ["traditionalStrengthTraining", "functionalStrengthTraining", "coreTraining", "climbing",
                  "HKWorkoutActivityTypeTraditionalStrengthTraining", "Kraft", "Bouldern", "flexibility"] {
            #expect(SportClassification.category(for: n) == .muscular, "\(n)")
        }
    }

    @Test func mixedNeedsUserDecision() {
        for n in ["hiit", "highIntensityIntervalTraining", "crossTraining", "mixedCardio"] {
            let c = SportClassification.category(for: n)
            #expect(c == .mixed, "\(n)")
            #expect(c.needsUserDecision)
        }
    }

    @Test func ignoreForYogaOtherAndUnknown() {
        for n in ["yoga", "mindAndBody", "other", "Sonstiges", "", "völlig unbekannt"] {
            #expect(SportClassification.category(for: n) == .ignore, "\(n)")
        }
    }

    @Test func normalizationIgnoresCaseSeparatorsAndPrefix() {
        #expect(SportClassification.category(for: "TRADITIONAL_STRENGTH_TRAINING") == .muscular)
        #expect(SportClassification.category(for: "  cross-country skiing ") == .aerobic)
    }

    @Test func feedsFlags() {
        #expect(SportCategory.cycling.feedsBikeLoad && !SportCategory.cycling.feedsMuscleTrack)
        #expect(SportCategory.aerobic.feedsAerobicLoad && !SportCategory.aerobic.feedsMuscleTrack)
        #expect(SportCategory.muscular.feedsMuscleTrack && !SportCategory.muscular.feedsAerobicLoad)
        #expect(!SportCategory.mixed.feedsMuscleTrack && !SportCategory.mixed.feedsAerobicLoad)
        #expect(!SportCategory.ignore.feedsMuscleTrack && !SportCategory.ignore.feedsAerobicLoad && !SportCategory.ignore.feedsBikeLoad)
    }

    @Test func defaultLegShare() {
        #expect(SportClassification.defaultLegShare(for: "climbing") == .light)
        #expect(SportClassification.defaultLegShare(for: "Bouldern") == .light)
        #expect(SportClassification.defaultLegShare(for: "traditionalStrengthTraining") == nil)
        #expect(SportClassification.defaultLegShare(for: "coreTraining") == LegInvolvement.none)
    }

    @Test func rawValuesStable() {
        #expect(SportCategory.aerobic.rawValue == "aerobic")
        #expect(SportCategory.muscular.rawValue == "muscular")
    }
}
