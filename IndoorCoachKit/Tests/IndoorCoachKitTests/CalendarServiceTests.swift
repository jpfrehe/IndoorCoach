import Foundation
import Testing
@testable import IndoorCoachKit

/// In-memory stand-in for EventKit; "external" edits simulate the user changing things in the Calendar app.
@MainActor
final class FakeCalendarBackend: CalendarBackend {
    struct Calendar { var title: String; var writable = true }
    var calendars: [String: Calendar] = ["default": Calendar(title: "Privat")]
    var events: [String: (calendarID: String, draft: CalendarEventDraft)] = [:]
    var defaultCalendarID: String? = "default"
    var accessGranted = true
    var canCreateCalendars = true
    private var nextID = 0

    private func makeID(_ prefix: String) -> String { nextID += 1; return "\(prefix)-\(nextID)" }

    func requestAccess() async throws {
        guard accessGranted else { throw CalendarError.accessDenied }
    }

    func updateEvent(id: String, with draft: CalendarEventDraft) throws -> String? {
        guard let event = events[id], calendars[event.calendarID]?.writable == true else { return nil }
        events[id] = (event.calendarID, draft)
        return id
    }

    func createEvent(in calendarID: String, with draft: CalendarEventDraft) throws -> String {
        guard calendars[calendarID] != nil else { throw CalendarError.noCalendar }
        let id = makeID("event")
        events[id] = (calendarID, draft)
        return id
    }

    func removeEvent(id: String) throws { events[id] = nil }

    func writableCalendarID(titled title: String) -> String? {
        calendars.first { $0.value.title == title && $0.value.writable }?.key
    }

    func createCalendar(titled title: String) throws -> String {
        guard canCreateCalendars else { throw CalendarError.noCalendar }
        let id = makeID("calendar")
        calendars[id] = Calendar(title: title)
        return id
    }

    // MARK: External changes (Calendar app)

    func userDeletesEvent(_ id: String) { events[id] = nil }

    func userDeletesCalendar(titled title: String) {
        for (id, cal) in calendars where cal.title == title {
            calendars[id] = nil
            events = events.filter { $0.value.calendarID != id }
        }
    }

    func eventsInCalendar(titled title: String) -> [CalendarEventDraft] {
        events.values.filter { calendars[$0.calendarID]?.title == title }.map(\.draft)
    }
}

@Suite("Calendar robustness")
@MainActor
struct CalendarServiceTests {
    let start = Date(timeIntervalSince1970: 1_795_000_000)

    func upsert(_ service: CalendarService, _ id: String?, title: String = "🚴 Sweet Spot") async throws -> String {
        try await service.upsert(eventID: id, title: title, start: start, durationSeconds: 3600, notes: "n")
    }

    @Test func createsEventInOwnCalendar() async throws {
        let fake = FakeCalendarBackend()
        let id = try await upsert(CalendarService(backend: fake), nil)
        let events = fake.eventsInCalendar(titled: CalendarService.calendarTitle)
        #expect(events.count == 1)
        #expect(fake.events[id]?.draft.title == "🚴 Sweet Spot")
        #expect(fake.events[id]?.draft.end == start.addingTimeInterval(3600))
        #expect(fake.events[id]?.draft.alarmOffset == TimeInterval(-30 * 60))
    }

    @Test func updatesExistingEventInPlace() async throws {
        let fake = FakeCalendarBackend()
        let service = CalendarService(backend: fake)
        let id = try await upsert(service, nil)
        let again = try await upsert(service, id, title: "🚴 VO₂max")
        #expect(again == id)
        #expect(fake.events.count == 1)
        #expect(fake.events[id]?.draft.title == "🚴 VO₂max")
    }

    @Test func recreatesEventDeletedInCalendarApp() async throws {
        let fake = FakeCalendarBackend()
        let service = CalendarService(backend: fake)
        let id = try await upsert(service, nil)
        fake.userDeletesEvent(id)
        let newID = try await upsert(service, id)
        #expect(newID != id)
        #expect(fake.eventsInCalendar(titled: CalendarService.calendarTitle).count == 1)
    }

    @Test func recreatesDeletedAppCalendar() async throws {
        let fake = FakeCalendarBackend()
        let service = CalendarService(backend: fake)
        let id = try await upsert(service, nil)
        fake.userDeletesCalendar(titled: CalendarService.calendarTitle)
        #expect(fake.writableCalendarID(titled: CalendarService.calendarTitle) == nil)
        let newID = try await upsert(service, id)
        #expect(newID != id)
        #expect(fake.writableCalendarID(titled: CalendarService.calendarTitle) != nil)
        #expect(fake.eventsInCalendar(titled: CalendarService.calendarTitle).count == 1)
    }

    @Test func fallsBackToDefaultCalendarWhenOwnCalendarCannotBeCreated() async throws {
        let fake = FakeCalendarBackend()
        fake.canCreateCalendars = false
        let id = try await upsert(CalendarService(backend: fake), nil)
        #expect(fake.events[id]?.calendarID == "default")
    }

    @Test func failsWithoutAnyWritableCalendar() async {
        let fake = FakeCalendarBackend()
        fake.canCreateCalendars = false
        fake.defaultCalendarID = nil
        await #expect(throws: CalendarError.noCalendar) { _ = try await upsert(CalendarService(backend: fake), nil) }
    }

    @Test func deniedAccessIsReported() async {
        let fake = FakeCalendarBackend()
        fake.accessGranted = false
        await #expect(throws: CalendarError.accessDenied) { _ = try await upsert(CalendarService(backend: fake), nil) }
        #expect(fake.events.isEmpty)
    }

    @Test func removingAnAlreadyDeletedEventIsANoOp() async throws {
        let fake = FakeCalendarBackend()
        let service = CalendarService(backend: fake)
        let id = try await upsert(service, nil)
        fake.userDeletesEvent(id)
        try await service.remove(eventID: id)
        #expect(fake.events.isEmpty)
    }
}
