import Foundation
import Testing
@testable import IndoorCoachKit

/// Zählt Wartezeiten (Backoff) statt zu schlafen.
private final class SleepCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.withLock { n } }
    func tick() { lock.withLock { n += 1 } }
}

private let secretToken = "tok-SECRET-123456"
private let secretKey = "key-SECRET-987654"

private func client(_ credential: IntervalsCredential?, _ transport: HTTPTransport, sleeper: SleepCounter = SleepCounter(),
                    clientID: String = "cid-1") -> (IntervalsClient, InMemoryIntervalsCredentialStore) {
    let store = InMemoryIntervalsCredentialStore(credential)
    let client = IntervalsClient(config: IntervalsConfig(clientID: clientID), store: store, transport: transport,
                                 sleep: { _ in sleeper.tick() })
    return (client, store)
}

private func jsonBody<T>(_ request: URLRequest, as type: T.Type) throws -> T {
    let body = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: body) as? T)
}

private let oauth = IntervalsCredential.oauth(accessToken: secretToken, athleteID: "i42", athleteName: "Lena")

private func localDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite("intervals.icu · Konfiguration und PKCE")
struct IntervalsConfigTests {
    @Test func authorizeURLHasAllItems() throws {
        let config = IntervalsConfig(clientID: "cid-1")
        let url = config.authorizeURL(state: "st-1", codeChallenge: "chal-1")
        let c = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(c.scheme == "https" && c.host == "intervals.icu" && c.path == "/oauth/authorize")
        func item(_ name: String) -> String? { c.queryItems?.first { $0.name == name }?.value }
        #expect(item("client_id") == "cid-1")
        #expect(item("redirect_uri") == "indoorcoach://localhost/intervals")
        #expect(item("scope") == "ACTIVITY:READ,CALENDAR:WRITE")
        #expect(item("state") == "st-1")
        #expect(item("code_challenge") == "chal-1")
        #expect(item("code_challenge_method") == "S256")
        #expect(item("response_type") == "code")
        #expect(item("client_secret") == nil)
        #expect(IntervalsConfig.callbackScheme == "indoorcoach")
    }

    @Test func oauthNeedsAClientID() {
        #expect(!IntervalsConfig(clientID: "").isOAuthAvailable)
        #expect(!IntervalsConfig(clientID: "  ").isOAuthAvailable)
        #expect(IntervalsConfig(clientID: "abc").isOAuthAvailable)
    }

    @Test func pkceMatchesRFC7636AppendixB() {
        #expect(IntervalsPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierIsLongRandomAndUnreserved() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let a = IntervalsPKCE.makeVerifier(), b = IntervalsPKCE.makeVerifier()
        #expect((43...128).contains(a.count) && (43...128).contains(b.count))
        #expect(a != b)
        #expect(a.unicodeScalars.allSatisfy { allowed.contains($0) })
        #expect(!IntervalsPKCE.challenge(for: a).contains("=") && !IntervalsPKCE.challenge(for: a).contains("+"))
    }

    @Test func credentialHeaders() {
        #expect(IntervalsCredential.oauth(accessToken: "t", athleteID: nil, athleteName: nil).authorizationHeader == "Bearer t")
        let expected = "Basic " + Data("API_KEY:abc".utf8).base64EncodedString()
        #expect(IntervalsCredential.apiKey("abc").authorizationHeader == expected)
    }

    @Test func credentialRoundTripsThroughTheSecretStore() {
        let secrets = InMemorySecretStore()
        let store = SecretIntervalsCredentialStore(secrets: secrets)
        #expect(store.loadCredential() == nil)
        store.saveCredential(oauth)
        #expect(store.loadCredential() == oauth)
        store.saveCredential(.apiKey("k"))
        #expect(store.loadCredential() == .apiKey("k"))
        store.saveCredential(nil)
        #expect(store.loadCredential() == nil && secrets.secret(.intervalsCredential) == nil)
    }

    @Test func errorMessagesAreGerman() {
        #expect(IntervalsError.notConfigured.localizedDescription == "intervals.icu-Anmeldung ist in dieser Version noch nicht freigeschaltet – verbinde dich vorerst mit deinem API-Key.")
        #expect(IntervalsError.notConnected.localizedDescription == "intervals.icu-Zugang abgelaufen – bitte neu verbinden.")
        for e: IntervalsError in [.invalidAPIKey, .authorizationDenied, .stateMismatch, .missingScope, .rateLimited(retryAfter: 90),
                                  .unavailable(503), .http(400, "x")] {
            #expect(e.localizedDescription.contains("intervals.icu"), "\(e)")
        }
    }
}

@Suite("intervals.icu · Anmeldung")
struct IntervalsAuthTests {
    static let tokenJSON = #"{"access_token":"\#(secretToken)","token_type":"Bearer","scope":"ACTIVITY:READ,CALENDAR:WRITE","athlete":{"id":"i42","name":"Lena Test","extra":1}}"#
    static func callback(_ query: String) -> URL { URL(string: "indoorcoach://localhost/intervals?\(query)")! }

    @Test func tokenExchangeSendsVerifierButNoSecret() async throws {
        let transport = MockTransport([(200, Self.tokenJSON, [:])])
        let (c, store) = client(nil, transport)
        try await c.completeAuthorization(callbackURL: Self.callback("code=abc%20d&state=S1"), expectedState: "S1", codeVerifier: "ver-123")
        let req = try #require(transport.requests.first)
        #expect(req.url?.absoluteString == "https://intervals.icu/api/oauth/token" && req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        let body = String(decoding: try #require(req.httpBody), as: UTF8.self)
        #expect(body == "client_id=cid-1&code=abc%20d&code_verifier=ver-123&grant_type=authorization_code&redirect_uri=indoorcoach://localhost/intervals")
        #expect(!body.contains("client_secret"))
        #expect(store.credential == .oauth(accessToken: secretToken, athleteID: "i42", athleteName: "Lena Test"))
    }

    @Test func stateMismatchStopsBeforeAnyRequest() async {
        let transport = MockTransport([])
        let (c, store) = client(nil, transport)
        await #expect(throws: IntervalsError.stateMismatch) {
            try await c.completeAuthorization(callbackURL: Self.callback("code=abc&state=OTHER"), expectedState: "S1", codeVerifier: "v")
        }
        #expect(transport.requests.isEmpty && store.credential == nil)
    }

    @Test func errorParameterMeansDenied() async {
        let transport = MockTransport([])
        let (c, _) = client(nil, transport)
        await #expect(throws: IntervalsError.authorizationDenied) {
            try await c.completeAuthorization(callbackURL: Self.callback("error=access_denied&state=S1"), expectedState: "S1", codeVerifier: "v")
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func missingCodeMeansDenied() async {
        let (c, _) = client(nil, MockTransport([]))
        await #expect(throws: IntervalsError.authorizationDenied) {
            try await c.completeAuthorization(callbackURL: Self.callback("state=S1"), expectedState: "S1", codeVerifier: "v")
        }
    }

    @Test(arguments: ["ACTIVITY:READ", "CALENDAR:WRITE", "ACTIVITY:READ,SETTINGS:READ"])
    func missingScopeIsRefusedAndNothingStored(scope: String) async {
        let json = #"{"access_token":"\#(secretToken)","scope":"\#(scope)"}"#
        let (c, store) = client(nil, MockTransport([(200, json, [:])]))
        await #expect(throws: IntervalsError.missingScope) {
            try await c.completeAuthorization(callbackURL: Self.callback("code=abc&state=S"), expectedState: "S", codeVerifier: "v")
        }
        #expect(store.credential == nil)
    }

    @Test func leniencyWithoutScopeOrAthlete() async throws {
        let (c, store) = client(nil, MockTransport([(200, #"{"access_token":"t-123456"}"#, [:])]))
        try await c.completeAuthorization(callbackURL: Self.callback("code=abc&state=S"), expectedState: "S", codeVerifier: "v")
        #expect(store.credential == .oauth(accessToken: "t-123456", athleteID: nil, athleteName: nil))
    }

    @Test func numericAthleteIDIsAccepted() async throws {
        let json = #"{"access_token":"t-123456","athlete":{"id":42,"name":"N"}}"#
        let (c, store) = client(nil, MockTransport([(200, json, [:])]))
        try await c.completeAuthorization(callbackURL: Self.callback("code=abc&state=S"), expectedState: "S", codeVerifier: "v")
        #expect(store.credential == .oauth(accessToken: "t-123456", athleteID: "42", athleteName: "N"))
    }

    @Test(arguments: [400, 401, 403])
    func rejectedCodeIsAnAuthorizationFailureNotAnExpiredToken(status: Int) async {
        let (c, store) = client(nil, MockTransport([(status, #"{"error":"invalid_grant"}"#, [:])]))
        await #expect(throws: IntervalsError.authorizationFailed) {
            try await c.completeAuthorization(callbackURL: Self.callback("code=abc&state=S"), expectedState: "S", codeVerifier: "v")
        }
        #expect(store.credential == nil)
    }

    @Test func apiKeyIsValidatedAgainstTheAthleteEndpoint() async throws {
        let transport = MockTransport([(200, #"{"id":"i77","name":"Jan","email":"x@y.de","sportSettings":[1,2]}"#, [:])])
        let (c, store) = client(nil, transport)
        let name = try await c.connect(apiKey: "  \(secretKey)  ")
        #expect(name == "Jan")
        let req = try #require(transport.requests.first)
        #expect(req.url?.absoluteString == "https://intervals.icu/api/v1/athlete/0" && req.httpMethod == "GET")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("API_KEY:\(secretKey)".utf8).base64EncodedString())
        #expect(store.credential == .apiKey(secretKey))
    }

    @Test func nestedAthleteAnswerIsReadToo() async throws {
        let (c, _) = client(nil, MockTransport([(200, #"{"athlete":{"id":7,"name":"Nest"}}"#, [:])]))
        #expect(try await c.connect(apiKey: "abcdef") == "Nest")
    }

    @Test func unauthorizedAPIKeyStoresNothing() async {
        let (c, store) = client(nil, MockTransport([(401, "{}", [:])]))
        await #expect(throws: IntervalsError.invalidAPIKey) { try await c.connect(apiKey: "wrong-key") }
        #expect(store.credential == nil)
    }

    @Test func emptyAPIKeyIsInvalidWithoutRequest() async {
        let transport = MockTransport([])
        let (c, _) = client(nil, transport)
        await #expect(throws: IntervalsError.invalidAPIKey) { try await c.connect(apiKey: "   ") }
        #expect(transport.requests.isEmpty)
    }
}

@Suite("intervals.icu · Pläne senden")
struct IntervalsPlansTests {
    static func planned(_ id: String = "7B3C0F5E-0000-4000-8000-000000000001") -> IntervalsPlannedWorkout {
        IntervalsPlannedWorkout(externalID: id, name: "Sweet Spot 3×12", start: localDate(2026, 11, 24, 7, 30),
                                fileName: "2026-11-24_Sweet_Spot_3x12.zwo", zwo: "<workout_file><name>Sweet Spot</name></workout_file>",
                                movingTime: 5400)
    }

    @Test func upsertBodyAndURL() async throws {
        let transport = MockTransport([(200, "[]", [:])])
        let (c, _) = client(oauth, transport)
        try await c.upsertWorkouts([Self.planned()])
        let req = try #require(transport.requests.first)
        #expect(req.url?.absoluteString == "https://intervals.icu/api/v1/athlete/0/events/bulk?upsert=true&upsertOnUid=false&updatePlanApplied=false")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer \(secretToken)")
        let list = try jsonBody(req, as: [[String: Any]].self)
        #expect(list.count == 1)
        let e = list[0]
        #expect(e["category"] as? String == "WORKOUT" && e["type"] as? String == "Ride")
        #expect(e["start_date_local"] as? String == "2026-11-24T07:30:00")
        #expect(e["name"] as? String == "Sweet Spot 3×12")
        #expect(e["filename"] as? String == "2026-11-24_Sweet_Spot_3x12.zwo")
        #expect(e["file_contents"] as? String == "<workout_file><name>Sweet Spot</name></workout_file>")
        #expect(e["external_id"] as? String == "7B3C0F5E-0000-4000-8000-000000000001")
        #expect(e["moving_time"] as? Int == 5400)
    }

    @Test func severalWorkoutsGoInOneRequest() async throws {
        let transport = MockTransport([(200, "[]", [:])])
        let (c, _) = client(.apiKey(secretKey), transport)
        try await c.upsertWorkouts([Self.planned("A"), Self.planned("B")])
        #expect(transport.requests.count == 1)
        let list = try jsonBody(transport.requests[0], as: [[String: Any]].self)
        #expect(list.map { $0["external_id"] as? String } == ["A", "B"])
    }

    @Test func emptyUpsertMakesNoRequest() async throws {
        let transport = MockTransport([])
        let (c, _) = client(oauth, transport)
        try await c.upsertWorkouts([])
        #expect(transport.requests.isEmpty)
    }

    @Test func upsertIsRetriedOnceOnServerErrorBecauseItIsIdempotent() async throws {
        let sleeper = SleepCounter()
        let transport = MockTransport([(503, "", [:]), (200, "[]", [:])])
        let (c, _) = client(oauth, transport, sleeper: sleeper)
        try await c.upsertWorkouts([Self.planned()])
        #expect(transport.requests.count == 2 && sleeper.count == 1)
    }

    @Test func bulkDeleteBody() async throws {
        let transport = MockTransport([(200, #"{"eventsDeleted":2}"#, [:])])
        let (c, _) = client(oauth, transport)
        try await c.deleteWorkouts(externalIDs: ["A", "B"])
        let req = try #require(transport.requests.first)
        #expect(req.url?.absoluteString == "https://intervals.icu/api/v1/athlete/0/events/bulk-delete" && req.httpMethod == "PUT")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let list = try jsonBody(req, as: [[String: String]].self)
        #expect(list == [["external_id": "A"], ["external_id": "B"]])
    }

    @Test func emptyDeleteMakesNoRequest() async throws {
        let transport = MockTransport([])
        let (c, _) = client(oauth, transport)
        try await c.deleteWorkouts(externalIDs: [])
        #expect(transport.requests.isEmpty)
    }

    @Test func withoutCredentialNothingIsSent() async {
        let transport = MockTransport([])
        let (c, _) = client(nil, transport)
        await #expect(throws: IntervalsError.notConnected) { try await c.upsertWorkouts([Self.planned()]) }
        await #expect(throws: IntervalsError.notConnected) { _ = try await c.activities(oldest: .now, newest: .now) }
        #expect(transport.requests.isEmpty)
    }
}

@Suite("intervals.icu · Fahrten")
struct IntervalsActivitiesTests {
    static let list = #"""
    [
      {"id":"i100","name":"Sweet Spot","type":"VirtualRide","start_date":"2026-11-10T17:30:00Z","start_date_local":"2026-11-10T18:30:00",
       "moving_time":3600,"elapsed_time":3700,"distance":31000.5,"icu_average_watts":205,"icu_weighted_avg_watts":221,
       "icu_joules":738400,"average_heartrate":148,"max_heartrate":171,"trainer":true,"source":"ZWIFT","file_type":"fit","icu_ctl":55.5,"unknown":{"x":1}},
      {"id":"i101","name":"Strava-Fahrt","type":"Ride","start_date":"2026-11-11T09:00:00Z","moving_time":3000,"source":"STRAVA"},
      {"id":"i102","name":"Lauf","type":"Run","start_date":"2026-11-12T06:00:00Z","moving_time":1800,"source":"GARMIN_CONNECT"},
      {"id":"i103","type":"Ride","start_date":"2026-11-13T09:00:00.000Z","moving_time":7200,"trainer":false,"source":"UPLOAD"},
      {"name":"ohne id","type":"Ride","start_date":"2026-11-13T09:00:00Z"},
      {"id":"i105","type":"Ride","start_date":"kaputt","moving_time":"viel","distance":null,"icu_average_watts":"x"},
      "kein objekt"
    ]
    """#

    @Test func requestsTheWindowAndMapsRides() async throws {
        let transport = MockTransport([(200, Self.list, [:])])
        let (c, _) = client(oauth, transport)
        let list = try await c.activities(oldest: localDate(2026, 5, 1), newest: localDate(2026, 11, 21, 15))
        let req = try #require(transport.requests.first)
        #expect(req.url?.absoluteString == "https://intervals.icu/api/v1/athlete/0/activities?oldest=2026-05-01&newest=2026-11-21")
        #expect(req.httpMethod == "GET" && req.value(forHTTPHeaderField: "Authorization") == "Bearer \(secretToken)")
        // STRAVA (no data from the API), non-rides and entries without id are skipped; lenient fields survive.
        #expect(list.map(\.id) == ["i100", "i103", "i105"])
        let first = list[0]
        #expect(first.name == "Sweet Spot" && first.source == "ZWIFT" && first.fileType == "fit")
        let ride = try #require(first.rideSummary(id: -5))
        #expect(ride.id == -5 && ride.name == "Sweet Spot" && ride.sportType == "VirtualRide")
        #expect(ride.startDate == ISO8601DateFormatter().date(from: "2026-11-10T17:30:00Z"))
        #expect(ride.movingTime == 3600 && ride.distance == 31000.5)
        #expect(ride.averageWatts == 205 && ride.weightedAverageWatts == 221 && ride.kilojoules == 738.4)
        #expect(ride.averageHeartrate == 148 && ride.maxHeartrate == 171 && ride.trainer)
        let outdoor = try #require(list[1].rideSummary(id: -6))
        #expect(!outdoor.trainer && outdoor.movingTime == 7200 && outdoor.name == "intervals.icu-Fahrt")
        #expect(outdoor.startDate == ISO8601DateFormatter().date(from: "2026-11-13T09:00:00Z"))
        #expect(list[2].rideSummary(id: -7) == nil)                      // no usable date or duration
    }

    @Test func fallsBackToElapsedTimeAndLocalStart() throws {
        let json = #"{"id":"i1","type":"Ride","start_date_local":"2026-11-10T18:30:00","elapsed_time":1800}"#
        let a = try JSONDecoder().decode(IntervalsActivity.self, from: Data(json.utf8))
        let ride = try #require(a.rideSummary(id: -1))
        #expect(ride.movingTime == 1800)
        #expect(ride.startDate == localDate(2026, 11, 10, 18, 30))
    }

    @Test func emptyOrWrongShapedListIsEmpty() async throws {
        let (c, _) = client(oauth, MockTransport([(200, "[]", [:]), (200, #"{"oops":true}"#, [:])]))
        #expect(try await c.activities(oldest: .now, newest: .now).isEmpty)
        await #expect(throws: (any Error).self) { _ = try await c.activities(oldest: .now, newest: .now) }
    }
}

@Suite("intervals.icu · FIT und gzip")
struct IntervalsFITTests {
    static let named = [
        "H4sICKCZAWsAA3JpZGUudHh0AHVWy44UMQz8lfmEztPJJ3BDAgmJ2x7mtuyuYIDfJ+uqSru14jI9nXYcP6rK+fL2+rB8+/z0+9d9",
        "2u3L3/v9UTKevWC92e3b0+Mxij9y51da1enLZnQysDywXOrt++vLPc/b1/uPt9dUbp9eHveff56enwtPc4M+6W3AHkdORbIiW4FO",
        "rK643Nlyup2t/75vMOQRPiG+5AYpu6dx+FthxrOd5utMD6jirAqHo/m+Evxak4X7bzDEW8FpLaFy2Fw74l6lgc/uRpVBNLz2xpim",
        "b+qdGR3nyR0hoh8x9AO2NnCQIZiBnHPaZcMBAwcwGjv8tdGqMnELHYtVHZVnmMdyoF9cTMx0su0LM14j/1UZeKAKTRBWVHUdj84r",
        "lblTi+H4N8JUEMg7+Xf3Ke30/ClwD8I4cR0oofHsAabp/J9UFPRmBXnWAzWOXQJoRzTKgp33JeC3o5mJaRewp5JywUVk0Cy7vP5s",
        "Tbl4LPBIPk4sNhO6HZ/sVwbrBgvaEHm3ALPBMyqQPQ521C2YvO3gcWQoImnNXTnkwz5YEn8QkTEUuJ7orRFPgEwO0CevDWqyCgEv",
        "MExYrbHedBHoLOlIUTo8L1FbUCJUkwUsAm2UuyQwjyuZBrMS2DuyQ3HI+2RXtoZDZvhv7EcJKdRygepZfemCNBqylGwTEflEqoPP",
        "ghC+94t77G07U7SxbERBCQIhathvZGmiXjJ5epMuGyqT+DHLyEutpBDqghY+knUmProDYLgyEUlesV1DJ0X6gKdxKQn6s/c6IkNO",
        "nJMVIGdB1tsGsobrO1DnNZRFPd8Uu1akz54uHzFGSZomBlQ2gaGkQoWXiP1Amxzys/of0ZOgSorJ2GUDmUEQiYg5/TE8UJeaMNjL",
        "Yhe574IgzTR2K83XUKS2Uw1c2tnOelzkkUNUiL8oDXZhNuU9Z8+Qz8kMGx7bNfw9Vs5N6CDByCqQyUxOMlRYwdY37TFsqPHuARDl",
        "LBu8tPCOBKxVuhNvmVApGwYUV+eDCIYu6bamZcGSl7qBE2YRteJgIje88jtmQcKLEFDEywYxMhnqCCqVefRk+3IctkMDRUP73MbB",
        "Azi1ufUFwGFtOp8VTUrzg0QbyD7VC+Xv6MUZlVcSjVNK8SznbZRUptifCl23iOu6gn5WBa+rHlp2bPUUYLx3gX2tSy/8i+6KSpdI",
        "arpXRAZ7RjQ8NNEdIrplQChMMHI6x9lMqsRBW1j4eEVi9VQncrqV3Rr1GZ+pZH1PHdSCUGdR/wFc4c6AmQwAAA=="
    ].joined()
    static let plain = [
        "H4sIAAAAAAAAA3VWy44UMQz8lfmEztPJJ3BDAgmJ2x7mtuyuYIDfJ+uqSru14jI9nXYcP6rK+fL2+rB8+/z0+9d92u3L3/v9UTKe",
        "vWC92e3b0+Mxij9y51da1enLZnQysDywXOrt++vLPc/b1/uPt9dUbp9eHveff56enwtPc4M+6W3AHkdORbIiW4FOrK643Nlyup2t",
        "/75vMOQRPiG+5AYpu6dx+FthxrOd5utMD6jirAqHo/m+Evxak4X7bzDEW8FpLaFy2Fw74l6lgc/uRpVBNLz2xpimb+qdGR3nyR0h",
        "oh8x9AO2NnCQIZiBnHPaZcMBAwcwGjv8tdGqMnELHYtVHZVnmMdyoF9cTMx0su0LM14j/1UZeKAKTRBWVHUdj84rlblTi+H4N8JU",
        "EMg7+Xf3Ke30/ClwD8I4cR0oofHsAabp/J9UFPRmBXnWAzWOXQJoRzTKgp33JeC3o5mJaRewp5JywUVk0Cy7vP5sTbl4LPBIPk4s",
        "NhO6HZ/sVwbrBgvaEHm3ALPBMyqQPQ521C2YvO3gcWQoImnNXTnkwz5YEn8QkTEUuJ7orRFPgEwO0CevDWqyCgEvMExYrbHedBHo",
        "LOlIUTo8L1FbUCJUkwUsAm2UuyQwjyuZBrMS2DuyQ3HI+2RXtoZDZvhv7EcJKdRygepZfemCNBqylGwTEflEqoPPghC+94t77G07",
        "U7SxbERBCQIhathvZGmiXjJ5epMuGyqT+DHLyEutpBDqghY+knUmProDYLgyEUlesV1DJ0X6gKdxKQn6s/c6IkNOnJMVIGdB1tsG",
        "sobrO1DnNZRFPd8Uu1akz54uHzFGSZomBlQ2gaGkQoWXiP1Amxzys/of0ZOgSorJ2GUDmUEQiYg5/TE8UJeaMNjLYhe574IgzTR2",
        "K83XUKS2Uw1c2tnOelzkkUNUiL8oDXZhNuU9Z8+Qz8kMGx7bNfw9Vs5N6CDByCqQyUxOMlRYwdY37TFsqPHuARDlLBu8tPCOBKxV",
        "uhNvmVApGwYUV+eDCIYu6bamZcGSl7qBE2YRteJgIje88jtmQcKLEFDEywYxMhnqCCqVefRk+3IctkMDRUP73MbBAzi1ufUFwGFt",
        "Op8VTUrzg0QbyD7VC+Xv6MUZlVcSjVNK8SznbZRUptifCl23iOu6gn5WBa+rHlp2bPUUYLx3gX2tSy/8i+6KSpdIarpXRAZ7RjQ8",
        "NNEdIrplQChMMHI6x9lMqsRBW1j4eEVi9VQncrqV3Rr1GZ+pZH1PHdSCUGdR/wFc4c6AmQwAAA=="
    ].joined()

    @Test func gunzipHandlesTheFileNameHeader() throws {
        let data = try #require(Data(base64Encoded: Self.named))
        #expect(data[3] & 0x08 != 0)                                      // FNAME is set (gzip without -n)
        let out = try Gzip.decompressIfNeeded(data)
        let text = String(decoding: out, as: UTF8.self)
        #expect(out.count == 3225 && text.hasPrefix("Spot72 Pause97 Sweet32") && text.hasSuffix("Sweet72 Zone1"))
    }

    @Test func gunzipHandlesAMinimalHeader() throws {
        let data = try #require(Data(base64Encoded: Self.plain))
        #expect(data[3] == 0)
        let out = try Gzip.decompressIfNeeded(data)
        #expect(out.count == 3225 && String(decoding: out, as: UTF8.self).hasPrefix("Spot72 Pause97 Sweet32"))
    }

    @Test func plainDataPassesThroughUnchanged() throws {
        let fit = sessionFIT()
        #expect(try Gzip.decompressIfNeeded(fit) == fit)
        #expect(try Gzip.decompressIfNeeded(Data()) == Data())
        #expect(try Gzip.decompressIfNeeded(Data([0x1f])) == Data([0x1f]))
    }

    @Test func truncatedGzipIsAnError() throws {
        let data = try #require(Data(base64Encoded: Self.plain))
        #expect(throws: (any Error).self) { try Gzip.decompressIfNeeded(data.prefix(12)) }
        #expect(throws: (any Error).self) { try Gzip.decompressIfNeeded(Data([0x1f, 0x8b, 0x08, 0x04, 0, 0, 0, 0, 0, 0, 0xff, 0xff])) }
    }

    @Test func downloadReturnsTheUnzippedFile() async throws {
        let gz = try #require(Data(base64Encoded: Self.named))
        let transport = RoutingTransport { _ in (200, gz) }
        let (c, _) = client(oauth, transport)
        let data = try await c.downloadFIT(activityID: "i100")
        #expect(data.count == 3225)
        let req = try #require(transport.requests.first)
        #expect(req.url?.absoluteString == "https://intervals.icu/api/v1/activity/i100/file" && req.httpMethod == "GET")
    }

    @Test func downloadKeepsAnUncompressedFitAsIs() async throws {
        let fit = sessionFIT()
        let (c, _) = client(oauth, RoutingTransport { _ in (200, fit) })
        let data = try await c.downloadFIT(activityID: "i100")
        #expect(try FITParser.summary(from: data).movingTime == 3600)
    }

    @Test func activityIDIsEscapedInThePath() async throws {
        let transport = RoutingTransport { _ in (200, Data()) }
        let (c, _) = client(oauth, transport)
        _ = try await c.downloadFIT(activityID: "a/b ?c")
        #expect(transport.requests[0].url?.absoluteString == "https://intervals.icu/api/v1/activity/a%2Fb%20%3Fc/file")
    }
}

@Suite("intervals.icu · Fehler, Schwärzung, Host")
struct IntervalsErrorTests {
    @Test func unauthorizedMeansNotConnected() async {
        let (c, _) = client(oauth, MockTransport([(401, "{}", [:])]))
        await #expect(throws: IntervalsError.notConnected) { try await c.upsertWorkouts([IntervalsPlansTests.planned()]) }
    }

    @Test func forbiddenDoesNotClaimTheTokenExpired() async {
        let (c, _) = client(oauth, MockTransport([(403, "{}", [:])]))
        await #expect(throws: IntervalsError.forbidden) { try await c.upsertWorkouts([IntervalsPlansTests.planned()]) }
        #expect(!IntervalsError.forbidden.localizedDescription.contains("abgelaufen"))
        #expect(IntervalsError.forbidden.localizedDescription == "intervals.icu verweigert den Zugriff – prüfe die Berechtigungen.")
        #expect(IntervalsError.keychainFailed.localizedDescription == "Zugang konnte nicht im Schlüsselbund gespeichert werden.")
        #expect(!IntervalsError.authorizationFailed.localizedDescription.contains("abgelaufen"))
    }

    @Test func rateLimitCarriesRetryAfter() async {
        let (c, _) = client(oauth, MockTransport([(429, "", ["Retry-After": "120"])]))
        await #expect(throws: IntervalsError.rateLimited(retryAfter: 120)) { _ = try await c.activities(oldest: .now, newest: .now) }
    }

    @Test func rateLimitIsNeverRetried() async {
        let transport = MockTransport([(429, "", [:]), (200, "[]", [:])])
        let (c, _) = client(oauth, transport)
        await #expect(throws: IntervalsError.rateLimited(retryAfter: nil)) { _ = try await c.activities(oldest: .now, newest: .now) }
        #expect(transport.requests.count == 1)
    }

    @Test func serverErrorIsRetriedOnceThenUnavailable() async {
        let sleeper = SleepCounter()
        let transport = MockTransport([(502, "", [:]), (503, "", [:]), (200, "[]", [:])])
        let (c, _) = client(oauth, transport, sleeper: sleeper)
        await #expect(throws: IntervalsError.unavailable(503)) { _ = try await c.activities(oldest: .now, newest: .now) }
        #expect(transport.requests.count == 2 && sleeper.count == 1)
    }

    @Test func serverErrorThenSuccessRecovers() async throws {
        let (c, _) = client(oauth, MockTransport([(500, "", [:]), (200, "[]", [:])]))
        #expect(try await c.activities(oldest: .now, newest: .now).isEmpty)
    }

    @Test func tokenExchangeIsNotRetried() async {
        let transport = MockTransport([(500, "", [:]), (200, IntervalsAuthTests.tokenJSON, [:])])
        let (c, _) = client(nil, transport)
        await #expect(throws: IntervalsError.unavailable(500)) {
            try await c.completeAuthorization(callbackURL: IntervalsAuthTests.callback("code=a&state=S"), expectedState: "S", codeVerifier: "v")
        }
        #expect(transport.requests.count == 1)
    }

    @Test func otherErrorsAreRedactedAndShort() async {
        let message = "Ungültig: Bearer \(secretToken) und \(secretToken) " + String(repeating: "x", count: 400)
        let (c, _) = client(oauth, MockTransport([(400, #"{"error":"\#(message)"}"#, [:])]))
        do {
            try await c.deleteWorkouts(externalIDs: ["A"])
            Issue.record("expected an error")
        } catch let IntervalsError.http(code, text) {
            #expect(code == 400)
            #expect(!text.contains(secretToken) && text.count <= 200)
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func apiKeyIsRedactedAsWellAsItsBase64Form() async {
        let basic = Data("API_KEY:\(secretKey)".utf8).base64EncodedString()
        let (c, _) = client(.apiKey(secretKey), MockTransport([(400, "echo \(secretKey) \(basic)", [:])]))
        do {
            try await c.deleteWorkouts(externalIDs: ["A"])
            Issue.record("expected an error")
        } catch let IntervalsError.http(_, text) {
            #expect(!text.contains(secretKey) && !text.contains(basic))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func everyRequestStaysOnIntervalsAndTheSecretOnlyTravelsInTheHeader() async throws {
        for credential in [oauth, IntervalsCredential.apiKey(secretKey)] {
            let transport = RoutingTransport { request in
                request.url?.path.hasSuffix("/file") == true ? (200, sessionFIT()) : (200, Data("[]".utf8))
            }
            let (c, _) = client(credential, transport)
            try await c.upsertWorkouts([IntervalsPlansTests.planned()])
            try await c.deleteWorkouts(externalIDs: ["A"])
            _ = try await c.activities(oldest: localDate(2026, 1, 1), newest: localDate(2026, 2, 1))
            _ = try await c.downloadFIT(activityID: "i1")
            await c.disconnect()
            let secrets: [String] = {
                switch credential {
                case .oauth(let t, _, _): [t]
                case .apiKey(let k): [k, Data("API_KEY:\(k)".utf8).base64EncodedString()]
                }
            }()
            #expect(transport.requests.count >= 4)
            for request in transport.requests {
                #expect(request.url?.scheme == "https" && request.url?.host == "intervals.icu")
                for secret in secrets {
                    #expect(request.url?.absoluteString.contains(secret) == false)
                    #expect(request.httpBody.map { String(decoding: $0, as: UTF8.self).contains(secret) } != true)
                }
                #expect(request.value(forHTTPHeaderField: "Authorization") == credential.authorizationHeader)
            }
        }
    }

    @Test func tokenExchangeAlsoOnlyTalksToIntervals() async throws {
        let transport = MockTransport([(200, IntervalsAuthTests.tokenJSON, [:])])
        let (c, _) = client(nil, transport)
        try await c.completeAuthorization(callbackURL: IntervalsAuthTests.callback("code=a&state=S"), expectedState: "S", codeVerifier: "v")
        #expect(transport.requests.allSatisfy { $0.url?.host == "intervals.icu" && $0.url?.scheme == "https" })
        let body = String(decoding: try #require(transport.requests[0].httpBody), as: UTF8.self)
        #expect(!body.contains(secretToken))
    }
}

@Suite("intervals.icu · Trennen")
struct IntervalsDisconnectTests {
    @Test func oauthCallsDisconnectAppAndClears() async throws {
        let transport = MockTransport([(200, "{}", [:])])
        let (c, store) = client(oauth, transport)
        await c.disconnect()
        let req = try #require(transport.requests.first)
        #expect(req.url?.absoluteString == "https://intervals.icu/api/v1/disconnect-app" && req.httpMethod == "DELETE")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer \(secretToken)")
        #expect(store.credential == nil)
    }

    @Test func failureIsIgnoredAndStillClears() async {
        let (c, store) = client(oauth, MockTransport([(500, "", [:])]))
        await c.disconnect()
        #expect(store.credential == nil)
    }

    @Test func apiKeyMakesNoRequestButClears() async {
        let transport = MockTransport([])
        let (c, store) = client(.apiKey(secretKey), transport)
        await c.disconnect()
        #expect(transport.requests.isEmpty && store.credential == nil)
    }

    @Test func neverRetriesAServerError() async {
        let transport = MockTransport([(503, "", [:]), (200, "", [:])])
        let (c, _) = client(oauth, transport)
        await c.disconnect()
        #expect(transport.requests.count == 1)
    }
}


// MARK: - Sicherheits-Nachbesserung

/// Ein SecretStore, der nichts speichert (Schlüsselbund-Schreibfehler).
private final class FailingSecretStore: SecretStore, @unchecked Sendable {
    func secret(_ key: Keychain.Key) -> String? { nil }
    func setSecret(_ value: String?, for key: Keychain.Key) {}
    var tokenStore: StravaTokenStore { InMemorySecretStore() }
}

/// Merkt sich den Zustand des Stores im Moment jeder Anfrage.
private final class StoreSpyTransport: HTTPTransport, @unchecked Sendable {
    let store: InMemoryIntervalsCredentialStore
    let result: Result<Int, any Error>
    private let lock = NSLock()
    private var _seen: [IntervalsCredential?] = []
    var seen: [IntervalsCredential?] { lock.withLock { _seen } }
    init(store: InMemoryIntervalsCredentialStore, result: Result<Int, any Error>) { self.store = store; self.result = result }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _seen.append(store.credential) }
        let code = try result.get()
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("intervals.icu · Härtung")
struct IntervalsHardeningTests {
    @Test func hostileNumbersNeverTrap() async throws {
        let json = #"""
        [{"id":1e300,"type":"Ride","start_date":"2026-11-10T17:30:00Z","moving_time":600},
         {"id":"i1","type":"Ride","start_date":"2026-11-10T17:30:00Z","moving_time":1e300,"elapsed_time":900,"distance":1e300,"icu_joules":-1e300},
         {"id":"i2","type":"Ride","start_date":"2026-11-10T17:30:00Z","moving_time":1e300},
         {"id":2.5e10,"type":"Ride","start_date":"2026-11-10T17:30:00Z","moving_time":600}]
        """#
        let (c, _) = client(oauth, MockTransport([(200, json, [:])]))
        let list = try await c.activities(oldest: .now, newest: .now)
        #expect(list.map(\.id) == ["i1", "i2", "25000000000"])          // the 1e300 id is dropped
        #expect(list[0].rideSummary(id: -1)?.movingTime == 900)         // out-of-range value counts as missing
        #expect(list[1].rideSummary(id: -2) == nil)
    }

    @Test func hostileAthleteIDInTheTokenAnswerIsIgnored() async throws {
        let json = #"{"access_token":"t-123456","athlete":{"id":1e300,"name":"N"}}"#
        let (c, store) = client(nil, MockTransport([(200, json, [:])]))
        try await c.completeAuthorization(callbackURL: IntervalsAuthTests.callback("code=a&state=S"), expectedState: "S", codeVerifier: "v")
        #expect(store.credential == .oauth(accessToken: "t-123456", athleteID: nil, athleteName: "N"))
    }

    @Test(arguments: [Result<Int, any Error>.success(500), .failure(URLError(.timedOut))])
    func disconnectClearsTheStoreBeforeTheRequest(result: Result<Int, any Error>) async {
        let store = InMemoryIntervalsCredentialStore(oauth)
        let spy = StoreSpyTransport(store: store, result: result)
        let c = IntervalsClient(config: IntervalsConfig(clientID: "x"), store: store, transport: spy, sleep: { _ in })
        await c.disconnect()
        #expect(spy.seen.count == 1 && spy.seen[0] == nil)               // already gone while the request is in flight
        #expect(store.credential == nil)
    }

    @Test func redirectsLeavingIntervalsAreRefused() throws {
        let original = URLRequest(url: URL(string: "https://intervals.icu/api/v1/activity/i1/file")!)
        func decide(_ url: String) -> URLRequest? {
            var next = URLRequest(url: URL(string: url)!)
            next.setValue("Bearer x", forHTTPHeaderField: "Authorization")
            return RestrictedRedirectTransport.redirectDecision(original: original, new: next)
        }
        #expect(decide("https://intervals.icu/other") != nil)
        #expect(decide("https://evil.example/steal") == nil)
        #expect(decide("https://intervals.icu.evil.example/x") == nil)
        #expect(decide("http://intervals.icu/x") == nil)
        #expect(decide("https://user@intervals.icu:8443/x") == nil)
        #expect(decide("https://forum.intervals.icu/x") == nil)
    }

    @Test func gunzipHonoursARunningOutputCap() throws {
        let data = try #require(Data(base64Encoded: IntervalsFITTests.named))
        #expect(try Gzip.decompressIfNeeded(data, maxOutput: 3225).count == 3225)
        #expect(throws: Gzip.Failure.tooLarge) { try Gzip.decompressIfNeeded(data, maxOutput: 3224) }
        #expect(throws: Gzip.Failure.tooLarge) { try Gzip.decompressIfNeeded(data, maxOutput: 100) }
    }

    @Test func oversizedDownloadsAreRefused() async throws {
        let (c, _) = client(oauth, RoutingTransport { _ in (200, Data(count: 1_000)) })
        await #expect(throws: IntervalsError.http(200, "Datei zu groß")) { _ = try await c.downloadFIT(activityID: "i1", maxCompressedBytes: 999) }
        #expect(try await c.downloadFIT(activityID: "i1", maxCompressedBytes: 1_000).count == 1_000)
    }

    @Test func aFailedKeychainWriteIsAnErrorNotASuccess() async {
        let store = SecretIntervalsCredentialStore(secrets: FailingSecretStore())
        #expect(store.saveCredential(.apiKey("k-123456")) == false)
        let transport = MockTransport([(200, #"{"id":"i1","name":"Jan"}"#, [:])])
        let c = IntervalsClient(config: IntervalsConfig(clientID: "x"), store: store, transport: transport, sleep: { _ in })
        await #expect(throws: IntervalsError.keychainFailed) { try await c.connect(apiKey: "k-123456") }

        let oauthTransport = MockTransport([(200, IntervalsAuthTests.tokenJSON, [:]), (200, "{}", [:])])
        let c2 = IntervalsClient(config: IntervalsConfig(clientID: "x"), store: store, transport: oauthTransport, sleep: { _ in })
        await #expect(throws: IntervalsError.keychainFailed) {
            try await c2.completeAuthorization(callbackURL: IntervalsAuthTests.callback("code=a&state=S"), expectedState: "S", codeVerifier: "v")
        }
        // The token that could not be stored is revoked again.
        #expect(oauthTransport.requests.last?.httpMethod == "DELETE" && oauthTransport.requests.last?.url?.path == "/api/v1/disconnect-app")
    }

    @Test func aTokenWithMissingScopeIsRevoked() async throws {
        let json = #"{"access_token":"\#(secretToken)","scope":"ACTIVITY:READ"}"#
        let transport = MockTransport([(200, json, [:]), (200, "{}", [:])])
        let (c, store) = client(nil, transport)
        await #expect(throws: IntervalsError.missingScope) {
            try await c.completeAuthorization(callbackURL: IntervalsAuthTests.callback("code=a&state=S"), expectedState: "S", codeVerifier: "v")
        }
        let revoke = try #require(transport.requests.last)
        #expect(revoke.httpMethod == "DELETE" && revoke.url?.absoluteString == "https://intervals.icu/api/v1/disconnect-app")
        #expect(revoke.value(forHTTPHeaderField: "Authorization") == "Bearer \(secretToken)")
        #expect(store.credential == nil)
    }

    @Test func theCodeAndVerifierAreRedactedFromServerMessages() async {
        let (c, _) = client(nil, MockTransport([(422, "bad code=CODE-SECRET-1 verifier VERIFIER-SECRET-1 CODE-SECRET-1", [:])]))
        do {
            try await c.completeAuthorization(callbackURL: IntervalsAuthTests.callback("code=CODE-SECRET-1&state=S"), expectedState: "S", codeVerifier: "VERIFIER-SECRET-1")
            Issue.record("expected an error")
        } catch let IntervalsError.http(_, text) {
            #expect(!text.contains("CODE-SECRET-1") && !text.contains("VERIFIER-SECRET-1"))
        } catch { Issue.record("wrong error \(error)") }
    }
}
