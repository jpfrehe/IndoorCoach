import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

private struct OfflineTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.notConnectedToInternet) }
}

@Suite("Claude-Key prüfen")
struct ClaudeKeyValidationTests {
    private func client(_ transport: HTTPTransport, key: String = "sk-ant-test-abc") -> ClaudeClient {
        ClaudeClient(apiKey: key, transport: transport)
    }

    @Test func requestIsAFreeModelsListCall() async throws {
        let transport = MockTransport([(200, #"{"data":[]}"#, [:])])
        try await client(transport).validateKey()
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=1")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test-abc")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == ClaudeClient.apiVersion)
        #expect(request.httpBody == nil)
    }

    @Test func status401IsInvalidKey() async {
        let transport = MockTransport([(401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#, [:])])
        await #expect(throws: ClaudeError.invalidAPIKey) { try await client(transport).validateKey() }
    }

    @Test func status403IsPermissionError() async {
        let transport = MockTransport([(403, #"{"type":"error","error":{"type":"permission_error","message":"no"}}"#, [:])])
        await #expect(throws: ClaudeError.permissionDenied) { try await client(transport).validateKey() }
    }

    @Test func serverErrorIsReportedAsHTTPError() async {
        let transport = MockTransport([(529, #"{"error":{"message":"overloaded"}}"#, [:])])
        await #expect(throws: ClaudeError.http(529, "overloaded")) { try await client(transport).validateKey() }
    }

    @Test func emptyKeyThrowsMissing() async {
        await #expect(throws: ClaudeError.missingAPIKey) { try await client(MockTransport([]), key: "").validateKey() }
    }
}

@MainActor
@Suite("Onboarding-Journey")
struct OnboardingJourneyTests {
    let container = try! AppEnvironment.makeContainer(inMemory: true)
    let defaults = UserDefaults(suiteName: "journey-\(UUID().uuidString)")!
    let secrets = InMemorySecretStore()

    func makeModel(transport: HTTPTransport = MockTransport([]),
                   store: MyWhooshSessionStore = InMemoryMyWhooshSessionStore()) -> AppModel {
        AppModel(context: container.mainContext, secrets: secrets, defaults: defaults,
                 transport: transport, myWhooshStore: store)
    }

    // MARK: Step persistence

    @Test func freshInstallStartsAtStepZero() {
        #expect(makeModel().onboardingStep == 0)
    }

    @Test func stepIsPersistedAndResumed() {
        let first = makeModel()
        first.onboardingStep = 3
        let second = makeModel()
        #expect(second.needsOnboarding)
        #expect(second.onboardingStep == 3)
    }

    @Test func storedStepIsClamped() {
        defaults.set(99, forKey: AppModel.Keys.onboardingStep)
        #expect(makeModel().onboardingStep == AppModel.onboardingStepCount - 1)
        defaults.set(-4, forKey: AppModel.Keys.onboardingStep)
        #expect(makeModel().onboardingStep == 0)
    }

    @Test func completingResetsTheStep() {
        let model = makeModel()
        model.onboardingStep = 4
        model.completeOnboarding()
        #expect(model.onboardingStep == 0)
        #expect(defaults.object(forKey: AppModel.Keys.onboardingStep) == nil)
        #expect(!makeModel().needsOnboarding)
    }

    @Test func stepKeyIsWipedWithAllData() {
        #expect(AppModel.Keys.all.contains(AppModel.Keys.onboardingStep))
    }

    @Test func existingInstallThatFinishedV1NeverSeesTheNewFlow() {
        defaults.set(true, forKey: AppModel.Keys.onboardingCompleted) // set by the v1 onboarding
        let model = makeModel()
        #expect(!model.needsOnboarding)
        #expect(model.onboardingStep == 0)
    }

    // MARK: FTP "Weiß ich nicht"

    @Test(arguments: [(75.0, 190), (70.0, 175), (82.5, 205), (60.0, 150), (68.0, 170), (90.0, 225)])
    func estimatedFTPIs25WattsPerKiloRoundedToFive(weight: Double, expected: Int) {
        #expect(AppModel.estimatedFTP(weightKg: weight) == expected)
    }

    @Test func estimatedFTPStaysInTheAllowedRange() {
        #expect(AppModel.estimatedFTP(weightKg: 40) == 100)
        #expect(AppModel.estimatedFTP(weightKg: 150) == 375)
        #expect((80...500).contains(AppModel.estimatedFTP(weightKg: 10)))
    }

    @Test func estimateFTPUpdatesTheProfile() {
        let model = makeModel()
        model.profile.weightKg = 72
        model.estimateFTP()
        #expect(model.profile.ftp == 180)
    }

    // MARK: Claude key

    @Test func validKeyIsStored() async {
        let model = makeModel(transport: MockTransport([(200, "{}", [:])]))
        let result = await model.validateAndStoreClaudeKey("  sk-ant-test-0000000000000000000000 \n")
        #expect(result == .valid)
        #expect(model.hasClaudeKey)
        #expect(secrets.secret(.claudeAPIKey) == "sk-ant-test-0000000000000000000000")
    }

    @Test func rejectedKeyIsNotStored() async {
        let model = makeModel(transport: MockTransport([(401, "{}", [:])]))
        #expect(await model.validateAndStoreClaudeKey("sk-ant-wrong-000000000000000") == .invalid)
        #expect(!model.hasClaudeKey)
    }

    @Test func forbiddenKeyIsNotStored() async {
        let model = makeModel(transport: MockTransport([(403, "{}", [:])]))
        #expect(await model.validateAndStoreClaudeKey("sk-ant-nopermission-0000000") == .forbidden)
        #expect(!model.hasClaudeKey)
    }

    @Test func networkErrorIsUnreachableAndDoesNotStore() async {
        let model = makeModel(transport: OfflineTransport())
        #expect(await model.validateAndStoreClaudeKey("sk-ant-test-0000000000000000000000") == .unreachable)
        #expect(!model.hasClaudeKey)
    }

    @Test func emptyKeyIsInvalidWithoutARequest() async {
        let transport = MockTransport([(200, "{}", [:])])
        let model = makeModel(transport: transport)
        #expect(await model.validateAndStoreClaudeKey("   ") == .invalid)
        #expect(transport.requests.isEmpty)
    }

    // MARK: Finish summary

    @Test func summaryReflectsWhatIsConnected() {
        let model = makeModel()
        var summary = model.onboardingSummary
        #expect(summary.profileReady)
        #expect(!summary.myWhooshConnected && !summary.coachReady)
        model.setClaudeAPIKey("sk-ant-test-0000000000000000000000")
        summary = model.onboardingSummary
        #expect(summary.coachReady && !summary.myWhooshConnected)
        #expect(summary.items.map(\.isDone) == [true, false, true])
    }

    @Test func summaryNeedsAtLeastOneTrainingDay() {
        let model = makeModel()
        model.profile.trainingDays = []
        #expect(!model.onboardingSummary.profileReady)
    }

    @Test func summaryLabelsAreSpokenGerman() {
        let items = makeModel().onboardingSummary.items
        #expect(items.map(\.title) == ["Profil", "MyWhoosh", "Coach"])
        #expect(items[1].accessibilityLabel == "MyWhoosh: nicht verbunden")
        #expect(items[0].accessibilityLabel == "Profil: eingerichtet")
    }

    // MARK: MyWhoosh

    @Test func connectingReportsLoadedRideCount() async {
        let login = #"{"Success":true,"WhooshId":"w1","AccessToken":"a.b.c","RefreshToken":"r"}"#
        let day = ISO8601DateFormatter().string(from: .now.addingTimeInterval(-86_400))
        let activities = #"{"activities":[{"id":"1","startDatetime":"\#(day)","rideDuration":3600,"distance":30,"watt":180}]}"#
        let model = makeModel(transport: MockTransport([(200, login, [:]), (200, activities, [:])]))
        #expect(await model.connectMyWhoosh(username: "a@b.de", password: "pw"))
        #expect(model.isMyWhooshConnected)
        #expect(model.importedRideCount == 1)
        #expect(model.onboardingSummary.myWhooshConnected)
    }

    @Test func failedLoginKeepsTheMessageForTheForm() async {
        let model = makeModel(transport: MockTransport([(401, "{}", [:])]))
        #expect(await model.connectMyWhoosh(username: "a@b.de", password: "bad") == false)
        #expect(model.lastMyWhooshError?.isEmpty == false)
    }
}
