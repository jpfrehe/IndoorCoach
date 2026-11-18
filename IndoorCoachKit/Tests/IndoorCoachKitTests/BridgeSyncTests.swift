import Foundation
import Network
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Transport double: canned rides, optional failure, counts the calls.
final class FakeBridgeTransport: BridgeTransport, @unchecked Sendable {
    private let lock = NSLock()
    var rides: [(ride: BridgeRide, fit: Data)] = []
    var failure: BridgeError?
    var correctCode = "482913"
    private(set) var fetches = 0
    private(set) var lastKnown: Set<String> = []

    func discover(pairing: Bool) async -> [DiscoveredBridge] {
        [DiscoveredBridge(name: "Mac", endpoint: .service(name: "Mac", type: Bridge.pairingServiceType, domain: "local.", interface: nil))]
    }

    func pair(with bridge: DiscoveredBridge, code: String) async throws -> (secret: Data, macName: String) {
        guard code == correctCode else { throw BridgeError.authenticationFailed }
        return (Data(repeating: 7, count: 32), "Lenas MacBook Air")
    }

    func fetchNewRides(macName: String, secret: Data, known: Set<String>) async throws -> [(ride: BridgeRide, fit: Data)] {
        lock.withLock { fetches += 1; lastKnown = known }
        if let failure { throw failure }
        return rides.filter { !known.contains($0.ride.id) }
    }
}

/// 10 min of 1 Hz records starting at `start` (5 min at 150 W, 5 min at 250 W) plus a heart rate.
private func powerFIT(start: Date) -> Data {
    var fit = FITBuilder()
    let t0 = fitTime(start)
    fit.message(global: 20, fields: [(253, 4, t0), (7, 2, 150), (3, 1, 140)])
    for s in 1...600 { fit.data([(4, t0 + UInt64(s)), (2, s <= 300 ? 150 : 250), (1, 140)]) }
    return fit.bytes
}

private func bridgeRide(_ start: Date, fit: Data) -> (ride: BridgeRide, fit: Data) {
    (BridgeRide(id: BridgeRide.id(forStart: start), startDate: start, durationSeconds: 600, byteCount: fit.count, addedAt: .now), fit)
}

@MainActor
@Suite("Mac-Brücke iPhone")
struct BridgeSyncTests {
    let container: ModelContainer
    let model: AppModel
    let secrets = InMemorySecretStore()
    let transport = FakeBridgeTransport()
    let defaults: UserDefaults

    init() throws {
        container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defaults = UserDefaults(suiteName: "bridge-\(UUID().uuidString)")!
        model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults,
                         transport: RoutingTransport { _ in (500, Data()) }, myWhooshStore: InMemoryMyWhooshSessionStore())
        model.bridge.transport = transport
    }

    func rides() throws -> [StoredRide] { try container.mainContext.fetch(FetchDescriptor<StoredRide>()) }

    func pair(code: String = "482913") async throws -> BridgeSyncSummary {
        let mac = try #require(await model.discoverBridges().first)
        return try await model.pairBridge(mac, code: code)
    }

    @Test func wrongCodeStoresNothing() async throws {
        let mac = try #require(await model.discoverBridges().first)
        await #expect(throws: BridgeError.authenticationFailed) { try await model.pairBridge(mac, code: "000000") }
        #expect(!model.isBridgePaired && secrets.secret(.bridgeSecret) == nil && model.bridgeMacName == nil)
    }

    @Test func pairingStoresTheSecretInTheKeychainStoreAndPicksUp() async throws {
        let existing = RideSummary(id: 5, name: "Strava", sportType: "VirtualRide", startDate: rideStart, movingTime: 600, distance: 0,
                                   averageWatts: 200, trainer: true)
        model.context.insert(StoredRide(existing))
        transport.rides = [bridgeRide(rideStart.addingTimeInterval(90), fit: powerFIT(start: rideStart.addingTimeInterval(90))),
                           bridgeRide(rideStart.addingTimeInterval(-86_400), fit: powerFIT(start: rideStart.addingTimeInterval(-86_400)))]
        let summary = try await pair()
        #expect(model.isBridgePaired && model.bridgeMacName == "Lenas MacBook Air")
        #expect(Data(base64Encoded: try #require(secrets.secret(.bridgeSecret))) == Data(repeating: 7, count: 32))
        #expect(summary.received == 2 && summary.inserted == 1 && summary.enriched == 1)
        let stored = try rides()
        #expect(stored.count == 2)
        let enriched = try #require(stored.first { $0.stravaID == 5 })
        #expect(enriched.name == "Strava" && enriched.powerCurve?[300] == 250 && enriched.maxWatts == 250)
        let coverage = model.secondsCoverage()
        #expect(coverage.measured == 2 && coverage.total == 2)
        #expect(model.lastBridgeSync != nil)
    }

    @Test func knownIDsArePassedAndPersisted() async throws {
        transport.rides = [bridgeRide(rideStart, fit: powerFIT(start: rideStart))]
        _ = try await pair()
        #expect(transport.lastKnown.isEmpty)
        _ = await model.syncFromBridge(announce: true)
        #expect(transport.lastKnown == [BridgeRide.id(forStart: rideStart)])
        #expect(defaults.stringArray(forKey: AppModel.Keys.bridgeKnownIDs) == [BridgeRide.id(forStart: rideStart)])
        #expect(try rides().count == 1)
    }

    @Test func bannerNamesASingleNewRideOtherwiseTheCounts() async throws {
        transport.rides = [bridgeRide(rideStart, fit: powerFIT(start: rideStart))]
        _ = try await pair()
        #expect(model.banner?.message.hasPrefix("Neue Fahrt vom Mac: 10 min · NP ") == true)

        let a = rideStart.addingTimeInterval(86_400), b = rideStart.addingTimeInterval(2 * 86_400)
        transport.rides += [bridgeRide(a, fit: powerFIT(start: a)), bridgeRide(b, fit: powerFIT(start: b))]
        _ = await model.syncFromBridge(announce: true)
        #expect(model.banner?.message == "Vom Mac: 2 neu")

        _ = await model.syncFromBridge(announce: true)
        #expect(model.banner?.message == "Keine neuen Fahrten auf dem Mac.")
    }

    @Test func automaticPickupIsThrottledAndSilentWhenUnreachable() async throws {
        _ = try await pair()
        let fetchesAfterPairing = transport.fetches
        _ = await model.syncFromBridge(announce: false)
        #expect(transport.fetches == fetchesAfterPairing)          // within 2 minutes of the last attempt

        model.bridge.lastAttempt = .now.addingTimeInterval(-300)
        transport.failure = .unreachable
        model.banner = nil
        _ = await model.syncFromBridge(announce: false)
        #expect(transport.fetches == fetchesAfterPairing + 1 && model.banner == nil)
    }

    @Test func manualPickupExplainsAnUnreachableMac() async throws {
        _ = try await pair()
        transport.failure = .unreachable
        _ = await model.syncFromBridge(announce: true)
        #expect(model.banner?.isError == true)
        #expect(model.banner?.message == "Mac nicht erreichbar – ist die Brücke geöffnet und seid ihr im selben WLAN?")
    }

    @Test func notPairedDoesNothing() async {
        #expect(await model.syncFromBridge(announce: true) == nil)
        #expect(transport.fetches == 0)
    }

    @Test func unpairForgetsEverythingButKeepsRides() async throws {
        transport.rides = [bridgeRide(rideStart, fit: powerFIT(start: rideStart))]
        _ = try await pair()
        model.unpairBridge()
        #expect(!model.isBridgePaired && secrets.secret(.bridgeSecret) == nil && model.bridgeMacName == nil)
        #expect(defaults.object(forKey: AppModel.Keys.bridgeKnownIDs) == nil)
        #expect(try rides().count == 1)
    }

    @Test func stateSurvivesARelaunch() async throws {
        _ = try await pair()
        let again = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults,
                             myWhooshStore: InMemoryMyWhooshSessionStore())
        #expect(again.isBridgePaired && again.bridgeMacName == "Lenas MacBook Air" && again.lastBridgeSync != nil)
    }

    @Test func unreadableFilesAreNotFetchedAgain() async throws {
        transport.rides = [bridgeRide(rideStart, fit: Data("kaputt".utf8))]
        let summary = try await pair()
        #expect(summary.received == 1 && summary.unreadable == 1 && summary.inserted == 0)
        _ = await model.syncFromBridge(announce: true)
        #expect(transport.lastKnown == [BridgeRide.id(forStart: rideStart)])
    }
}

@MainActor
@Suite("FIT-Import ergänzt")
struct FITEnrichmentTests {
    @Test func fitFileEnrichesAListRideInsteadOfBeingDropped() throws {
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "fit-\(UUID().uuidString)")!,
                             transport: RoutingTransport { _ in (500, Data()) }, myWhooshStore: InMemoryMyWhooshSessionStore())
        let list = RideSummary(id: AppModel.importedRideID("mywhoosh:a1"), name: "Tempo Tuesday", sportType: "VirtualRide",
                               startDate: rideStart.addingTimeInterval(100), movingTime: 600, distance: 0, averageWatts: 190, trainer: true)
        container.mainContext.insert(StoredRide(list))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("e-\(UUID().uuidString).fit")
        try powerFIT(start: rideStart).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        model.importFITFiles([url])
        let stored = try container.mainContext.fetch(FetchDescriptor<StoredRide>())
        #expect(stored.count == 1 && stored[0].name == "Tempo Tuesday" && stored[0].powerCurve?[300] == 250)
        #expect(model.banner?.message == "1 Fahrt mit Sekundendaten ergänzt.")

        model.importFITFiles([url])                  // second time: already complete
        #expect(model.banner?.message == "Diese Fahrten sind schon in der App.")
    }

    @Test func messagesCountInsertedEnrichedAndFailed() {
        func msg(_ i: Int, _ e: Int, _ f: Int) -> String {
            AppModel.fitImportMessage(AppModel.ImportResult(inserted: i, enriched: e, skipped: 0), failed: f)
        }
        #expect(msg(2, 3, 0) == "2 importiert, 3 ergänzt.")
        #expect(msg(2, 3, 1) == "2 importiert, 3 ergänzt, 1 nicht lesbar.")
        #expect(msg(1, 0, 0) == "1 Fahrt importiert.")
        #expect(msg(0, 0, 1) == "Die Datei ist keine lesbare FIT-Aktivität.")
    }
}
