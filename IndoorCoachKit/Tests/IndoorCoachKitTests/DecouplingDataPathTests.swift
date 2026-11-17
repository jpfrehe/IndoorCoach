import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// 1 Hz FIT at 200 W; heart rate 140 bpm in the first half, `secondHalfHR` in the second (nil = no heart-rate field).
private func hrFIT(secondHalfHR: UInt64?, minutes: Int = 60) -> Data {
    var fit = FITBuilder()
    let t0 = fitTime(rideStart)
    let seconds = minutes * 60
    func hr(_ s: Int) -> UInt64 { s < seconds / 2 ? 140 : (secondHalfHR ?? 0) }
    if secondHalfHR == nil {
        fit.message(global: 20, fields: [(253, 4, t0), (7, 2, 200)])
        for s in 1..<seconds { fit.data([(4, t0 + UInt64(s)), (2, 200)]) }
    } else {
        fit.message(global: 20, fields: [(253, 4, t0), (7, 2, 200), (3, 1, hr(0))])
        for s in 1..<seconds { fit.data([(4, t0 + UInt64(s)), (2, 200), (1, hr(s))]) }
    }
    return fit.bytes
}

@Suite("Decoupling data path")
struct DecouplingDataPathTests {
    @Test func fitSummaryComputesDecoupling() throws {
        let s = try FITParser.summary(from: hrFIT(secondHalfHR: 147))
        let d = try #require(s.decoupling)
        #expect(abs(d - (1 - 140.0 / 147.0) * 100) < 1e-6)
    }

    @Test func heartRateSeriesIsAlignedWithPower() throws {
        let data = hrFIT(secondHalfHR: 147)
        let power = try #require(FITParser.powerSeries(from: data))
        let hr = try #require(FITParser.heartRateSeries(from: data))
        #expect(hr.count == power.count)
        #expect(hr.first == 140 && hr.last == 147)
    }

    @Test func noDecouplingWithoutHeartRateOrForShortRides() throws {
        #expect(try FITParser.summary(from: hrFIT(secondHalfHR: nil)).decoupling == nil)
        #expect(try FITParser.summary(from: hrFIT(secondHalfHR: 147, minutes: 15)).decoupling == nil)
    }

    @Test func rideSummaryFromFITCarriesDecoupling() throws {
        let ride = RideSummary(fit: try FITParser.summary(from: hrFIT(secondHalfHR: 147)), id: -9, name: "x")
        #expect(ride.decoupling != nil)
    }

    @Test func storedRideKeepsDecouplingOnSummaryOnlyUpdate() throws {
        var fitRide = RideSummary(id: 1, name: "a", sportType: "VirtualRide", startDate: rideStart, movingTime: 3600, distance: 1)
        fitRide.decoupling = 3.2
        let stored = StoredRide(fitRide)
        #expect(stored.summary.decoupling == 3.2)
        var sync = fitRide
        sync.decoupling = nil
        sync.name = "synced"
        stored.update(from: sync)
        #expect(stored.name == "synced")
        #expect(stored.decoupling == 3.2)
        sync.decoupling = 6.1
        stored.update(from: sync)
        #expect(stored.decoupling == 6.1)
    }

    @MainActor @Test func fitImportStoresDecoupling() throws {
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
                             transport: RoutingTransport { _ in (500, Data()) }, myWhooshStore: InMemoryMyWhooshSessionStore())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("d-\(UUID().uuidString).fit")
        try hrFIT(secondHalfHR: 147).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        model.importFITFiles([url])
        let stored = try container.mainContext.fetch(FetchDescriptor<StoredRide>())
        #expect(stored.count == 1)
        #expect(stored.first?.decoupling != nil)
    }

    @Test func demoRidesHaveDeterministicDecouplingAndImprovingEfficiency() throws {
        let a = DemoData.rides(endingAt: rideStart), b = DemoData.rides(endingAt: rideStart)
        #expect(a.map(\.decoupling) == b.map(\.decoupling))
        #expect(a.allSatisfy { ($0.decoupling ?? -99) > -3 && ($0.decoupling ?? 99) < 12 })
        let trend = try #require(AerobicEfficiency.trend(rides: a, ftp: 250, now: rideStart))
        #expect(trend.direction == .improving, "demo trend: \(trend.changePercent)")
        #expect(trend.changePercent > 3 && trend.changePercent < 8)
        let series = AerobicEfficiency.weeklySeries(rides: a, ftp: 250, from: rideStart.addingTimeInterval(-84 * 86_400), to: rideStart)
        #expect(series.count >= 8)
    }
}
