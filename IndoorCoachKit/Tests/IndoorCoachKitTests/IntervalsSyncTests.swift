import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Antwortet wie intervals.icu; Zustand ist von außen steuerbar. Merkt sich alle Anfragen (RoutingTransport).
private final class IntervalsStub: @unchecked Sendable {
    private let lock = NSLock()
    private var _status: Int?
    private var _activities = "[]"
    private var _files: [String: Data] = [:]
    private var _tokenScope = "ACTIVITY:READ,CALENDAR:WRITE"

    var status: Int? { get { lock.withLock { _status } } set { lock.withLock { _status = newValue } } }
    var activitiesJSON: String { get { lock.withLock { _activities } } set { lock.withLock { _activities = newValue } } }
    private var _fileStatus: [String: Int] = [:]
    func setFile(_ id: String, _ data: Data) { lock.withLock { _files[id] = data } }
    /// Antwortcode für die Datei einer Aktivität (nil hebt auf).
    func setFileStatus(_ id: String, _ status: Int?) { lock.withLock { _fileStatus[id] = status } }

    private var log: [URLRequest] = []
    /// Alle Anfragen seit dem letzten `reset()`.
    var all: [URLRequest] { lock.withLock { log } }
    func reset() { lock.withLock { log = [] } }

    lazy var transport = RoutingTransport { [unowned self] request in self.route(request) }

    private func route(_ request: URLRequest) -> (Int, Data) {
        lock.withLock { log.append(request) }
        let path = request.url?.path ?? ""
        if let status = status { return (status, Data("{}".utf8)) }
        if path == "/api/oauth/token" {
            return (200, Data(#"{"access_token":"tok-OAUTH-123456","scope":"ACTIVITY:READ,CALENDAR:WRITE","athlete":{"id":"i9","name":"Oskar"}}"#.utf8))
        }
        if path == "/api/v1/athlete/0" { return (200, Data(#"{"id":"i1","name":"Jan"}"#.utf8)) }
        if path == "/api/v1/athlete/0/activities" { return (200, Data(activitiesJSON.utf8)) }
        if path.hasSuffix("/file") {
            let id = path.split(separator: "/").dropLast().last.map(String.init) ?? ""
            if let code = lock.withLock({ _fileStatus[id] }) { return (code, Data()) }
            if let file = lock.withLock({ _files[id] }) { return (200, file) }
            return (404, Data())
        }
        return (200, Data("[]".utf8))
    }

    func requests(_ suffix: String) -> [URLRequest] { all.filter { $0.url?.path.hasSuffix(suffix) == true } }
}

/// Reicht an einen Transport weiter; kann Anfragen anhalten (Wettlauf-Tests) oder Fehler werfen.
private final class HookTransport: HTTPTransport, @unchecked Sendable {
    let inner: HTTPTransport
    let hook: (@Sendable (URLRequest) throws -> Void)?
    private let lock = NSLock()
    private var held: String?
    private var reached = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    init(_ inner: HTTPTransport, hook: (@Sendable (URLRequest) throws -> Void)? = nil) { self.inner = inner; self.hook = hook }

    func holdPath(_ suffix: String) { lock.withLock { held = suffix; reached = false; released = false } }
    func release() {
        let w = lock.withLock { () -> CheckedContinuation<Void, Never>? in released = true; defer { waiter = nil }; return waiter }
        w?.resume()
    }
    func waitUntilReached() async {
        for _ in 0..<500 {
            if lock.withLock({ reached }) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("request never reached the gate")
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try hook?(request)
        let hold = lock.withLock { held.map { request.url?.path.hasSuffix($0) == true && !released } ?? false }
        if hold {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    reached = true
                    if released { return true }
                    waiter = c
                    return false
                }
                if resumeNow { c.resume() }
            }
        }
        return try await inner.data(for: request)
    }
}

private func jsonBody<T>(_ request: URLRequest, as type: T.Type) throws -> T {
    let body = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: body) as? T)
}

private func recordsFIT(start: Date, seconds: Int = 600) -> Data {
    var fit = FITBuilder()
    let t0 = fitTime(start)
    fit.message(global: 20, fields: [(253, 4, t0), (7, 2, 200), (3, 1, 140)])
    for s in 1...seconds { fit.data([(4, t0 + UInt64(s)), (2, 200), (1, 140)]) }
    return fit.bytes
}

private func activityJSON(id: String, start: Date, source: String = "ZWIFT", type: String = "VirtualRide", seconds: Int = 600) -> String {
    let iso = ISO8601DateFormatter().string(from: start)
    return #"{"id":"\#(id)","name":"Fahrt \#(id)","type":"\#(type)","start_date":"\#(iso)","moving_time":\#(seconds),"distance":15000,"icu_average_watts":200,"average_heartrate":140,"trainer":true,"source":"\#(source)"}"#
}

@MainActor
@Suite("intervals.icu · App-Anbindung")
struct IntervalsSyncTests {
    let container: ModelContainer
    let defaults: UserDefaults
    let secrets = InMemorySecretStore()
    fileprivate let stub = IntervalsStub()
    let model: AppModel
    let planned = WorkoutDefinition(title: "Sweet Spot 2×20", type: .sweetSpot, summary: "s", segments: [
        .warmup(10, from: 0.45, to: 0.75), .intervals(2, on: 1200, at: 0.9, off: 300, at: 0.55), .cooldown(10, from: 0.65, to: 0.4)])

    init(clientID: String = "") throws {
        container = try AppEnvironment.makeContainer(inMemory: true)
        defaults = UserDefaults(suiteName: "intervals-\(UUID().uuidString)")!
        model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: stub.transport,
                         myWhooshStore: InMemoryMyWhooshSessionStore(), intervalsConfig: IntervalsConfig(clientID: clientID))
    }

    func connect() async {
        await model.connectIntervals(apiKey: "key-123456")
        stub.reset()
    }

    func makeWorkout(daysAhead: Int = 1) -> StoredWorkout {
        let date = Calendar.current.date(byAdding: .day, value: daysAhead, to: .now)!
        let w = StoredWorkout(proposal: PlannedWorkoutProposal(date: date, definition: planned, rationale: "r"), source: .manual, weekFocus: nil)
        container.mainContext.insert(w)
        return w
    }

    func rides() throws -> [StoredRide] { try container.mainContext.fetch(FetchDescriptor<StoredRide>()) }

    // MARK: Verbinden

    @Test func connectingWithAnAPIKeyShowsNameAndImportsTheHistory() async throws {
        stub.activitiesJSON = "[" + activityJSON(id: "i1", start: .now.addingTimeInterval(-86_400 * 3)) + "]"
        stub.setFile("i1", recordsFIT(start: .now.addingTimeInterval(-86_400 * 3)))
        await model.connectIntervals(apiKey: " key-123456 ")
        #expect(model.isIntervalsConnected && model.intervalsUsesAPIKey && model.intervalsAthleteName == "Jan")
        #expect(secrets.secret(.intervalsCredential)?.contains("key-123456") == true)
        #expect(try rides().count == 1)
        #expect(model.lastIntervalsImport != nil)
        #expect(model.syncErrors[.intervalsICU] == nil)
        // First import: 210 days back.
        let activities = try #require(stub.requests("/activities").first)
        let oldest = try #require(URLComponents(url: activities.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "oldest" }?.value)
        let expected = Calendar.current.date(byAdding: .day, value: -210, to: .now)!
        #expect(oldest == IntervalsClient.dayFormatter().string(from: expected))
    }

    @Test func aWrongAPIKeyConnectsNothing() async {
        stub.status = 401
        await model.connectIntervals(apiKey: "falsch-123456")
        #expect(!model.isIntervalsConnected && secrets.secret(.intervalsCredential) == nil)
        #expect(model.banner?.isError == true && model.banner?.message.contains("API-Key") == true)
        #expect(stub.all.count == 1)
    }

    @Test func oauthIsRefusedWithoutAClientID() async {
        var asked = false
        await model.connectIntervals { _ in asked = true; return URL(string: "indoorcoach://localhost/intervals")! }
        #expect(!asked && stub.all.isEmpty && !model.isIntervalsConnected)
        #expect(model.banner?.isError == true)
        #expect(model.banner?.message == IntervalsError.notConfigured.localizedDescription)
    }

    @Test func oauthFlowUsesPKCEAndStoresTheToken() async throws {
        let model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: stub.transport,
                             myWhooshStore: InMemoryMyWhooshSessionStore(), intervalsConfig: IntervalsConfig(clientID: "cid-77"))
        var authorizeURL: URL?
        await model.connectIntervals { url in
            authorizeURL = url
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "indoorcoach://localhost/intervals?code=CODE1&state=\(state)")!
        }
        let url = try #require(authorizeURL)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let challenge = try #require(items.first { $0.name == "code_challenge" }?.value)
        let token = try #require(stub.requests("/oauth/token").first)
        let tokenBody = try #require(token.httpBody)
        let body = String(decoding: tokenBody, as: UTF8.self)
        let verifier = try #require(body.split(separator: "&").first { $0.hasPrefix("code_verifier=") }.map { String($0.dropFirst(14)) })
        #expect(IntervalsPKCE.challenge(for: verifier) == challenge)
        #expect(!body.contains("client_secret") && body.contains("client_id=cid-77"))
        #expect(model.isIntervalsConnected && !model.intervalsUsesAPIKey && model.intervalsAthleteName == "Oskar")
    }

    @Test func aCancelledSignInShowsTheErrorAndStoresNothing() async {
        let model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: stub.transport,
                             myWhooshStore: InMemoryMyWhooshSessionStore(), intervalsConfig: IntervalsConfig(clientID: "cid-77"))
        struct Cancelled: Error {}
        await model.connectIntervals { _ in throw Cancelled() }
        #expect(!model.isIntervalsConnected && model.banner?.isError == true)
        await model.connectIntervals { url in
            URL(string: "indoorcoach://localhost/intervals?code=CODE1&state=FALSCH")!
        }
        #expect(!model.isIntervalsConnected && model.banner?.message == IntervalsError.stateMismatch.localizedDescription)
    }

    @Test func connectingSendsUpcomingPlannedWorkouts() async throws {
        let w = makeWorkout()
        await model.connectIntervals(apiKey: "key-123456")
        #expect(w.intervalsSentAt != nil)
        #expect(stub.requests("/events/bulk").count == 1)
    }

    @Test func connectingDoesNotSendWhenAutoSendIsOff() async throws {
        let w = makeWorkout()
        model.profile.autoSendToIntervals = false
        await model.connectIntervals(apiKey: "key-123456")
        #expect(w.intervalsSentAt == nil && stub.requests("/events/bulk").isEmpty)
    }

    // MARK: Senden

    @Test func sendingUpsertsWithTheWorkoutIDAndTheZWO() async throws {
        await connect()
        let w = makeWorkout()
        await model.sendToIntervals([w])
        #expect(w.intervalsSentAt != nil)
        let req = try #require(stub.requests("/events/bulk").first)
        let list = try jsonBody(req, as: [[String: Any]].self)
        let e = try #require(list.first)
        #expect(e["external_id"] as? String == w.id.uuidString)
        #expect(e["file_contents"] as? String == ZWOExporter.xml(for: w.definition))
        #expect(e["filename"] as? String == ZWOExporter.fileName(for: w.definition, date: w.date))
        #expect(e["name"] as? String == w.title && e["moving_time"] as? Int == w.definition.totalDuration)
        let expectedStart = IntervalsClient.localTimeFormatter().string(from: model.startDate(for: w))
        #expect(e["start_date_local"] as? String == expectedStart)
        #expect(model.banner?.message == "Einheit an intervals.icu gesendet." && model.banner?.isError == false)
    }

    @Test func severalWorkoutsAreOneRequest() async {
        await connect()
        let a = makeWorkout(daysAhead: 1), b = makeWorkout(daysAhead: 2)
        await model.sendToIntervals([a, b])
        #expect(stub.requests("/events/bulk").count == 1)
        #expect(a.intervalsSentAt != nil && b.intervalsSentAt != nil)
        #expect(model.banner?.message == "2 Einheiten an intervals.icu gesendet.")
        #expect(!model.isSendingToIntervals)
    }

    @Test func aFailedSendSetsTheErrorAndKeepsTheWorkoutUnsent() async {
        await connect()
        let w = makeWorkout()
        stub.status = 500
        await model.sendToIntervals([w])
        #expect(w.intervalsSentAt == nil)
        #expect(model.syncErrors[.intervalsICU] != nil && model.banner?.isError == true)
        stub.status = nil
        await model.sendToIntervals([w])
        #expect(w.intervalsSentAt != nil && model.syncErrors[.intervalsICU] == nil)
    }

    @Test func notConnectedSendsNothing() async {
        let w = makeWorkout()
        await model.sendToIntervals([w])
        #expect(w.intervalsSentAt == nil && stub.all.isEmpty)
    }

    // MARK: Automatisch senden

    func accept() async {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        model.proposal = PlanProposal(weekFocus: "x", notes: "", workouts: [
            PlannedWorkoutProposal(date: tomorrow, definition: planned, rationale: "r")], rejected: [])
        await model.acceptProposal(addToCalendar: false)
    }

    @Test func acceptingAProposalSendsToIntervalsWhenConnectedAndEnabled() async throws {
        await connect()
        await accept()
        let stored = try container.mainContext.fetch(FetchDescriptor<StoredWorkout>())
        let w = try #require(stored.first { $0.title == planned.title })
        #expect(w.intervalsSentAt != nil)
        #expect(stub.requests("/events/bulk").count == 1)
    }

    @Test func acceptingDoesNotSendWhenAutoSendIsOffOrNotConnected() async throws {
        await accept()                                                   // not connected
        #expect(stub.all.isEmpty)
        model.profile.autoSendToIntervals = false
        await connect()
        await accept()
        #expect(stub.requests("/events/bulk").isEmpty)
        let sent = try container.mainContext.fetch(FetchDescriptor<StoredWorkout>()).filter { $0.intervalsSentAt != nil }
        #expect(sent.isEmpty)
    }

    @Test func aProfileWithoutTheNewKeyDefaultsToAutoSend() throws {
        let old = #"{"name":"X","ftp":250,"autoSendToMyWhoosh":false}"#
        let profile = try JSONDecoder().decode(AthleteProfile.self, from: Data(old.utf8))
        #expect(profile.autoSendToIntervals && !profile.autoSendToMyWhoosh)
        var changed = AthleteProfile()
        changed.autoSendToIntervals = false
        let back = try JSONDecoder().decode(AthleteProfile.self, from: JSONEncoder().encode(changed))
        #expect(!back.autoSendToIntervals)
    }

    @Test func adjustingASentWorkoutResendsIt() async throws {
        await connect()
        let w = makeWorkout()
        await model.sendToIntervals([w])
        let before = stub.requests("/events/bulk").count
        await model.adjust(w, minutes: 45, easierBy: nil)
        #expect(stub.requests("/events/bulk").count == before + 1)
        let last = try #require(stub.requests("/events/bulk").last)
        let events = try jsonBody(last, as: [[String: Any]].self)
        let e = try #require(events.first)
        #expect(e["moving_time"] as? Int == w.definition.totalDuration)
        #expect(abs(w.definition.totalDuration - 45 * 60) <= 60)
        #expect(model.banner?.isError == false)
    }

    @Test func adjustingAnUnsentWorkoutSendsNothing() async {
        await connect()
        let w = makeWorkout()
        await model.adjust(w, minutes: 45, easierBy: nil)
        #expect(stub.requests("/events/bulk").isEmpty)
    }

    @Test func aFailedResendKeepsTheLocalChangeAndShowsTheError() async {
        await connect()
        let w = makeWorkout()
        await model.sendToIntervals([w])
        stub.status = 500
        await model.adjust(w, minutes: 45, easierBy: nil)
        #expect(abs(w.definition.totalDuration - 45 * 60) <= 60)
        #expect(model.banner?.isError == true)
    }

    // MARK: Löschen

    @Test func deletingASentWorkoutRemovesTheEvent() async throws {
        await connect()
        let w = makeWorkout()
        let id = w.id.uuidString
        await model.sendToIntervals([w])
        await model.delete(w)
        let req = try #require(stub.requests("/events/bulk-delete").first)
        let list = try jsonBody(req, as: [[String: String]].self)
        #expect(list == [["external_id": id]])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.title == "Sweet Spot 2×20" })) == 0)
    }

    @Test func deletingAnUnsentWorkoutMakesNoRequest() async {
        await connect()
        let w = makeWorkout()
        await model.delete(w)
        #expect(stub.all.isEmpty)
    }

    @Test func aFailedRemoteDeleteNeverBlocksTheLocalOne() async throws {
        await connect()
        let w = makeWorkout()
        await model.sendToIntervals([w])
        stub.status = 500
        await model.delete(w)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.title == "Sweet Spot 2×20" })) == 0)
    }

    // MARK: Fahrten importieren

    @Test func newRidesAreStoredFromTheirFITFile() async throws {
        await connect()
        let start = Date.now.addingTimeInterval(-86_400 * 2)
        stub.activitiesJSON = "[" + activityJSON(id: "i1", start: start) + "]"
        stub.setFile("i1", recordsFIT(start: start))
        await model.importIntervalsRides(full: true)
        let stored = try rides()
        #expect(stored.count == 1)
        let ride = try #require(stored.first)
        #expect(ride.stravaID == AppModel.importedRideID("intervals:i1") && ride.stravaID < 0)
        #expect(ride.secondsData != nil)
        #expect(model.lastIntervalsImport != nil && model.syncErrors[.intervalsICU] == nil)
        #expect(model.banner?.message == "intervals.icu: 1 Fahrt importiert.")
    }

    @Test func aRideWithoutFileFallsBackToTheListValues() async throws {
        await connect()
        let start = Date.now.addingTimeInterval(-86_400)
        stub.activitiesJSON = "[" + activityJSON(id: "i2", start: start, type: "Ride") + "]"     // no file → 404
        await model.importIntervalsRides(full: true)
        let all = try rides()
        let ride = try #require(all.first)
        #expect(ride.movingTime == 600 && ride.summary.averageWatts == 200 && ride.secondsData == nil)
        #expect(model.lastIntervalsImport != nil)
    }

    @Test func aRideAlreadyStoredFromStravaGetsEnrichedNotDuplicated() async throws {
        await connect()
        let start = Date.now.addingTimeInterval(-86_400 * 2)
        let strava = RideSummary(id: 4242, name: "Strava-Fahrt", sportType: "VirtualRide", startDate: start.addingTimeInterval(60),
                                 movingTime: 600, distance: 15_000, averageWatts: 200, trainer: true)
        container.mainContext.insert(StoredRide(strava))
        try container.mainContext.save()
        stub.activitiesJSON = "[" + activityJSON(id: "i3", start: start) + "]"
        stub.setFile("i3", recordsFIT(start: start))
        await model.importIntervalsRides(full: true)
        let stored = try rides()
        #expect(stored.count == 1)
        #expect(stored[0].stravaID == 4242 && stored[0].secondsData != nil)
        #expect(model.banner?.message == "intervals.icu: 1 Fahrt mit Sekundendaten ergänzt.")
    }

    @Test func stravaSourcedActivitiesAreSkipped() async throws {
        await connect()
        let start = Date.now.addingTimeInterval(-86_400)
        stub.activitiesJSON = "[" + activityJSON(id: "i4", start: start, source: "STRAVA") + "," + activityJSON(id: "i5", start: start.addingTimeInterval(-7_200), type: "Run") + "]"
        await model.importIntervalsRides(full: true)
        #expect(try rides().isEmpty)
        #expect(stub.requests("/file").isEmpty)
        #expect(model.banner?.message == "intervals.icu: keine neuen Fahrten.")
    }

    @Test func knownRidesAreNotDownloadedAgain() async throws {
        await connect()
        let start = Date.now.addingTimeInterval(-86_400 * 2)
        stub.activitiesJSON = "[" + activityJSON(id: "i6", start: start) + "]"
        stub.setFile("i6", recordsFIT(start: start))
        await model.importIntervalsRides(full: true)
        #expect(stub.requests("/file").count == 1)
        await model.importIntervalsRides()
        #expect(stub.requests("/file").count == 1)
        #expect(try rides().count == 1)
        // The incremental window is the last import minus 7 days.
        let last = try #require(stub.requests("/activities").last)
        let oldest = URLComponents(url: last.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "oldest" }?.value
        let expected = try #require(model.lastIntervalsImport).addingTimeInterval(-7 * 86_400)
        #expect(oldest == IntervalsClient.dayFormatter().string(from: expected))
    }

    @Test func aPermanentlyUnreadableRideIsRememberedAndNeverBlocksTheWindow() async throws {
        await connect()
        model.lastIntervalsImport = nil
        // No start, no duration and no file (404): permanently unusable.
        stub.activitiesJSON = #"[{"id":"i7","type":"Ride","source":"UPLOAD"}]"#
        await model.importIntervalsRides(full: true, announce: true)
        #expect(try rides().isEmpty)
        #expect(model.banner?.isError == true)
        #expect(model.lastIntervalsImport != nil)
        #expect(stub.requests("/file").count == 1)
        // Later runs skip it: no download, no error.
        model.syncErrors[.intervalsICU] = nil
        await model.importIntervalsRides(full: true)
        #expect(stub.requests("/file").count == 1)
        #expect(model.syncErrors[.intervalsICU] == nil)
        #expect(defaults.stringArray(forKey: AppModel.Keys.intervalsUnreadable) == ["i7"])
    }

    @Test func theUnreadableMemoryIsCapped() throws {
        let ids = (0..<600).map { "x\($0)" }
        model.rememberUnreadableIntervalsActivities(ids)
        let kept = model.unreadableIntervalsActivities
        #expect(kept.count == 500 && kept.contains("x599") && !kept.contains("x0"))
    }

    @Test func aServerErrorOnTheFileStopsTheRunInsteadOfStoringAFallback() async throws {
        await connect()
        model.lastIntervalsImport = nil
        let t = Date.now.addingTimeInterval(-86_400)
        stub.activitiesJSON = "[" + activityJSON(id: "ok1", start: t) + "," + activityJSON(id: "bad", start: t.addingTimeInterval(-7_200)) + "]"
        stub.setFile("ok1", recordsFIT(start: t))
        stub.setFileStatus("bad", 503)
        await model.importIntervalsRides(full: true)
        #expect(try rides().count == 1)                                   // what was read stays, no degraded copy of "bad"
        #expect(model.lastIntervalsImport == nil)
        #expect(model.syncErrors[.intervalsICU] == "intervals.icu ist gerade nicht erreichbar.")
        #expect(model.banner?.isError == true)
        // Recovered: the missing ride arrives with its file.
        stub.setFileStatus("bad", nil)
        stub.setFile("bad", recordsFIT(start: t.addingTimeInterval(-7_200)))
        await model.importIntervalsRides(full: true)
        #expect(try rides().count == 2 && model.lastIntervalsImport != nil && model.syncErrors[.intervalsICU] == nil)
    }

    @Test func aNetworkErrorOnTheFileStopsTheRunToo() async throws {
        let hook = HookTransport(stub.transport) { request in
            if request.url?.path.hasSuffix("/file") == true { throw URLError(.timedOut) }
        }
        let model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: hook,
                             myWhooshStore: InMemoryMyWhooshSessionStore(), intervalsConfig: IntervalsConfig(clientID: ""))
        SecretIntervalsCredentialStore(secrets: secrets).saveCredential(.apiKey("key-123456"))
        model.refreshCredentialState()
        stub.activitiesJSON = "[" + activityJSON(id: "n1", start: .now.addingTimeInterval(-3_600)) + "]"
        await model.importIntervalsRides(full: true)
        #expect(try rides().isEmpty && model.lastIntervalsImport == nil)
        #expect(model.syncErrors[.intervalsICU] == "intervals.icu ist gerade nicht erreichbar.")
    }

    @Test func aMissingFileFallsBackToTheListValuesForGood() async throws {
        await connect()
        stub.activitiesJSON = "[" + activityJSON(id: "m1", start: .now.addingTimeInterval(-3_600)) + "]"
        stub.setFileStatus("m1", 404)
        await model.importIntervalsRides(full: true)
        #expect(try rides().count == 1)
    }

    @Test func forbiddenHasItsOwnShortText() {
        #expect(AppModel.intervalsErrorText(IntervalsError.forbidden) == "intervals.icu verweigert den Zugriff.")
        #expect(AppModel.intervalsErrorText(URLError(.notConnectedToInternet)) == "intervals.icu ist gerade nicht erreichbar.")
    }

    // MARK: Nebenläufigkeit

    @Test func aSendWhileAnotherRunsIsQueuedNotDropped() async throws {
        let gate = HookTransport(stub.transport)
        let model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: gate,
                             myWhooshStore: InMemoryMyWhooshSessionStore(), intervalsConfig: IntervalsConfig(clientID: ""))
        SecretIntervalsCredentialStore(secrets: secrets).saveCredential(.apiKey("key-123456"))
        model.refreshCredentialState()
        let a = makeWorkout(daysAhead: 1), b = makeWorkout(daysAhead: 2)
        gate.holdPath("/events/bulk")
        let first = Task { @MainActor in await model.sendToIntervals([a]) }
        await gate.waitUntilReached()
        await model.sendToIntervals([b])                                 // arrives while the first send is in flight
        gate.release()
        await first.value
        #expect(a.intervalsSentAt != nil && b.intervalsSentAt != nil)
        #expect(stub.requests("/events/bulk").count == 2)
        #expect(!model.isSendingToIntervals)
    }

    @Test func anImportFinishingAfterDisconnectWritesNothing() async throws {
        let gate = HookTransport(stub.transport)
        let model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: gate,
                             myWhooshStore: InMemoryMyWhooshSessionStore(), intervalsConfig: IntervalsConfig(clientID: ""))
        SecretIntervalsCredentialStore(secrets: secrets).saveCredential(.apiKey("key-123456"))
        model.refreshCredentialState()
        stub.activitiesJSON = "[" + activityJSON(id: "g1", start: .now.addingTimeInterval(-3_600)) + "]"
        stub.setFile("g1", recordsFIT(start: .now.addingTimeInterval(-3_600)))
        gate.holdPath("/activities")
        let importing = Task { @MainActor in await model.importIntervalsRides(full: true) }
        await gate.waitUntilReached()
        await model.disconnectIntervals()
        gate.release()
        await importing.value
        #expect(try rides().isEmpty && model.lastIntervalsImport == nil)
        #expect(model.syncErrors[.intervalsICU] == nil)
        #expect(model.banner?.message == "intervals.icu getrennt." && model.banner?.isError == false)
    }

    @Test func anImportFailingAfterDisconnectShowsNoError() async throws {
        let gate = HookTransport(stub.transport)
        let model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: gate,
                             myWhooshStore: InMemoryMyWhooshSessionStore(), intervalsConfig: IntervalsConfig(clientID: ""))
        SecretIntervalsCredentialStore(secrets: secrets).saveCredential(.apiKey("key-123456"))
        model.refreshCredentialState()
        stub.status = 401
        gate.holdPath("/activities")
        let importing = Task { @MainActor in await model.importIntervalsRides(full: true) }
        await gate.waitUntilReached()
        await model.disconnectIntervals()
        gate.release()
        await importing.value
        #expect(model.syncErrors[.intervalsICU] == nil && model.banner?.isError == false)
    }

    @Test func connectingWaitsForARunningSyncAndThenImports() async throws {
        model.isSyncing = true
        stub.activitiesJSON = "[" + activityJSON(id: "w1", start: .now.addingTimeInterval(-3_600)) + "]"
        stub.setFile("w1", recordsFIT(start: .now.addingTimeInterval(-3_600)))
        let release = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            model.isSyncing = false
        }
        await model.connectIntervals(apiKey: "key-123456")
        await release.value
        #expect(try rides().count == 1 && model.lastIntervalsImport != nil)
    }

    // MARK: Schlüsselbund

    @Test func aKeychainFailureIsReportedNotShownAsConnected() async {
        final class Failing: SecretStore, @unchecked Sendable {
            func secret(_ key: Keychain.Key) -> String? { nil }
            func setSecret(_ value: String?, for key: Keychain.Key) {}
            var tokenStore: StravaTokenStore { InMemorySecretStore() }
        }
        let model = AppModel(context: container.mainContext, secrets: Failing(), defaults: defaults, transport: stub.transport,
                             myWhooshStore: InMemoryMyWhooshSessionStore(), intervalsConfig: IntervalsConfig(clientID: ""))
        let ok = await model.connectIntervals(apiKey: "key-123456")
        #expect(!ok && !model.isIntervalsConnected)
        #expect(model.banner?.message == "Zugang konnte nicht im Schlüsselbund gespeichert werden." && model.banner?.isError == true)
    }
    @Test func atMostEightyRidesPerRun() async throws {
        await connect()
        let list = (0..<95).map { activityJSON(id: "b\($0)", start: .now.addingTimeInterval(-Double($0 + 1) * 86_400 / 2)) }
        stub.activitiesJSON = "[" + list.joined(separator: ",") + "]"
        model.lastIntervalsImport = nil
        await model.importIntervalsRides(full: true)
        #expect(try rides().count == 80)
        #expect(model.lastIntervalsImport == nil)                         // 15 are still waiting: the window stays
        await model.importIntervalsRides(full: true)
        #expect(try rides().count == 95 && model.lastIntervalsImport != nil)
    }

    @Test func anExpiredTokenSetsTheErrorThenSuccessClearsIt() async {
        await connect()
        stub.status = 401
        await model.importIntervalsRides(announce: true)
        #expect(model.syncErrors[.intervalsICU] == "Zugang abgelaufen – bitte neu verbinden.")
        #expect(model.banner?.isError == true)
        #expect(model.connection(.intervalsICU).status == .error("Zugang abgelaufen – bitte neu verbinden."))
        #expect(model.connectionsNeedingAttention == 1)
        stub.status = nil
        await model.importIntervalsRides(announce: true)
        #expect(model.syncErrors[.intervalsICU] == nil && model.connectionsNeedingAttention == 0)
    }

    @Test func rateLimitAndOutageHaveShortTexts() {
        #expect(AppModel.intervalsErrorText(IntervalsError.rateLimited(retryAfter: 60)) == "intervals.icu-Limit erreicht – später erneut versuchen.")
        #expect(AppModel.intervalsErrorText(IntervalsError.unavailable(503)) == "intervals.icu ist gerade nicht erreichbar.")
        #expect(AppModel.intervalsErrorText(IntervalsError.http(400, "x")) == "Synchronisierung fehlgeschlagen.")
    }

    @Test func importWithoutConnectionDoesNothing() async {
        await model.importIntervalsRides(full: true)
        #expect(stub.all.isEmpty)
    }

    @Test func importWaitsWhileAnotherSyncRuns() async {
        await connect()
        model.isSyncing = true
        await model.importIntervalsRides(full: true)
        #expect(stub.all.isEmpty)
    }

    @Test func syncRidesIncludesIntervals() async throws {
        await connect()
        let start = Date.now.addingTimeInterval(-86_400)
        stub.activitiesJSON = "[" + activityJSON(id: "i8", start: start) + "]"
        stub.setFile("i8", recordsFIT(start: start))
        await model.syncRides()
        #expect(try rides().count == 1)
    }

    @Test func syncRidesWithoutAnySourceMentionsIntervals() async {
        await model.syncRides(userInitiated: true)
        #expect(model.banner?.message.contains("intervals.icu") == true)
        #expect(model.banner?.message.contains("Strava") == true && model.banner?.message.contains("MyWhoosh") == true)
    }

    // MARK: Trennen

    @Test func disconnectingClearsTheStateButKeepsImportedRides() async throws {
        await connect()
        let start = Date.now.addingTimeInterval(-86_400)
        stub.activitiesJSON = "[" + activityJSON(id: "i9", start: start) + "]"
        stub.setFile("i9", recordsFIT(start: start))
        await model.importIntervalsRides(full: true)
        let w = makeWorkout()
        await model.sendToIntervals([w])
        model.syncErrors[.intervalsICU] = "x"

        await model.disconnectIntervals()

        #expect(!model.isIntervalsConnected && model.intervalsAthleteName == nil && !model.intervalsUsesAPIKey)
        #expect(secrets.secret(.intervalsCredential) == nil)
        #expect(model.syncErrors[.intervalsICU] == nil && model.lastIntervalsImport == nil)
        #expect(defaults.object(forKey: AppModel.Keys.intervalsLastImport) == nil)
        #expect(w.intervalsSentAt == nil)
        #expect(try rides().count == 1)
        #expect(model.banner?.message == "intervals.icu getrennt." && model.banner?.isError == false)
        #expect(model.connection(.intervalsICU).status == .notConnected)
    }

    @Test func disconnectingOAuthRevokesTheGrantAtIntervals() async {
        let model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: stub.transport,
                             myWhooshStore: InMemoryMyWhooshSessionStore(), intervalsConfig: IntervalsConfig(clientID: "cid-77"))
        await model.connectIntervals { url in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "indoorcoach://localhost/intervals?code=C&state=\(state)")!
        }
        await model.disconnectIntervals()
        #expect(stub.requests("/disconnect-app").count == 1 && stub.requests("/disconnect-app")[0].httpMethod == "DELETE")
        #expect(!model.isIntervalsConnected)
    }

    @Test func everyRequestStaysOnIntervals() async throws {
        let w = makeWorkout()
        stub.activitiesJSON = "[" + activityJSON(id: "h1", start: .now.addingTimeInterval(-86_400)) + "]"
        await model.connectIntervals(apiKey: "key-123456")
        await model.sendToIntervals([w])
        await model.delete(w)
        await model.disconnectIntervals()
        #expect(!stub.all.isEmpty)
        #expect(stub.all.allSatisfy { $0.url?.host == "intervals.icu" })
    }

    // MARK: Debug-Seed

    @Test func theUITestSeedConnectsWithoutNetwork() async {
        model.seedIntervalsConnected()
        #expect(model.isIntervalsConnected && model.intervalsUsesAPIKey && model.intervalsAthleteName == "UI Test")
        #expect(model.connection(.intervalsICU).status == .connected(detail: "UI Test", lastSync: nil))
        await model.syncRides()
        let w = makeWorkout()
        await model.sendToIntervals([w])
        #expect(stub.all.isEmpty)
    }
}
