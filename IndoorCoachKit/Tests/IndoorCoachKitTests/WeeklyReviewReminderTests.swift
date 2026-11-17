import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

final class FakeReminderCenter: ReminderCenter, @unchecked Sendable {
    struct Entry: Equatable { var weekday: Int, hour: Int, minute: Int, title: String }
    private let lock = NSLock()
    private var status: ReminderAuthorization
    private let grants: Bool
    private let failsToSchedule: Bool
    private var _pending: [String: Entry] = [:]
    private var _prompts = 0

    init(status: ReminderAuthorization, grants: Bool = true, failsToSchedule: Bool = false) {
        self.status = status; self.grants = grants; self.failsToSchedule = failsToSchedule
    }

    var pending: [String: Entry] { lock.withLock { _pending } }
    var prompts: Int { lock.withLock { _prompts } }

    func authorization() async -> ReminderAuthorization { lock.withLock { status } }
    func requestAuthorization() async -> Bool {
        lock.withLock {
            _prompts += 1
            status = grants ? .authorized : .denied
            return grants
        }
    }
    func scheduleWeekly(id: String, weekday: Int, hour: Int, minute: Int, title: String, body: String) async throws {
        if failsToSchedule { throw URLError(.unknown) }
        lock.withLock { _pending[id] = Entry(weekday: weekday, hour: hour, minute: minute, title: title) }
    }
    func cancel(id: String) { lock.withLock { _pending[id] = nil } }
}

@Suite("Wochenrückblick-Erinnerung")
struct WeeklyReviewReminderTests {
    @Test func enableSchedulesSundayEighteenWhenAuthorized() async {
        let center = FakeReminderCenter(status: .authorized)
        #expect(await WeeklyReviewReminder.enable(center: center) == .scheduled)
        #expect(center.prompts == 0)
        #expect(center.pending[WeeklyReviewReminder.identifier]
                == .init(weekday: 1, hour: 18, minute: 0, title: "Dein Wochenrückblick ist da"))
    }

    @Test func enableAsksOnceAndSchedulesWhenGranted() async {
        let center = FakeReminderCenter(status: .notDetermined, grants: true)
        #expect(await WeeklyReviewReminder.enable(center: center) == .scheduled)
        #expect(center.prompts == 1)
        #expect(center.pending.count == 1)
    }

    @Test func declinedPromptSchedulesNothing() async {
        let center = FakeReminderCenter(status: .notDetermined, grants: false)
        #expect(await WeeklyReviewReminder.enable(center: center) == .denied)
        #expect(center.pending.isEmpty)
    }

    @Test func deniedInSettingsDoesNotPromptAgain() async {
        let center = FakeReminderCenter(status: .denied)
        #expect(await WeeklyReviewReminder.enable(center: center) == .denied)
        #expect(center.prompts == 0 && center.pending.isEmpty)
    }

    @Test func schedulingFailureIsReported() async {
        let center = FakeReminderCenter(status: .authorized, failsToSchedule: true)
        #expect(await WeeklyReviewReminder.enable(center: center) == .failed)
    }

    @Test func enablingTwiceKeepsOneNotification() async {
        let center = FakeReminderCenter(status: .authorized)
        _ = await WeeklyReviewReminder.enable(center: center)
        _ = await WeeklyReviewReminder.schedule(center: center)
        #expect(center.pending.count == 1)
    }

    @Test func disableRemovesThePendingNotification() async {
        let center = FakeReminderCenter(status: .authorized)
        _ = await WeeklyReviewReminder.enable(center: center)
        WeeklyReviewReminder.disable(center: center)
        #expect(center.pending.isEmpty)
    }

    @Test func profileFieldDefaultsToOffAndSurvivesOldJSON() throws {
        #expect(AthleteProfile().weeklyReviewReminder == false)
        let old = try JSONDecoder().decode(AthleteProfile.self, from: Data(#"{"ftp": 280, "name": "A"}"#.utf8))
        #expect(old.ftp == 280)
        #expect(old.weeklyReviewReminder == false)
        var p = AthleteProfile()
        p.weeklyReviewReminder = true
        let back = try JSONDecoder().decode(AthleteProfile.self, from: JSONEncoder().encode(p))
        #expect(back.weeklyReviewReminder)
    }

    @Test @MainActor func deleteAllDataRemovesThePendingNotification() async throws {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let suite = "reminder-delete-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        let center = FakeReminderCenter(status: .authorized)
        model.reminderCenter = center
        model.profile.weeklyReviewReminder = true
        _ = await WeeklyReviewReminder.enable(center: center)
        #expect(center.pending.count == 1)
        await model.deleteAllData()
        #expect(center.pending.isEmpty)
        #expect(model.profile.weeklyReviewReminder == false)
    }
}
