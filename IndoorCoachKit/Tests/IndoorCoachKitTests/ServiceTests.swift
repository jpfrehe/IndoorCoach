import Foundation
import Testing
@testable import IndoorCoachKit

/// Records requests and replays canned responses.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    var responses: [(Int, String, [String: String])]
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    init(_ responses: [(Int, String, [String: String])]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (code, body, headers) = lock.withLock {
            requests.append(request)
            return responses.isEmpty ? (500, "{}", [:]) : responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), response)
    }
}

final class MemoryTokenStore: StravaTokenStore, @unchecked Sendable {
    var tokens: StravaTokens?
    init(_ tokens: StravaTokens? = nil) { self.tokens = tokens }
    func loadTokens() -> StravaTokens? { tokens }
    func saveTokens(_ tokens: StravaTokens?) { self.tokens = tokens }
}

@Suite("Strava")
struct StravaTests {
    let config = StravaConfig(clientID: "123", clientSecret: "s3cr&t")

    @Test func authorizeURLContainsScopesAndState() {
        let url = config.authorizeURL(state: "xyz").absoluteString
        #expect(url.hasPrefix("https://www.strava.com/oauth/mobile/authorize?"))
        #expect(url.contains("scope=read,activity:read_all"))
        #expect(url.contains("state=xyz"))
        #expect(url.contains("redirect_uri=indoorcoach://localhost/strava"))
    }

    @Test func decodesAndFiltersRides() throws {
        let json = """
        [
          {"id":1,"name":"Sweet Spot","sport_type":"VirtualRide","start_date":"2026-11-10T17:30:00Z","moving_time":3600,
           "distance":31000.5,"average_watts":205.1,"weighted_average_watts":221,"kilojoules":738.4,"average_heartrate":148.2,
           "max_heartrate":171,"trainer":true,"device_watts":true},
          {"id":2,"name":"Lauf","sport_type":"Run","start_date":"2026-11-11T06:00:00Z","moving_time":1800,"distance":5000},
          {"id":3,"name":"Gravel","type":"Ride","start_date":"2026-11-12T09:00:00Z","moving_time":7200,"distance":60000,"trainer":false}
        ]
        """
        let list = try StravaActivityDTO.decodeList(Data(json.utf8))
        let rides = list.filter(\.isRide).map(\.summary)
        #expect(rides.map(\.id) == [1, 3])
        #expect(rides[0].isIndoor)
        #expect(rides[0].weightedAverageWatts == 221)
        #expect(!rides[1].isIndoor)
        #expect(rides[1].sportType == "Ride")
    }

    @Test func completeAuthorizationExchangesCodeAndStoresTokens() async throws {
        let transport = MockTransport([(200, #"{"token_type":"Bearer","access_token":"a1","refresh_token":"r1","expires_at":1900000000,"scope":"read,activity:read_all","athlete":{"firstname":"Max","lastname":"M"}}"#, [:])])
        let store = MemoryTokenStore()
        let client = StravaClient(config: config, store: store, transport: transport)
        let tokens = try await client.completeAuthorization(
            callbackURL: URL(string: "indoorcoach://localhost/strava?state=abc&code=CODE&scope=read,activity:read_all")!,
            expectedState: "abc")
        #expect(tokens.accessToken == "a1")
        #expect(store.tokens?.refreshToken == "r1")
        #expect(tokens.athleteName == "Max M")
        let body = String(data: transport.requests[0].httpBody!, encoding: .utf8)!
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=CODE"))
        #expect(body.contains("client_secret=s3cr%26t"))
    }

    @Test func rejectsWrongState() async {
        let client = StravaClient(config: config, store: MemoryTokenStore(), transport: MockTransport([]))
        await #expect(throws: StravaError.stateMismatch) {
            _ = try await client.completeAuthorization(
                callbackURL: URL(string: "indoorcoach://localhost/strava?state=evil&code=CODE")!, expectedState: "abc")
        }
    }

    @Test func rejectsMissingActivityScope() async {
        let client = StravaClient(config: config, store: MemoryTokenStore(), transport: MockTransport([]))
        await #expect(throws: StravaError.missingScope) {
            _ = try await client.completeAuthorization(
                callbackURL: URL(string: "indoorcoach://localhost/strava?state=abc&code=CODE&scope=read")!, expectedState: "abc")
        }
    }

    @Test func refreshesExpiredTokenAndPersistsRotatedRefreshToken() async throws {
        let store = MemoryTokenStore(StravaTokens(accessToken: "old", refreshToken: "r-old",
                                                  expiresAt: Date.now.addingTimeInterval(-10), athleteName: "Max"))
        let transport = MockTransport([(200, #"{"access_token":"new","refresh_token":"r-new","expires_at":1900000000}"#, [:])])
        let client = StravaClient(config: config, store: store, transport: transport)
        let token = try await client.validAccessToken()
        #expect(token == "new")
        #expect(store.tokens?.refreshToken == "r-new")
        #expect(store.tokens?.athleteName == "Max")
    }

    @Test func fetchRidesPaginatesAndUsesBearerToken() async throws {
        let store = MemoryTokenStore(StravaTokens(accessToken: "tok", refreshToken: "r", expiresAt: .distantFuture))
        let one = #"{"id":%d,"name":"R","sport_type":"VirtualRide","start_date":"2026-11-10T17:30:00Z","moving_time":3600,"distance":1}"#
        let page1 = "[" + (1...100).map { String(format: one, $0) }.joined(separator: ",") + "]"
        let page2 = "[" + String(format: one, 101) + "]"
        let transport = MockTransport([(200, page1, [:]), (200, page2, [:])])
        let client = StravaClient(config: config, store: store, transport: transport)
        let rides = try await client.fetchRides(after: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(rides.count == 101)
        #expect(transport.requests.count == 2)
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(transport.requests[1].url!.query!.contains("page=2"))
        #expect(transport.requests[0].url!.query!.contains("after=1700000000"))
    }

    @Test func mapsRateLimit() async {
        let store = MemoryTokenStore(StravaTokens(accessToken: "tok", refreshToken: "r", expiresAt: .distantFuture))
        let client = StravaClient(config: config, store: store, transport: MockTransport([(429, "{}", [:])]))
        await #expect(throws: StravaError.rateLimited(retryAfter: nil)) { _ = try await client.fetchRides(after: .distantPast) }
    }
}

@Suite("Claude coach")
struct ClaudeTests {
    let calendar = Calendar.current

    func context() -> PlanContext {
        let today = calendar.startOfDay(for: Formatters.isoDay.date(from: "2026-11-16")!)
        var profile = AthleteProfile()
        profile.ftp = 260
        profile.trainingDays = [2, 4, 6, 7]
        let rides = DemoData.rides(endingAt: today, ftp: 260)
        let series = TrainingLoad.series(dailyTSS: TrainingLoad.dailyTSS(rides: rides, ftp: 260),
                                         from: calendar.date(byAdding: .day, value: -90, to: today)!, to: today)
        return PlanContext(profile: profile, today: today,
                           horizonStart: calendar.date(byAdding: .day, value: 1, to: today)!,
                           horizonEnd: calendar.date(byAdding: .day, value: 7, to: today)!,
                           load: series.last,
                           weeks: TrainingLoad.weeks(rides: rides, ftp: 260, from: calendar.date(byAdding: .day, value: -42, to: today)!, to: today),
                           recentRides: rides,
                           alreadyPlanned: [PlannedWorkoutProposal(date: Formatters.isoDay.date(from: "2026-11-19")!,
                                                                   definition: DemoData.library.vo2, rationale: "")],
                           wish: "Diese Woche nur drei Einheiten")
    }

    @Test func userMessageContainsKeyFactsButNoRideNames() {
        let msg = PlanPrompt.userMessage(context())
        #expect(msg.contains("FTP: 260 W"))
        #expect(msg.contains("Fitness (CTL)"))
        #expect(msg.contains("von 2026-11-17 bis einschließlich 2026-11-23"))
        #expect(msg.contains("Wunsch des Athleten: Diese Woche nur drei Einheiten"))
        #expect(msg.contains("2026-11-19: VO₂max 5×4"))
        #expect(!msg.contains("Sonntagsrunde"), "Activity names are personal data and are not sent")
    }

    @Test func schemaIsClosedAndRequiresAllProperties() throws {
        let schema = PlanPrompt.schema
        let data = try JSONSerialization.data(withJSONObject: schema)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains(#""additionalProperties":false"#))
        let workout = ((schema["properties"] as! [String: Any])["workouts"] as! [String: Any])["items"] as! [String: Any]
        let segment = ((workout["properties"] as! [String: Any])["segments"] as! [String: Any])["items"] as! [String: Any]
        let props = Set((segment["properties"] as! [String: Any]).keys)
        #expect(props == Set(segment["required"] as! [String]))
        #expect(!text.contains("minimum"), "numeric constraints are not supported by structured outputs")
    }

    @Test func parseAcceptsValidAndRejectsInvalidWorkouts() throws {
        let json = """
        {"weekFocus":"Sweet Spot","notes":"Gut erholt starten.","workouts":[
          {"date":"2026-11-17","title":"Sweet Spot 3×12","type":"sweetSpot","summary":"s","rationale":"r","segments":[
            {"kind":"warmup","duration":600,"power":null,"powerLow":0.45,"powerHigh":0.75,"repeat":null,"onDuration":null,"offDuration":null,"onPower":null,"offPower":null,"cadence":null,"text":null},
            {"kind":"intervals","duration":0,"power":null,"powerLow":null,"powerHigh":null,"repeat":3,"onDuration":720,"offDuration":300,"onPower":0.9,"offPower":0.55,"cadence":null,"text":"Ruhig"},
            {"kind":"cooldown","duration":480,"power":null,"powerLow":0.4,"powerHigh":0.65,"repeat":null,"onDuration":null,"offDuration":null,"onPower":null,"offPower":null,"cadence":null,"text":null}]},
          {"date":"2026-11-19","title":"Doppelt","type":"endurance","summary":"s","rationale":"r","segments":[
            {"kind":"steady","duration":3600,"power":0.65,"powerLow":null,"powerHigh":null,"repeat":null,"onDuration":null,"offDuration":null,"onPower":null,"offPower":null,"cadence":null,"text":null}]},
          {"date":"2026-12-24","title":"Zu spät","type":"endurance","summary":"s","rationale":"r","segments":[
            {"kind":"steady","duration":3600,"power":0.65,"powerLow":null,"powerHigh":null,"repeat":null,"onDuration":null,"offDuration":null,"onPower":null,"offPower":null,"cadence":null,"text":null}]},
          {"date":"2026-11-21","title":"Kaputt","type":"bogus","summary":"s","rationale":"r","segments":[
            {"kind":"intervals","duration":0,"power":null,"powerLow":null,"powerHigh":null,"repeat":null,"onDuration":60,"offDuration":60,"onPower":1.2,"offPower":0.5,"cadence":null,"text":null}]},
          {"date":"2026-11-22","title":"Zu hart","type":"bogus","summary":"s","rationale":"r","segments":[
            {"kind":"steady","duration":2400,"power":9.0,"powerLow":null,"powerHigh":null,"repeat":null,"onDuration":null,"offDuration":null,"onPower":null,"offPower":null,"cadence":null,"text":null}]}
        ]}
        """
        let plan = try PlanPrompt.parse(json, context: context())
        #expect(plan.workouts.map(\.definition.title) == ["Sweet Spot 3×12", "Zu hart"])
        #expect(plan.workouts[0].definition.totalDuration == 75 * 60, "69 min + 6 min Aufwärm-Check")
        #expect(plan.workouts[1].definition.segments[0].power == 2.5, "power is clamped")
        #expect(plan.workouts[1].definition.type == .mixed, "unknown type falls back to mixed")
        #expect(plan.rejected.count == 3)
    }

    @Test func requestUsesStructuredOutputAndCurrentHeaders() throws {
        let client = ClaudeClient(apiKey: "sk-test", model: "claude-opus-5-5", transport: MockTransport([]))
        let request = try client.makeRequest(body: client.requestBody(system: "S", user: "U", schema: ["type": "object"], effort: "medium"))
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(body["model"] as? String == "claude-opus-5-5")
        let output = body["output_config"] as! [String: Any]
        #expect((output["format"] as! [String: Any])["type"] as? String == "json_schema")
        #expect(body["temperature"] == nil)
        #expect(body["thinking"] == nil, "Opus 5.5 rejects disabling thinking; adaptive is the default")
    }

    @Test func parsesTextAndHandlesRefusalAndTruncation() throws {
        let ok = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"a\":1}"}],"stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5},"model":"claude-opus-5-5"}"#
        #expect(try ClaudeClient.parseResponse(Data(ok.utf8)).text == #"{"a":1}"#)
        let refusal = #"{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}}"#
        #expect(throws: ClaudeError.refusal("cyber")) { try ClaudeClient.parseResponse(Data(refusal.utf8)) }
        let cut = #"{"content":[{"type":"text","text":"{\"a\":"}],"stop_reason":"max_tokens"}"#
        #expect(throws: ClaudeError.truncated) { try ClaudeClient.parseResponse(Data(cut.utf8)) }
    }

    @Test func mapsHTTPErrors() async {
        let unauthorized = ClaudeClient(apiKey: "bad", transport: MockTransport([(401, #"{"error":{"message":"invalid x-api-key"}}"#, [:])]))
        await #expect(throws: ClaudeError.invalidAPIKey) {
            _ = try await unauthorized.structuredJSON(system: "", user: "", schema: [:])
        }
        let badRequest = ClaudeClient(apiKey: "k", transport: MockTransport([(400, #"{"type":"error","error":{"type":"invalid_request_error","message":"nope"}}"#, [:])]))
        await #expect(throws: ClaudeError.http(400, "nope")) {
            _ = try await badRequest.structuredJSON(system: "", user: "", schema: [:])
        }
        let missing = ClaudeClient(apiKey: "")
        await #expect(throws: ClaudeError.missingAPIKey) {
            _ = try await missing.structuredJSON(system: "", user: "", schema: [:])
        }
    }

    @Test func llmTextIsCleanedAndClamped() {
        #expect(PlanPrompt.clean("Sweet\u{0000} Spot\u{0007}\n", max: 80) == "Sweet Spot")
        #expect(PlanPrompt.clean(String(repeating: "a", count: 100), max: 10).count == 10)
        var seg = Segment.steady(10, at: 0.9, cadence: 9999, text: String(repeating: "x", count: 200))
        seg = PlanPrompt.sanitize(seg)!
        #expect(seg.cadence == nil)
        #expect(seg.text!.count == 60)
        #expect(PlanPrompt.sanitize(.intervals(3, on: 0, at: 1.2, off: 60, at: 0.5)) == nil)
    }

    @Test func retriesWithoutFallbackWhenRejected() async throws {
        let ok = #"{"content":[{"type":"text","text":"{}"}],"stop_reason":"end_turn"}"#
        let transport = MockTransport([(400, #"{"error":{"message":"fallbacks: unknown parameter"}}"#, [:]), (200, ok, [:])])
        let client = ClaudeClient(apiKey: "k", transport: transport)
        _ = try await client.structuredJSON(system: "", user: "", schema: [:])
        #expect(transport.requests.count == 2)
        let second = try JSONSerialization.jsonObject(with: transport.requests[1].httpBody!) as! [String: Any]
        #expect(second["fallbacks"] == nil)
        #expect(transport.requests[1].value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test func errorMessagesRedactKeys() {
        let msg = ClaudeClient.redact("invalid key sk-ant-api03-ABC_def-123 provided")
        #expect(msg == "invalid key sk-ant-… provided")
    }

    @Test func demoCoachRespectsTrainingDaysAndExistingPlan() throws {
        let ctx = context()
        let plan = DemoCoach.makePlan(ctx)
        #expect(!plan.workouts.isEmpty)
        for w in plan.workouts {
            #expect(ctx.profile.trainingDays.contains(AthleteProfile.isoWeekday(of: w.date)))
            #expect(Formatters.isoDay.string(from: w.date) != "2026-11-19")
        }
    }
}
