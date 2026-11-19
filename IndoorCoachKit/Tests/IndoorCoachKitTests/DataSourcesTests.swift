import Foundation
import Testing
@testable import IndoorCoachKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let watch = HealthSourceRef(name: "Apple Watch", bundleID: "com.apple.health")
private let garmin = HealthSourceRef(name: "Garmin Connect", bundleID: "com.garmin.connect")

@Suite("Datenquellen")
struct DataSourcesTests {
    @Test func everyShownTypeHasAnExplanation() {
        #expect(DataSourceTexts.shownTypes.count == 7)
        for type in DataSourceTexts.shownTypes {
            #expect(!DataSourceTexts.title(for: type).isEmpty)
            #expect(DataSourceTexts.explanation(for: type).count > 20)
        }
    }

    @Test func honestGaps() {
        let text = DataSourceTexts.gaps.joined(separator: "\n")
        #expect(text.contains("Garmin, Whoop und Polar schreiben kein HRV nach Apple Health"))
        #expect(text.contains("MyWhoosh schreibt nicht nach Apple Health"))
        #expect(text.contains("Mac-Brücke"))
    }

    @Test func methodPageCoversTheCalculations() {
        let all = DataSourceTexts.method.map { $0.title + " " + $0.text }.joined(separator: "\n")
        for word in ["hrTSS", "TRIMP", "Härte × Minuten", "Aufwärm-Check", "ERG", "gemessen", "angenommen", "geschätzt", "angegeben"] {
            #expect(all.contains(word), "fehlt: \(word)")
        }
    }

    @Test func usageCountsDaysPerSourceAndFlagsChoice() {
        let days = (0..<10).map { HealthDaily(date: now.addingTimeInterval(-Double($0) * 86_400), metric: .restingHR, value: 50, source: watch) }
            + (0..<3).map { HealthDaily(date: now.addingTimeInterval(-Double($0) * 86_400), metric: .restingHR, value: 51, source: garmin) }
            + [HealthDaily(date: now, metric: .bodyMass, value: 78, source: watch)]
        let usage = HealthSourceUsageBuilder.usage(dailies: days, now: now)
        let resting = usage.filter { $0.metric == .restingHR }
        #expect(resting.map(\.source) == [watch, garmin])   // most days first
        #expect(resting.map(\.days) == [10, 3])
        #expect(HealthSourceUsageBuilder.needsChoice(usage, metric: .restingHR))
        #expect(!HealthSourceUsageBuilder.needsChoice(usage, metric: .bodyMass))
    }

    @Test func oldDaysFallOutOfTheWindow() {
        let old = HealthDaily(date: now.addingTimeInterval(-60 * 86_400), metric: .hrvSDNN, value: 40, source: garmin)
        #expect(HealthSourceUsageBuilder.usage(dailies: [old], now: now).isEmpty)
    }
}
