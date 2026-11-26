import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

// MARK: - Test helpers

/// Builds small FIT files: one definition + data message per call, little-endian, CRC left at 0 (not checked).
struct FITBuilder {
    private var body: [UInt8] = []

    /// `fields`: (field number, size in bytes, value).
    mutating func message(global: UInt16, local: UInt8 = 0, fields: [(UInt8, Int, UInt64)]) {
        body += [0x40 | local, 0, 0, UInt8(global & 0xFF), UInt8(global >> 8), UInt8(fields.count)]
        for f in fields { body += [f.0, UInt8(f.1), f.1 == 1 ? 0x02 : f.1 == 2 ? 0x84 : 0x86] }
        data(local: local, fields.map { ($0.1, $0.2) })
    }

    mutating func data(local: UInt8 = 0, _ values: [(Int, UInt64)], compressedOffset: UInt8? = nil) {
        body.append(compressedOffset.map { 0x80 | (local & 0x03) << 5 | ($0 & 0x1F) } ?? local)
        for (size, value) in values { for b in 0..<size { body.append(UInt8((value >> (8 * UInt64(b))) & 0xFF)) } }
    }

    var bytes: Data {
        let size = UInt32(body.count)
        let header: [UInt8] = [14, 0x20, 0x08, 0x08, UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF),
                               UInt8(size >> 24), 0x2E, 0x46, 0x49, 0x54, 0, 0]
        return Data(header + body + [0, 0])
    }
}

/// FIT seconds for a Unix date.
func fitTime(_ date: Date) -> UInt64 { UInt64(date.timeIntervalSince1970 - FITParser.fitEpoch) }

let rideStart = Date(timeIntervalSince1970: 1_794_000_000) // Nov 2026

func sessionFIT(start: Date = rideStart) -> Data {
    var fit = FITBuilder()
    fit.message(global: 18, fields: [(2, 4, fitTime(start)), (8, 4, 3_600_000), (9, 4, 3_250_000),
                                     (20, 2, 205), (34, 2, 221), (16, 1, 138), (17, 1, 171), (48, 4, 738_000)])
    return fit.bytes
}

/// Routes by URL: JSON for the activity list, raw bytes for FIT downloads.
final class RoutingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    let route: @Sendable (URLRequest) -> (Int, Data)
    init(_ route: @escaping @Sendable (URLRequest) -> (Int, Data)) { self.route = route }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests.append(request) }
        let (code, body) = route(request)
        return (body, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}

private func token() -> String {
    func b64(_ s: String) -> String {
        Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
    return b64(#"{"alg":"HS256"}"#) + "." + b64(#"{"exp":\#(Int(Date.now.timeIntervalSince1970) + 3600)}"#) + ".sig"
}

private func signedIn() -> MemoryMyWhooshStore {
    MemoryMyWhooshStore(MyWhooshSession(username: "rider@example.com", whooshId: "w-1", accessToken: token(), refreshToken: ""))
}

// MARK: - FIT parser

@Suite("FIT parser")
struct FITParserTests {
    @Test func readsTheSessionSummary() throws {
        let s = try FITParser.summary(from: sessionFIT())
        #expect(s.startDate == rideStart)
        #expect(s.movingTime == 3600 && s.distance == 32_500)
        #expect(s.averageWatts == 205 && s.normalizedPower == 221)
        #expect(s.averageHeartrate == 138 && s.maxHeartrate == 171)
        #expect(s.kilojoules == 738)
    }

    @Test func fallsBackToRecordsWithNormalizedPower() throws {
        var fit = FITBuilder()
        let t0 = fitTime(rideStart)
        fit.message(global: 20, fields: [(253, 4, t0), (7, 2, 200), (3, 1, 140)])
        // 10 min: 5 min at 150 W, 5 min at 250 W → NP above the 200 W average.
        for s in 1...600 { fit.data([(4, t0 + UInt64(s)), (2, s <= 300 ? 150 : 250), (1, 140)]) }
        let summary = try FITParser.summary(from: fit.bytes)
        #expect(summary.movingTime == 600)
        #expect(summary.startDate == rideStart)
        #expect(abs(summary.averageWatts! - 200) < 0.2)
        #expect(summary.normalizedPower! > 205)
        #expect(summary.averageHeartrate == 140)
    }

    @Test func compressedTimestampsRollOver() throws {
        var fit = FITBuilder()
        let t0 = fitTime(rideStart) & ~0x1F | 0x1E                 // offset 30 of a 32 s window
        fit.message(global: 20, fields: [(253, 4, t0), (7, 2, 100)])
        fit.message(global: 20, local: 1, fields: [(7, 2, 100)])
        fit.data(local: 1, [(2, 100)], compressedOffset: 0x1F)       // +1 s
        fit.data(local: 1, [(2, 100)], compressedOffset: 0x02)       // wraps → +4 s
        let summary = try FITParser.summary(from: fit.bytes)
        #expect(summary.movingTime == 4)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: FITParser.Error.notFIT) { try FITParser.summary(from: Data("kein fit".utf8)) }
        #expect(throws: FITParser.Error.notFIT) { try FITParser.summary(from: Data()) }
    }
}

// MARK: - MyWhoosh history

@Suite("MyWhoosh history")
struct MyWhooshHistoryTests {
    @Test func parsesNestedListsAndFieldVariants() throws {
        let json = #"""
        {"status":true,"data":{"activities":[
          {"_id":"a1","title":"Tempo Tuesday","startTime":1794000000000,"fitFileUrl":"https://mywhooshprod.s3.eu-west-1.amazonaws.com/ride/w-1/a1.fit"},
          {"id":42,"name":"Alpe","date":"2026-11-03T18:00:00Z","duration":3720,"avgPower":231,"downloadUrl":"http://insecure.example/x.fit"},
          {"name":"ohne id"}
        ]}}
        """#
        let list = try #require(MyWhooshActivity.list(from: Data(json.utf8)))
        #expect(list.activities.count == 2)
        #expect(list.responseKeys == ["data", "status"])
        let first = list.activities[0]
        #expect(first.id == "a1" && first.name == "Tempo Tuesday")
        #expect(first.date == Date(timeIntervalSince1970: 1_794_000_000))
        #expect(first.fitURL?.host() == "mywhooshprod.s3.eu-west-1.amazonaws.com")
        let second = list.activities[1]
        #expect(second.id == "42" && second.durationSeconds == 3720 && second.averageWatts == 231)
        #expect(second.fitURL == nil)                                  // plain http is never followed
        #expect(second.date == ISO8601DateFormatter().date(from: "2026-11-03T18:00:00Z"))
    }

    @Test func sendsPageAndSortDateAndPagesUntilEmpty() async throws {
        let transport = RoutingTransport { request in
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            let page = body["page"] as? Int ?? 0
            return (200, Data(#"{"data":{"activities":[\#(page <= 2 ? #"{"id":"p\#(page)"}"# : "")]}}"#.utf8))
        }
        let client = MyWhooshClient(store: signedIn(), transport: transport)
        let list = try await client.activities()
        #expect(list.activities.map(\.id) == ["p1", "p2"])
        #expect(transport.requests.count == 3)
        let first = try #require(try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as? [String: Any])
        #expect(first["page"] as? Int == 1 && first["sortDate"] as? String == "DESC" && first["limit"] != nil)
        #expect(first["offset"] == nil)                                  // answered with 403 by MyWhoosh
        #expect(transport.requests[0].url == MyWhooshClient.activitiesURL && transport.requests[0].httpMethod == "POST")
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
    }

    @Test func retriesWithoutLimitAndStopsAtNotBefore() async throws {
        let old = Int(Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSince1970)
        let transport = RoutingTransport { request in
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            if body["limit"] != nil { return (400, Data(#"{"message":["limit should not exist"]}"#.utf8)) }
            return (200, Data(#"{"activities":[{"id":"a\#(body["page"]!)","startTime":\#(old)}]}"#.utf8))
        }
        let list = try await MyWhooshClient(store: signedIn(), transport: transport)
            .activities(notBefore: Date(timeIntervalSince1970: 1_750_000_000))
        #expect(list.activities.map(\.id) == ["a1"])                    // page 1 already reaches back far enough
        #expect(transport.requests.count == 2)                          // with limit (400), then without
    }

    @Test func unreadableHistoryPointsToTheFITImport() async {
        let client = MyWhooshClient(store: signedIn(), transport: RoutingTransport { _ in (200, Data(#"{"message":"ok"}"#.utf8)) })
        await #expect(throws: MyWhooshError.historyUnavailable) { try await client.activities() }
        #expect(MyWhooshError.historyUnavailable.localizedDescription.contains("FIT"))
    }

    /// Regression: a 401/403 from the undocumented history endpoint signed the user out right after login.
    /// Also for 401: `case 401, 403 where …` applied the condition to 403 only (compiler warning in CI).
    @Test(arguments: [401, 403])
    func historyRefusalKeepsTheSession(status: Int) async {
        let transport = RoutingTransport { _ in (status, Data("<html>\(status)</html>".utf8)) }
        let store = signedIn()
        let client = MyWhooshClient(store: store, transport: transport)
        await #expect(throws: MyWhooshError.historyUnavailable) { try await client.activities() }
        #expect(transport.requests.count == 1 && store.session != nil)
    }

    @Test func loginAcceptsNumericWhooshIdAndKeepsDocumentedRefusal() async throws {
        let ok = RoutingTransport { _ in (200, Data(#"{"Success":true,"WhooshId":123456,"AccessToken":"\#(token())","RefreshToken":"r"}"#.utf8)) }
        let store = MemoryMyWhooshStore()
        try await MyWhooshClient(store: store, transport: ok).login(username: "rider@example.com", password: "pw")
        #expect(store.session?.whooshId == "123456")

        let refused = RoutingTransport { _ in (200, Data(#"{"Success":false,"Message":"Invalid credentials"}"#.utf8)) }
        await #expect(throws: MyWhooshError.loginFailed) {
            try await MyWhooshClient(store: MemoryMyWhooshStore(), transport: refused).login(username: "a", password: "b")
        }
    }

    @MainActor @Test func silentImportAtLaunchOnlyLogsARefusedHistory() async throws {
        // Keep the container alive for the whole test – the context does not retain it.
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(context: container.mainContext,
                             secrets: InMemorySecretStore(), defaults: UserDefaults(suiteName: "t-\(UUID().uuidString)")!,
                             transport: RoutingTransport { _ in (400, Data(#"{"errors":["userId required"]}"#.utf8)) },
                             myWhooshStore: signedIn())
        await model.importMyWhooshRides(announce: false)
        #expect(model.banner == nil && model.isMyWhooshConnected)
        await model.importMyWhooshRides(announce: true)
        #expect(model.banner?.isError == true)
    }

    @Test func errorBodyExcerptIsOneShortLine() {
        let excerpt = MyWhooshClient.bodyExcerpt(Data("{\n  \"errors\": [\"x\"],\n \"pad\": \"\(String(repeating: "y", count: 1_500))\"}".utf8))
        #expect(!excerpt.contains("\n") && excerpt.count == 1_000 && excerpt.hasPrefix(#"{ "errors": ["x"]"#))
    }

    /// Field names as MyWhoosh actually answers (device log, 17.11.2026).
    static let realEntry = #"""
    {"error":false,"data":[{"id":"6744a1","title":"Tempo","routeName":"Alula","sportType":"Cycling","type":"E_Ride",
      "startDatetime":"2026-11-16T17:30:00.000Z","date":"2026-11-16","createdAt":"2026-11-16T18:35:00.000Z",
      "rideDuration":3725,"distance":36.4,"elevation":210,"watt":214,"wattPerKg":2.9,"heartrate":148,
      "activityFileId":"a1b2c3d4-e5f6","totalWorkout":1}]}
    """#

    @Test func readsTheRealMyWhooshFields() throws {
        let list = try #require(MyWhooshActivity.list(from: Data(Self.realEntry.utf8)))
        let a = try #require(list.activities.first)
        #expect(a.id == "6744a1" && a.name == "Tempo")
        #expect(a.date == ISO8601DateFormatter().date(from: "2026-11-16T17:30:00Z"))
        #expect(a.durationSeconds == 3725 && a.distanceMeters == 36_400)
        #expect(a.averageWatts == 214 && a.averageHeartrate == 148)
        #expect(a.fileKey == "a1b2c3d4-e5f6" && a.fitURL == nil)
        #expect(list.sample.contains("rideDuration=") && !list.sample.contains("Alula") && !list.sample.contains("Tempo"))
        #expect(MyWhooshActivity.seconds(NSNumber(value: 62)) == 3720)          // small numbers are minutes
        #expect(MyWhooshActivity.seconds("1:02:05") == 3725)
    }

    @Test func fileKeyGoesToRideStorageWithoutToken() async throws {
        let transport = RoutingTransport { request in
            request.url?.lastPathComponent.hasSuffix(".fit") == true ? (200, Data("fit".utf8)) : (403, Data())
        }
        let client = MyWhooshClient(store: signedIn(), transport: transport)
        let activity = try #require(MyWhooshActivity.list(from: Data(Self.realEntry.utf8))?.activities.first)
        #expect(try await client.downloadFIT(for: activity) == Data("fit".utf8))
        #expect(transport.requests.map { $0.url!.absoluteString } == [
            "https://mywhooshprod.s3.eu-west-1.amazonaws.com/ride/w-1/a1b2c3d4-e5f6",
            "https://mywhooshprod.s3.eu-west-1.amazonaws.com/ride/w-1/a1b2c3d4-e5f6.fit"])
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    @Test func logFileKeepsLinesAcrossLaunchesAndCaps() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = LogFile(url: url)
        file.append(category: "sync", level: "notice", "alt", date: .now.addingTimeInterval(-2 * 86_400))
        file.append(category: "mywhoosh", level: "error", "neu\nzeile")
        let again = LogFile(url: url)                                   // "next launch"
        let lines = again.entries(since: .now.addingTimeInterval(-86_400))
        #expect(lines.count == 1 && lines[0].contains("[mywhoosh] error: neu zeile"))
        for _ in 0..<3_000 { again.append(category: "sync", level: "notice", String(repeating: "x", count: 300)) }
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size <= 512 * 1024 + 400)
        again.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func logRedactionCoversTokensAndEmails() {
        let line = Redactor.scrub("Login ok für rider@example.com, token \(token())")
        #expect(!line.contains("rider@example.com") && !line.contains("eyJ"))
        #expect(MyWhooshClient.serverMessage(["Message": String(repeating: "x", count: 500)])?.count == 160)
    }

    @Test func tokenGoesOnlyToMyWhooshHosts() async throws {
        let transport = RoutingTransport { _ in (200, Data("fit".utf8)) }
        let client = MyWhooshClient(store: signedIn(), transport: transport)
        _ = try await client.downloadFIT(URL(string: "https://mywhooshprod.s3.eu-west-1.amazonaws.com/ride/a.fit")!)
        _ = try await client.downloadFIT(URL(string: "https://service14.mywhoosh.com/v2/file/a.fit")!)
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(transport.requests[1].value(forHTTPHeaderField: "Authorization") != nil)
        await #expect(throws: MyWhooshError.unexpectedResponse) {
            try await client.downloadFIT(URL(string: "http://mywhoosh.com/a.fit")!)
        }
    }
}

// MARK: - Import into the app

/// One ride two days ago, listed by MyWhoosh with a FIT file.
func historyTransport() -> RoutingTransport {
    let recent = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 - 2 * 86_400).rounded())
    return RoutingTransport { request in
        if request.url == MyWhooshClient.activitiesURL {
            let ms = Int(recent.timeIntervalSince1970 * 1000)
            return (200, Data(#"{"activities":[{"id":"r1","name":"Sweet Spot","startTime":\#(ms),"fitFileUrl":"https://cdn.mywhoosh.com/r1.fit"}]}"#.utf8))
        }
        return (200, sessionFIT(start: recent))
    }
}

@Suite("Ride import")
@MainActor
struct RideImportTests {
    let container: ModelContainer
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!

    init() throws {
        container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func model(_ transport: HTTPTransport, store: MyWhooshSessionStore = InMemoryMyWhooshSessionStore()) -> AppModel {
        AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                 transport: transport, myWhooshStore: store)
    }

    func rides(_ model: AppModel) throws -> [StoredRide] { try model.context.fetch(FetchDescriptor<StoredRide>()) }


    @Test func importsRidesReplacesDemoDataAndSkipsKnownOnes() async throws {
        let transport = historyTransport()
        let model = model(transport, store: signedIn())
        model.bootstrap()
        #expect(try model.isDemoMode && !rides(model).isEmpty)

        await model.importMyWhooshRides()
        let stored = try rides(model)
        #expect(stored.count == 1)
        let ride = try #require(stored.first?.summary)
        #expect(ride.name == "Sweet Spot" && ride.isIndoor && !ride.isFromStrava)
        #expect(ride.weightedAverageWatts == 221 && ride.movingTime == 3600)
        #expect(!model.isDemoMode && model.hasImportedRides)
        #expect(model.banner?.message.contains("1 Fahrt importiert") == true)

        let before = transport.requests.count
        await model.importMyWhooshRides()
        #expect(transport.requests.count == before + 2)                 // list pages only, no second FIT download
        #expect(try rides(model).count == 1)
    }

    @Test func listValuesStandInWhenTheFileIsRefused() async throws {
        let recent = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 - 86_400).rounded())
        let iso = ISO8601DateFormatter().string(from: recent)
        let transport = RoutingTransport { request in
            guard request.url == MyWhooshClient.activitiesURL else { return (403, Data()) }
            return (200, Data(#"{"data":[{"id":"r9","title":"Z2","startDatetime":"\#(iso)","rideDuration":3600,"watt":180,"heartrate":131,"distance":30.5,"activityFileId":"k9"}]}"#.utf8))
        }
        let model = model(transport, store: signedIn())
        await model.importMyWhooshRides()
        let ride = try #require(try rides(model).first?.summary)
        #expect(ride.movingTime == 3600 && ride.averageWatts == 180 && ride.averageHeartrate == 131 && ride.distance == 30_500)
        #expect(ride.startDate == recent && ride.isIndoor)
        #expect(model.lastMyWhooshImport != nil)
    }

    @Test func windowStaysOpenWhileRidesAreUnreadable() async throws {
        let transport = RoutingTransport { request in
            guard request.url == MyWhooshClient.activitiesURL else { return (403, Data()) }
            return (200, Data(#"{"data":[{"id":"x1","title":"ohne Dauer","activityFileId":"k1"}]}"#.utf8))
        }
        let model = model(transport, store: signedIn())
        await model.importMyWhooshRides()
        #expect(try rides(model).isEmpty && model.lastMyWhooshImport == nil)
        #expect(model.banner?.isError == true)
    }

    @Test func silentImportDoesNotRaiseSyncErrorForUnreadableRides() async throws {
        let transport = RoutingTransport { request in
            guard request.url == MyWhooshClient.activitiesURL else { return (403, Data()) }
            return (200, Data(#"{"data":[{"id":"x1","title":"ohne Dauer","activityFileId":"k1"}]}"#.utf8))
        }
        let model = model(transport, store: signedIn())
        await model.importMyWhooshRides(announce: false)
        #expect(model.syncErrors[.myWhoosh] == nil)
        await model.importMyWhooshRides(announce: true)
        #expect(model.syncErrors[.myWhoosh] != nil)
    }

    @Test func sameRideFromAnotherSourceIsNotCountedTwice() throws {
        let model = model(RoutingTransport { _ in (500, Data()) })
        let strava = RideSummary(id: 99, name: "Strava", sportType: "VirtualRide", startDate: rideStart, movingTime: 3600, distance: 0)
        model.context.insert(StoredRide(strava))
        let fit = try FITParser.summary(from: sessionFIT(start: rideStart.addingTimeInterval(90)))
        #expect(model.storeImportedRides([RideSummary(fit: fit, id: AppModel.importedRideID("fit:1"), name: "Dup")]) == 0)
        #expect(try rides(model).count == 1)
    }

    @Test func importsFITFilesFromTheFilesApp() throws {
        let model = model(RoutingTransport { _ in (500, Data()) })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = dir.appendingPathComponent("Morning Ride.fit")
        let bad = dir.appendingPathComponent("notes.fit")
        try sessionFIT().write(to: good)
        try Data("nope".utf8).write(to: bad)

        model.importFITFiles([good, bad])
        let stored = try rides(model)
        #expect(stored.count == 1 && stored[0].name == "Morning Ride" && stored[0].stravaID < 0)
        #expect(model.banner?.isError == true && model.banner?.message.contains("1 importiert, 1 nicht lesbar") == true)

        model.importFITFiles([good])
        #expect(try rides(model).count == 1)
        #expect(model.banner?.message == "Diese Fahrten sind schon in der App.")
    }

    @Test func importedIDsAreStableAndNegative() {
        #expect(AppModel.importedRideID("mywhoosh:a1") == AppModel.importedRideID("mywhoosh:a1"))
        #expect(AppModel.importedRideID("mywhoosh:a1") != AppModel.importedRideID("mywhoosh:a2"))
        #expect(AppModel.importedRideID("mywhoosh:a1") < 0)
    }

    @Test func deleteAllDataForgetsTheImport() async throws {
        let model = model(historyTransport(), store: signedIn())
        await model.importMyWhooshRides()
        #expect(model.hasImportedRides)
        await model.deleteAllData()
        #expect(!model.hasImportedRides && model.lastMyWhooshImport == nil)
        #expect(defaults.object(forKey: AppModel.Keys.ridesImported) == nil)
    }
}

// MARK: - Fresh MyWhoosh ride + Mac bridge (device log 26.11.2026)

/// Hands out its rides only from the `availableFrom`-th call on (the Mac had not picked up the file yet).
private final class LateBridgeTransport: BridgeTransport, @unchecked Sendable {
    private let lock = NSLock()
    let rides: [(ride: BridgeRide, fit: Data)]
    let availableFrom: Int
    private(set) var fetches = 0
    init(rides: [(ride: BridgeRide, fit: Data)], availableFrom: Int) { self.rides = rides; self.availableFrom = availableFrom }
    func discover(pairing: Bool) async -> [DiscoveredBridge] { [] }
    func pair(with bridge: DiscoveredBridge, code: String) async throws -> (secret: Data, macName: String) {
        throw BridgeError.authenticationFailed
    }
    func fetchNewRides(macName: String, secret: Data, known: Set<String>) async throws -> [(ride: BridgeRide, fit: Data)] {
        let call = lock.withLock { fetches += 1; return fetches }
        return call < availableFrom ? [] : rides.filter { !known.contains($0.ride.id) }
    }
}

@Suite("Frische MyWhoosh-Fahrt und Mac-Brücke")
@MainActor
struct FreshMyWhooshRideTests {
    let container: ModelContainer
    let secrets = InMemorySecretStore()
    /// The ride ended a minute ago and lasted 10 minutes.
    let end = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 - 60).rounded())
    var start: Date { end.addingTimeInterval(-600) }

    init() throws {
        container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// MyWhoosh as on the device: the unprocessed entry carries the upload time as start, watt 0, the file is refused.
    var listJSON: Data {
        let iso = ISO8601DateFormatter().string(from: end)
        return Data(#"{"data":[{"id":"fresh1","title":"Rolle - Sweet Spot Blöcke","startDatetime":"\#(iso)","createdAt":"\#(iso)","date":\#(Int(end.timeIntervalSince1970)),"rideDuration":"00:10:00.000","watt":0,"heartrate":0,"distance":5.1,"activityFileId":"k1"}]}"#.utf8)
    }

    func listTransport() -> RoutingTransport {
        let json = listJSON
        return RoutingTransport { request in request.url == MyWhooshClient.activitiesURL ? (200, json) : (403, Data()) }
    }

    /// 10 min of 1 Hz power from `start`.
    func bridgeFIT() -> (ride: BridgeRide, fit: Data) {
        var fit = FITBuilder()
        let t0 = fitTime(start)
        fit.message(global: 20, fields: [(253, 4, t0), (7, 2, 150), (3, 1, 140)])
        for s in 1...600 { fit.data([(4, t0 + UInt64(s)), (2, s <= 300 ? 150 : 250), (1, 140)]) }
        let data = fit.bytes
        return (BridgeRide(id: BridgeRide.id(forStart: start), startDate: start, durationSeconds: 600, byteCount: data.count,
                           addedAt: .now), data)
    }

    func model(bridge: BridgeTransport) -> AppModel {
        let model = AppModel(context: container.mainContext, secrets: secrets,
                             defaults: UserDefaults(suiteName: "fresh-\(UUID().uuidString)")!,
                             transport: listTransport(), myWhooshStore: signedIn())
        model.bridge.transport = bridge
        model.bridge.macName = "Mac"
        model.bridge.freshRideRetryDelay = .milliseconds(10)
        secrets.setSecret(Data(repeating: 7, count: 32).base64EncodedString(), for: .bridgeSecret)
        return model
    }

    func rides() throws -> [StoredRide] { try container.mainContext.fetch(FetchDescriptor<StoredRide>()) }

    @Test func uploadTimeIsNotTakenAsStart() throws {
        let list = try #require(MyWhooshActivity.list(from: listJSON))
        #expect(list.activities.first?.date == start)
        // A processed entry (start well before the upload) keeps its start.
        let old = try #require(MyWhooshActivity.list(from: Data(MyWhooshHistoryTests.realEntry.utf8))?.activities.first)
        #expect(old.date == ISO8601DateFormatter().date(from: "2026-11-16T17:30:00Z"))
    }

    @Test func listFirstThenBridgeIsOneRideWithSecondsData() async throws {
        defer { withExtendedLifetime(container) {} }   // a ModelContext does not keep its container alive
        let model = model(bridge: LateBridgeTransport(rides: [bridgeFIT()], availableFrom: 1))
        await model.importMyWhooshRides()
        await model.syncFromBridge(announce: true)
        let stored = try rides()
        #expect(stored.count == 1)
        #expect(stored.first?.name == "Rolle - Sweet Spot Blöcke" && stored.first?.powerCurveData != nil)
        #expect(stored.first?.averageWatts != nil)
    }

    @Test func bridgeFirstThenListKeepsOneRideAndTakesTheListName() async throws {
        defer { withExtendedLifetime(container) {} }
        let model = model(bridge: LateBridgeTransport(rides: [bridgeFIT()], availableFrom: 1))
        await model.syncFromBridge(announce: true)
        await model.importMyWhooshRides()
        let stored = try rides()
        #expect(stored.count == 1 && stored.first?.name == "Rolle - Sweet Spot Blöcke" && stored.first?.powerCurveData != nil)
    }

    @Test func pullToRefreshWaitsForTheMacToHandOverTheFreshRide() async throws {
        defer { withExtendedLifetime(container) {} }
        let bridge = LateBridgeTransport(rides: [bridgeFIT()], availableFrom: 3)
        let model = model(bridge: bridge)
        await model.refreshFromPull()
        let stored = try rides()
        #expect(stored.count == 1 && stored.first?.powerCurveData != nil && stored.first?.secondsData != nil)
        #expect(bridge.fetches == 3 && model.bridge.awaitingSeconds.isEmpty)
        #expect(model.banner?.isError != true)
    }

    @Test func pullToRefreshDoesNotWaitWithoutAFreshRide() async throws {
        defer { withExtendedLifetime(container) {} }
        let bridge = LateBridgeTransport(rides: [], availableFrom: 1)
        let model = model(bridge: bridge)
        model.context.insert(StoredRide(RideSummary(id: AppModel.importedRideID("mywhoosh:fresh1"), name: "x", sportType: "VirtualRide",
                                                    startDate: start, movingTime: 600, distance: 0, trainer: true)))
        try model.context.save()
        await model.refreshFromPull()
        #expect(bridge.fetches == 1)
    }

    @Test func repairMergesTheShiftedDuplicate() throws {
        defer { withExtendedLifetime(container) {} }
        let model = model(bridge: LateBridgeTransport(rides: [], availableFrom: 1))
        let listID = AppModel.importedRideID("mywhoosh:fresh1")
        let listRow = StoredRide(RideSummary(id: listID, name: "Rolle - Sweet Spot Blöcke", sportType: "VirtualRide",
                                             startDate: end.addingTimeInterval(20), movingTime: 600, distance: 5100, trainer: true))
        listRow.perceivedExertion = 6
        model.context.insert(listRow)
        let fit = bridgeFIT()
        let summary = try FITParser.summary(from: fit.fit)
        let measuredID = AppModel.importedRideID("fit:\(Int(summary.startDate.timeIntervalSince1970))")
        model.context.insert(StoredRide(RideSummary(fit: summary, id: measuredID, name: AppModel.bridgeRideName)))
        let workout = StoredWorkout(proposal: DemoCoach.makePlan(model.planContext(wish: "", startToday: true)).workouts[0],
                                    source: .demo, weekFocus: "")
        workout.linkedRideID = listID
        model.context.insert(workout)
        // A back-to-back ride with power is not touched.
        model.context.insert(StoredRide(RideSummary(id: 77, name: "Andere", sportType: "VirtualRide", startDate: end.addingTimeInterval(30),
                                                    movingTime: 600, distance: 0, averageWatts: 180, trainer: true)))
        try model.context.save()

        #expect(model.repairShiftedMyWhooshDuplicates() == 1)
        let stored = try rides()
        #expect(stored.count == 2 && !stored.contains { $0.stravaID == listID })
        let kept = try #require(stored.first { $0.stravaID == measuredID })
        #expect(kept.name == "Rolle - Sweet Spot Blöcke" && kept.perceivedExertion == 6)
        #expect(workout.linkedRideID == measuredID)
        #expect(model.repairShiftedMyWhooshDuplicates() == 0)
    }
}
