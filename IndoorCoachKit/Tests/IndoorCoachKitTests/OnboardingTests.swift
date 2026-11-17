import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@MainActor
@Suite("Onboarding flag")
struct OnboardingTests {
    let container = try! AppEnvironment.makeContainer(inMemory: true)
    let defaults = UserDefaults(suiteName: "onboarding-\(UUID().uuidString)")!

    func makeModel() -> AppModel {
        AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
    }

    @Test func decisionTable() {
        #expect(AppModel.needsOnboarding(completedFlag: nil, isExistingInstall: false))
        #expect(!AppModel.needsOnboarding(completedFlag: nil, isExistingInstall: true))
        #expect(!AppModel.needsOnboarding(completedFlag: true, isExistingInstall: false))
        #expect(AppModel.needsOnboarding(completedFlag: false, isExistingInstall: true))
    }

    @Test func freshInstallShowsOnboarding() {
        let model = makeModel()
        #expect(model.needsOnboarding)
        #expect(defaults.object(forKey: AppModel.Keys.onboardingCompleted) as? Bool == false)
    }

    @Test func existingProfileSkipsOnboardingAfterUpdate() throws {
        defaults.set(try JSONEncoder().encode(AthleteProfile()), forKey: AppModel.Keys.profile)
        #expect(!makeModel().needsOnboarding)
        #expect(defaults.bool(forKey: AppModel.Keys.onboardingCompleted))
    }

    @Test func existingDemoDataWithoutSavedProfileSkipsOnboarding() {
        makeModel().bootstrap() // a previous version seeded demo data but never saved a profile
        defaults.removeObject(forKey: AppModel.Keys.onboardingCompleted)
        defaults.removeObject(forKey: AppModel.Keys.profile)
        #expect(!makeModel().needsOnboarding)
    }

    @Test func completedOnboardingIsNotShownAgain() {
        let first = makeModel()
        #expect(first.needsOnboarding)
        first.completeOnboarding()
        #expect(!first.needsOnboarding)
        #expect(!makeModel().needsOnboarding)
    }

    @Test func interruptedOnboardingIsShownAgain() {
        let first = makeModel()
        first.profile.ftp = 280 // writes profile.v1, then the app is killed before finishing
        let second = makeModel()
        #expect(second.needsOnboarding)
        #expect(second.profile.ftp == 280)
    }

    @Test func completingRegeneratesDemoDataForTheChosenFTP() throws {
        let model = makeModel()
        model.bootstrap()
        let before = try container.mainContext.fetchCount(FetchDescriptor<StoredRide>())
        model.profile.ftp = 320
        model.completeOnboarding()
        let rides = try container.mainContext.fetch(FetchDescriptor<StoredRide>())
        #expect(before > 0)
        #expect(rides.count > 0 && rides.allSatisfy(\.isDemo))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StoredWorkout>()) > 0)
    }
}
