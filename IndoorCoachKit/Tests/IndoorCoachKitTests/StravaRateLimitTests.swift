import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Records the backoff delays instead of sleeping.
final class RecordingSleeper: @unchecked Sendable {
    private(set) var delays: [Duration] = []
    private let lock = NSLock()
    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] d in lock.withLock { delays.append(d) } }
    }
}

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func utcDate(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: h, minute: m, second: s))!
}

private func response(_ code: Int, _ headers: [String: String]) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://www.strava.com/api/v3/athlete/activities")!, statusCode: code,
                    httpVersion: nil, headerFields: headers)!
}

@Suite("Strava rate limits & retries")
struct StravaRateLimitTests {
    let config = StravaConfig(clientID: "123", clientSecret: "secret")
    let connected = StravaTokens(accessToken: "tok-SECRET", refreshToken: "r", expiresAt: .distantFuture)

    func client(_ transport: MockTransport, sleeper: RecordingSleeper = RecordingSleeper()) -> StravaClient {
        StravaClient(config: config, store: MemoryTokenStore(connected), transport: transport, sleep: sleeper.sleep)
    }

    // MARK: Messages

    @Test func rateLimitMessageIsGermanAndNamesMinutes() {
        #expect(StravaError.rateLimited(retryAfter: 600).errorDescription
                == "Strava-Limit erreicht – bitte in ca. 10 Minuten erneut synchronisieren.")
        #expect(StravaError.rateLimited(retryAfter: 61).errorDescription
                == "Strava-Limit erreicht – bitte in ca. 2 Minuten erneut synchronisieren.")
        #expect(StravaError.rateLimited(retryAfter: 5).errorDescription
                == "Strava-Limit erreicht – bitte in ca. 1 Minute erneut synchronisieren.")
        #expect(StravaError.rateLimited(retryAfter: nil).errorDescription
                == "Strava-Limit erreicht – bitte in ca. 15 Minuten erneut synchronisieren.")
        #expect(StravaError.rateLimited(retryAfter: 5 * 3600 + 10).errorDescription
                == "Strava-Tageslimit erreicht – bitte in ca. 6 Stunden erneut synchronisieren.")
    }

    // MARK: Header parsing

    @Test func retryAfterHeaderInSecondsWins() {
        let r = response(429, ["Retry-After": "120", "X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "201,300"])
        #expect(StravaClient.retryAfter(from: r, now: utcDate(10, 7)) == 120)
    }

    @Test func fifteenMinuteWindowResetsAtNextQuarterHour() {
        let r = response(429, ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "201,300"])
        #expect(StravaClient.retryAfter(from: r, now: utcDate(10, 7, 30)) == TimeInterval(7 * 60 + 30))
    }

    @Test func dailyLimitResetsAtMidnightUTC() {
        let r = response(429, ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "12,2000"])
        #expect(StravaClient.retryAfter(from: r, now: utcDate(22, 0)) == TimeInterval(2 * 3600))
    }

    @Test func readLimitHeadersAreHonoured() {
        let r = response(429, ["X-ReadRateLimit-Limit": "100,1000", "X-ReadRateLimit-Usage": "101,200",
                               "X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "101,200"])
        #expect(StravaClient.retryAfter(from: r, now: utcDate(10, 14)) == TimeInterval(60))
    }

    @Test func noUsableHeadersMeansUnknown() {
        #expect(StravaClient.retryAfter(from: response(429, [:]), now: utcDate(10, 0)) == nil)
        #expect(StravaClient.retryAfter(from: response(429, ["X-RateLimit-Usage": "garbage"]), now: utcDate(10, 0)) == nil)
    }

    // MARK: Client behaviour

    @Test func rateLimitSurfacesRetryAfterAndIsNotRetried() async {
        let transport = MockTransport([(429, #"{"message":"Rate Limit Exceeded"}"#, ["Retry-After": "540"])])
        let sleeper = RecordingSleeper()
        await #expect(throws: StravaError.rateLimited(retryAfter: 540)) {
            _ = try await client(transport, sleeper: sleeper).fetchRides(after: .distantPast)
        }
        #expect(transport.requests.count == 1)
        #expect(sleeper.delays.isEmpty)
    }

    @Test func serverErrorIsRetriedOnceAfterBackoff() async throws {
        let ride = #"[{"id":1,"name":"R","sport_type":"VirtualRide","start_date":"2026-11-10T17:30:00Z","moving_time":3600,"distance":1}]"#
        let transport = MockTransport([(503, "<html>down</html>", [:]), (200, ride, [:])])
        let sleeper = RecordingSleeper()
        let rides = try await client(transport, sleeper: sleeper).fetchRides(after: .distantPast)
        #expect(rides.map(\.id) == [1])
        #expect(transport.requests.count == 2)
        #expect(sleeper.delays.count == 1)
        #expect(sleeper.delays[0] <= .seconds(5))
    }

    @Test func persistentServerErrorGivesUpAfterOneRetry() async {
        let transport = MockTransport([(502, "<html>bad gateway</html>", [:]), (502, "<html>bad gateway</html>", [:]),
                                       (200, "[]", [:])])
        let sleeper = RecordingSleeper()
        await #expect(throws: StravaError.unavailable(502)) {
            _ = try await client(transport, sleeper: sleeper).fetchRides(after: .distantPast)
        }
        #expect(transport.requests.count == 2)
        #expect(sleeper.delays.count == 1)
        let message = StravaError.unavailable(502).errorDescription ?? ""
        #expect(message.contains("Strava ist gerade nicht erreichbar"))
        #expect(!message.contains("html"))
    }

    @Test func errorsNeverContainTheAccessToken() async {
        let transport = MockTransport([(400, #"{"message":"bad token tok-SECRET"}"#, [:])])
        do {
            _ = try await client(transport).fetchRides(after: .distantPast)
            Issue.record("expected an error")
        } catch {
            // The server echo is redacted before it reaches the UI.
            #expect(!error.localizedDescription.contains("tok-SECRET"))
        }
    }
}

@Suite("Strava sync robustness")
@MainActor
struct StravaSyncRobustnessTests {
    static let one = #"{"id":%d,"name":"R","sport_type":"VirtualRide","start_date":"2026-11-10T17:30:00Z","moving_time":3600,"distance":1}"#

    @Test func syncFailingMidPaginationKeepsStoredRidesAndLastSync() async throws {
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let previousSync = Date(timeIntervalSince1970: 1_790_000_000)
        defaults.set(previousSync, forKey: AppModel.Keys.lastSync)
        defaults.set("123", forKey: AppModel.Keys.stravaClientID)
        let secrets = InMemorySecretStore()
        secrets.setSecret("secret", for: .stravaClientSecret)
        secrets.saveTokens(StravaTokens(accessToken: "tok", refreshToken: "r", expiresAt: .distantFuture))

        let page1 = "[" + (1...100).map { String(format: Self.one, 1_000_000 + $0) }.joined(separator: ",") + "]"
        let transport = MockTransport([(200, page1, [:]),
                                       (429, "{}", ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "200,900"])])
        let model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: transport)
        let existing = RideSummary(id: 42, name: "Schon da", sportType: "VirtualRide", startDate: previousSync,
                                   movingTime: 3600, distance: 1, averageWatts: nil, weightedAverageWatts: nil,
                                   kilojoules: nil, averageHeartrate: nil, maxHeartrate: nil, trainer: true)
        model.context.insert(StoredRide(existing))
        try model.context.save()

        await model.syncStrava()

        let rides = try model.context.fetch(FetchDescriptor<StoredRide>())
        #expect(rides.map(\.stravaID).contains(42))
        #expect(model.lastSync == previousSync)
        #expect(defaults.object(forKey: AppModel.Keys.lastSync) as? Date == previousSync)
        #expect(model.banner?.isError == true)
        #expect(model.banner?.message.hasPrefix("Strava-Limit erreicht – bitte in ca.") == true)
        #expect(model.isStravaConnected, "a rate limit must not look like a disconnect")
        #expect(!model.isSyncing)
    }
}
