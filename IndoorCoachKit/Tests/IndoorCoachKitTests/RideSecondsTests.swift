import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Ride seconds (stored 1 Hz data)")
struct RideSecondsTests {
    @Test func roundTripsPowerAndHeartRate() throws {
        let seconds = RideSeconds(power: [0, 150, 2500, 310], heartRate: [0, 120, 181, 255])
        let decoded = try #require(RideSeconds.decode(seconds.encoded()))
        #expect(decoded == seconds)
    }

    @Test func roundTripsWithoutHeartRateAndClampsPower() throws {
        let seconds = RideSeconds(watts: [100.4, 99_999, -3], beatsPerMinute: nil)
        #expect(seconds.power == [100, UInt16.max, 0])
        let decoded = try #require(RideSeconds.decode(seconds.encoded()))
        #expect(decoded.heartRate == nil)
        #expect(decoded.power == seconds.power)
    }

    @Test func rejectsGarbageAndOversizedSeries() {
        #expect(RideSeconds.decode(Data([1, 2, 3])) == nil)
        #expect(RideSeconds.decode(Data()) == nil)
        var header = Data([RideSeconds.formatVersion, 0])
        let count = UInt32(FITParser.maxSeriesSeconds + 1)
        withUnsafeBytes(of: count.littleEndian) { header.append(contentsOf: $0) }
        #expect(RideSeconds.decode(header) == nil)
    }

    @Test func fitSummaryCarriesTheSeconds() throws {
        var fit = FITBuilder()
        let t0 = fitTime(rideStart)
        fit.message(global: 20, fields: [(253, 4, t0), (7, 2, 150), (3, 1, 120)])
        for s in 1..<120 { fit.data([(4, t0 + UInt64(s)), (2, 150 + UInt64(s % 3)), (1, 121)]) }
        let summary = try FITParser.summary(from: fit.bytes)
        let seconds = try #require(summary.seconds)
        #expect(seconds.power.count == 120)
        #expect(seconds.heartRate?.count == 120)
        #expect(seconds.power[0] == 150)
    }

    @MainActor @Test func importStoresSecondsAndFillsThemInForCompleteRides() throws {
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "secs-\(UUID().uuidString)")!,
                             transport: RoutingTransport { _ in (500, Data()) }, myWhooshStore: InMemoryMyWhooshSessionStore())
        var ride = RideSummary(id: 77, name: "FIT", sportType: "VirtualRide", startDate: rideStart, movingTime: 600,
                               distance: 0, averageWatts: 200, trainer: true)
        ride.powerCurve = [5: 300, 60: 250]
        let seconds = RideSeconds(power: Array(repeating: 200, count: 600), heartRate: nil)
        // Ride already complete (curve) but without stored seconds: the seconds are added.
        _ = model.mergeImportedRides([ride])
        #expect(model.rideSeconds(id: 77) == nil)
        _ = model.mergeImportedRides([ride], seconds: [77: seconds])
        #expect(model.rideSeconds(id: 77) == seconds)

        // Enrichment of a list ride (other id, same start) moves the seconds to the stored ride.
        var listRide = RideSummary(id: 88, name: "Liste", sportType: "VirtualRide", startDate: rideStart.addingTimeInterval(86_400),
                                   movingTime: 600, distance: 0, averageWatts: 190, trainer: true)
        _ = model.mergeImportedRides([listRide])
        listRide.id = 99
        listRide.powerCurve = [5: 280]
        _ = model.mergeImportedRides([listRide], seconds: [99: seconds])
        #expect(model.rideSeconds(id: 88) == seconds)
    }
}
