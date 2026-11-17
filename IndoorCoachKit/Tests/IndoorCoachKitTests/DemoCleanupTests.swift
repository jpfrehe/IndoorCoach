import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Demo cleanup")
@MainActor
struct DemoCleanupTests {
    static let realRideID = 12_345_678_901
    static let realRide = """
    [{"id":\(realRideID),"name":"Echte Fahrt","sport_type":"VirtualRide","start_date":"2026-11-10T17:30:00Z",
      "moving_time":3600,"distance":30000}]
    """
    static let tokenResponse = #"{"access_token":"a","refresh_token":"r","expires_at":4000000000,"scope":"read,activity:read_all"}"#

    let container: ModelContainer
    let secrets = InMemorySecretStore()
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!

    init() throws {
        container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defaults.set("123", forKey: AppModel.Keys.stravaClientID)
        secrets.setSecret("secret", for: .stravaClientSecret)
    }

    func model(_ responses: [(Int, String, [String: String])]) -> AppModel {
        AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: MockTransport(responses))
    }

    func rides(_ model: AppModel) throws -> [StoredRide] { try model.context.fetch(FetchDescriptor<StoredRide>()) }
    func workouts(_ model: AppModel) throws -> [StoredWorkout] { try model.context.fetch(FetchDescriptor<StoredWorkout>()) }

    /// Adds one Claude workout and accepts one DemoCoach proposal (what a user without Claude key does).
    func addUserWorkouts(_ model: AppModel) async {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        model.context.insert(StoredWorkout(proposal: PlannedWorkoutProposal(date: tomorrow, definition: DemoData.library.vo2,
                                                                            rationale: "Claude"),
                                           source: .claude, weekFocus: nil))
        model.proposal = PlanProposal(weekFocus: "x", notes: "",
                                      workouts: [PlannedWorkoutProposal(date: tomorrow, definition: DemoData.library.tempo,
                                                                        rationale: "Vom Nutzer übernommen")],
                                      rejected: [])
        await model.acceptProposal(addToCalendar: false)
    }

    @Test func connectingStravaRemovesDemoDataButKeepsUserWorkouts() async throws {
        let model = model([(200, Self.tokenResponse, [:]), (200, Self.realRide, [:])])
        model.bootstrap()
        let seededWorkouts = try workouts(model).count
        #expect(try rides(model).allSatisfy(\.isDemo) && !rides(model).isEmpty)
        #expect(seededWorkouts > 0)
        await addUserWorkouts(model)

        await model.connectStrava { url in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "indoorcoach://localhost/strava?state=\(state)&code=C&scope=read,activity:read_all")!
        }

        #expect(model.isStravaConnected)
        #expect(try rides(model).map(\.stravaID) == [Self.realRideID])
        let titles = Set(try workouts(model).map(\.rationale))
        #expect(titles == ["Claude", "Vom Nutzer übernommen"], "only seeded demo workouts are removed")
    }

    @Test func firstRealSyncRemovesLeftoverDemoData() async throws {
        let model = model([(200, Self.realRide, [:])])
        model.bootstrap()
        await addUserWorkouts(model)
        // Tokens appear without the connect flow (e.g. restored from the Keychain).
        secrets.saveTokens(StravaTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture))
        model.refreshCredentialState()

        await model.syncStrava()

        #expect(try rides(model).map(\.stravaID) == [Self.realRideID])
        #expect(Set(try workouts(model).map(\.rationale)) == ["Claude", "Vom Nutzer übernommen"])
    }

    @Test func regularSyncKeepsEverythingReal() async throws {
        secrets.saveTokens(StravaTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture))
        let model = model([(200, Self.realRide, [:]), (200, "[]", [:])])
        model.bootstrap() // connected: no demo seeding
        #expect(try rides(model).isEmpty)
        await model.syncStrava()
        await addUserWorkouts(model)
        await model.syncStrava()
        #expect(try rides(model).map(\.stravaID) == [Self.realRideID])
        #expect(try workouts(model).count == 2)
    }

    @Test func failedSyncKeepsDemoData() async throws {
        let model = model([(429, "{}", [:])])
        model.bootstrap()
        let demoRides = try rides(model).count
        secrets.saveTokens(StravaTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture))
        model.refreshCredentialState()
        await model.syncStrava()
        #expect(try rides(model).count == demoRides)
    }
}
