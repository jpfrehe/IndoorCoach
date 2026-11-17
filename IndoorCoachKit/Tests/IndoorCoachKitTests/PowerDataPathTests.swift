import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// 10 min of records: 5 min at 150 W, a 10 s recording gap, 4:50 at 250 W; plus one absurd 9000 W spike.
private func recordsFIT() -> Data {
    var fit = FITBuilder()
    let t0 = fitTime(rideStart)
    fit.message(global: 20, fields: [(253, 4, t0), (7, 2, 150)])
    for s in 1..<300 { fit.data([(4, t0 + UInt64(s)), (2, s == 100 ? 9000 : 150)]) }
    for s in 310...600 { fit.data([(4, t0 + UInt64(s)), (2, 250)]) }
    return fit.bytes
}

@Suite("Power data path")
struct PowerDataPathTests {
    @Test func resamplesToOneHertzFillsGapsAndCapsSpikes() throws {
        let series = try #require(FITParser.powerSeries(from: recordsFIT()))
        #expect(series.count == 601)
        #expect(series[0] == 150 && series[299] == 150)
        #expect(series[100] == 0)                         // 9000 W spike dropped
        #expect(series[300] == 0 && series[309] == 0)     // gap
        #expect(series[310] == 250 && series[600] == 250)
    }

    @Test func summaryCarriesMaxWattsAndCurve() throws {
        let s = try FITParser.summary(from: recordsFIT())
        #expect(s.maxWatts == 250)
        let curve = try #require(s.powerCurve)
        #expect(curve[1] == 250)
        #expect(curve[240] == 250)
        #expect(abs((curve[300] ?? 0) - 242.5) < 1e-9)   // last 300 s: 9 s of gap (0 W) + 291 s at 250 W
    }

    @Test func fileWithoutPowerHasNoCurve() throws {
        let s = try FITParser.summary(from: sessionFIT())
        #expect(s.powerCurve == nil)
    }

    @Test func rideSummaryFromFITKeepsCurve() throws {
        let fit = try FITParser.summary(from: recordsFIT())
        let ride = RideSummary(fit: fit, id: -5, name: "x")
        #expect(ride.maxWatts == 250 && ride.powerCurve?[1] == 250)
    }

    @Test func stravaMaxWattsIsMapped() throws {
        let json = #"[{"id":1,"name":"n","sport_type":"VirtualRide","start_date":"2026-11-01T10:00:00Z","moving_time":3600,"distance":1,"average_watts":200,"max_watts":640}]"#
        let dto = try #require(try StravaActivityDTO.decodeList(Data(json.utf8)).first)
        #expect(dto.summary.maxWatts == 640)
    }

    @Test func storedRideRoundTripsAndKeepsCurveOnResync() {
        var r = RideSummary(id: 1, name: "a", sportType: "VirtualRide", startDate: rideStart, movingTime: 3600, distance: 1)
        r.powerCurve = [5: 700, 300: 320]
        r.maxWatts = 800
        let stored = StoredRide(r)
        #expect(stored.summary.powerCurve == [5: 700, 300: 320] && stored.summary.maxWatts == 800)

        var strava = RideSummary(id: 1, name: "renamed", sportType: "VirtualRide", startDate: rideStart, movingTime: 3600, distance: 1)
        strava.maxWatts = 810
        stored.update(from: strava)
        #expect(stored.name == "renamed")
        #expect(stored.summary.powerCurve == [5: 700, 300: 320])   // not wiped
        #expect(stored.summary.maxWatts == 810)
    }

    @Test func demoRidesHaveDeterministicMeasuredCurves() {
        let a = DemoData.rides(endingAt: rideStart)
        let b = DemoData.rides(endingAt: rideStart)
        #expect(!a.isEmpty && a.allSatisfy { $0.powerCurve?[300] != nil })
        #expect(a.map(\.powerCurve) == b.map(\.powerCurve))
        for r in a { #expect((r.powerCurve?[5] ?? 0) >= (r.powerCurve?[300] ?? .infinity)) }
    }

    @MainActor @Test func fitImportStoresTheCurve() throws {
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
                             transport: RoutingTransport { _ in (500, Data()) }, myWhooshStore: InMemoryMyWhooshSessionStore())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("p-\(UUID().uuidString).fit")
        try recordsFIT().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        model.importFITFiles([url])
        let stored = try container.mainContext.fetch(FetchDescriptor<StoredRide>())
        #expect(stored.count == 1 && stored[0].summary.powerCurve?[1] == 250)
    }
}
