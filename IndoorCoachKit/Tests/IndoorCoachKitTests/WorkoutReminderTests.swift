import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Records one-shot notifications (the weekly-review fake lives in `WeeklyReviewReminderTests`).
final class FakeOnceCenter: ReminderCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var status: ReminderAuthorization
    private var _once: [String: (date: Date, body: String)] = [:]
    init(status: ReminderAuthorization = .authorized) { self.status = status }
    var once: [String: (date: Date, body: String)] { lock.withLock { _once } }
    func authorization() async -> ReminderAuthorization { lock.withLock { status } }
    func requestAuthorization() async -> Bool { lock.withLock { status = .authorized }; return true }
    func scheduleWeekly(id: String, weekday: Int, hour: Int, minute: Int, title: String, body: String) async throws {}
    func scheduleOnce(id: String, at date: Date, title: String, body: String) async throws {
        lock.withLock { _once[id] = (date, body) }
    }
    func cancel(id: String) { lock.withLock { _once[id] = nil } }
    func cancelAll(withPrefix prefix: String) async {
        lock.withLock { _once = _once.filter { !$0.key.hasPrefix(prefix) } }
    }
}

@Suite("Erinnerung vor Einheiten")
struct WorkoutReminderTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func item(hours: Double, status: WorkoutStatus = .planned, title: String = "Sweet Spot 3×12") -> WorkoutReminder.Item {
        WorkoutReminder.Item(id: UUID(), title: title, start: now.addingTimeInterval(hours * 3600),
                             duration: 4140, tss: 72.4, status: status)
    }

    @Test func schedulesThirtyMinutesBeforeWithTheSpecText() {
        let w = item(hours: 5)
        let r = WorkoutReminder.plan(items: [w], now: now)
        #expect(r.count == 1)
        #expect(r[0].id == "workout.\(w.id.uuidString)")
        #expect(r[0].fireDate == w.start.addingTimeInterval(-1800))
        #expect(r[0].body == "Gleich: Sweet Spot 3×12 · 1:09 h · TSS 72")
    }

    @Test func skipsDoneSkippedPastAndBeyondFourteenDays() {
        let items = [item(hours: 5, status: .done), item(hours: 5, status: .skipped), item(hours: -2),
                     item(hours: 0.3),                       // fire time (−12 min) already passed
                     item(hours: 14 * 24 + 1), item(hours: 24)]
        #expect(WorkoutReminder.plan(items: items, now: now).count == 1)
    }

    @Test func capsAtTwentyEarliestFirst() {
        let items = (1...30).map { item(hours: Double(31 - $0) * 2) }
        let r = WorkoutReminder.plan(items: items, now: now)
        #expect(r.count == 20)
        #expect(r == r.sorted { $0.fireDate < $1.fireDate })
        #expect(r.first?.fireDate == items.map(\.start).min()!.addingTimeInterval(-1800))
    }

    @Test func rescheduleReplacesOldOnesAndNeedsPermission() async {
        let center = FakeOnceCenter()
        let a = item(hours: 5), b = item(hours: 30)
        await WorkoutReminder.reschedule(items: [a, b], now: now, center: center)
        #expect(center.once.count == 2)
        await WorkoutReminder.reschedule(items: [b], now: now, center: center)
        #expect(Set(center.once.keys) == ["workout.\(b.id.uuidString)"])
        let denied = FakeOnceCenter(status: .denied)
        await WorkoutReminder.reschedule(items: [a], now: now, center: denied)
        #expect(denied.once.isEmpty)
    }

    @Test func profileFieldDefaultsOffAndSurvivesOldJSON() throws {
        #expect(AthleteProfile().workoutReminder == false)
        let old = try JSONDecoder().decode(AthleteProfile.self, from: Data(#"{"ftp": 280}"#.utf8))
        #expect(old.workoutReminder == false)
        var p = AthleteProfile(); p.workoutReminder = true
        #expect(try JSONDecoder().decode(AthleteProfile.self, from: JSONEncoder().encode(p)).workoutReminder)
    }

    @MainActor
    func makeModel(_ center: FakeOnceCenter) throws -> (AppModel, ModelContainer) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let suite = "workout-reminder-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        model.reminderCenter = center
        return (model, container)
    }

    @Test @MainActor func modelSchedulesOnlyWhenOptedInAndRemovesOnDeleteAndWipe() async throws {
        let center = FakeOnceCenter()
        let (model, container) = try makeModel(center)
        let context = container.mainContext
        let day = Calendar.current.date(byAdding: .day, value: 2, to: .now)!
        let def = WorkoutDefinition(title: "Grundlage", type: .endurance, summary: "locker",
                                    segments: [Segment(kind: .steady, duration: 3600, power: 0.65)])
        func make() -> StoredWorkout {
            StoredWorkout(proposal: PlannedWorkoutProposal(date: day, definition: def, rationale: ""), source: .demo, weekFocus: nil)
        }
        let stored = make()
        context.insert(stored)
        try context.save()

        await model.rescheduleWorkoutReminders()
        #expect(center.once.isEmpty)                       // opt-in only

        model.profile.workoutReminder = true
        await model.rescheduleWorkoutReminders()
        #expect(center.once.count == 1)

        await model.delete(stored)
        #expect(center.once.isEmpty)

        context.insert(make())
        await model.rescheduleWorkoutReminders()
        #expect(center.once.count == 1)
        await model.deleteAllData()
        #expect(center.once.isEmpty)
    }
}
