import EventKit
import Foundation

public enum CalendarError: LocalizedError {
    case accessDenied
    case noCalendar

    public var errorDescription: String? {
        switch self {
        case .accessDenied: "Kein Kalenderzugriff. Bitte in Einstellungen → Datenschutz → Kalender erlauben."
        case .noCalendar: "Es wurde kein beschreibbarer Kalender gefunden."
        }
    }
}

/// Everything written into a calendar event.
struct CalendarEventDraft: Equatable {
    var title: String
    var start: Date
    var end: Date
    var notes: String
    /// Alarm relative to the start, in seconds (negative = before).
    var alarmOffset: TimeInterval
}

/// The few EventKit operations the service needs – a seam so the upsert logic can be tested without EventKit.
@MainActor
protocol CalendarBackend: AnyObject {
    func requestAccess() async throws
    /// Updates the event and returns its identifier, or nil when it no longer exists (deleted in the Calendar app)
    /// or its calendar is gone / read-only.
    func updateEvent(id: String, with draft: CalendarEventDraft) throws -> String?
    func createEvent(in calendarID: String, with draft: CalendarEventDraft) throws -> String
    func removeEvent(id: String) throws
    func writableCalendarID(titled title: String) -> String?
    func createCalendar(titled title: String) throws -> String
    var defaultCalendarID: String? { get }
}

/// Writes planned workouts into the iOS calendar (own calendar "Indoor Training" when possible).
@MainActor
public final class CalendarService {
    public static let calendarTitle = "Indoor Training"
    private let backend: CalendarBackend

    public convenience init() {
        self.init(backend: EventKitCalendarBackend())
    }

    init(backend: CalendarBackend) {
        self.backend = backend
    }

    public func requestAccess() async throws {
        try await backend.requestAccess()
    }

    /// Creates or updates the event and returns its identifier. An event deleted by the user in the Calendar app
    /// is created anew (in the app calendar, which is recreated if it was deleted too).
    public func upsert(eventID: String?, title: String, start: Date, durationSeconds: Int, notes: String) async throws -> String {
        try await backend.requestAccess()
        let draft = CalendarEventDraft(title: title, start: start,
                                       end: start.addingTimeInterval(TimeInterval(max(durationSeconds, 600))),
                                       notes: notes, alarmOffset: -30 * 60)
        if let eventID, let updated = try backend.updateEvent(id: eventID, with: draft) {
            return updated
        }
        return try backend.createEvent(in: trainingCalendarID(), with: draft)
    }

    public func remove(eventID: String) async throws {
        try await backend.requestAccess()
        try backend.removeEvent(id: eventID)
    }

    /// Looked up on every write, so a calendar deleted in the Calendar app is simply recreated.
    private func trainingCalendarID() throws -> String {
        if let existing = backend.writableCalendarID(titled: Self.calendarTitle) { return existing }
        if let created = try? backend.createCalendar(titled: Self.calendarTitle) { return created }
        guard let fallback = backend.defaultCalendarID else { throw CalendarError.noCalendar }
        return fallback
    }
}

/// Production backend on top of `EKEventStore`.
@MainActor
final class EventKitCalendarBackend: CalendarBackend {
    private let store = EKEventStore()

    func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return }
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw CalendarError.accessDenied }
    }

    func updateEvent(id: String, with draft: CalendarEventDraft) throws -> String? {
        guard let event = store.event(withIdentifier: id),
              let calendar = event.calendar, calendar.allowsContentModifications,
              store.calendar(withIdentifier: calendar.calendarIdentifier) != nil else { return nil }
        try save(event, draft)
        return event.eventIdentifier
    }

    func createEvent(in calendarID: String, with draft: CalendarEventDraft) throws -> String {
        guard let calendar = store.calendar(withIdentifier: calendarID) else { throw CalendarError.noCalendar }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        try save(event, draft)
        return event.eventIdentifier
    }

    func removeEvent(id: String) throws {
        guard let event = store.event(withIdentifier: id) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func writableCalendarID(titled title: String) -> String? {
        store.calendars(for: .event).first { $0.title == title && $0.allowsContentModifications }?.calendarIdentifier
    }

    func createCalendar(titled title: String) throws -> String {
        // Prefer the source of the default calendar (usually iCloud) so the calendar syncs to the Mac.
        guard let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local }) else { throw CalendarError.noCalendar }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title
        calendar.source = source
        calendar.cgColor = CGColor(red: 0.98, green: 0.36, blue: 0.13, alpha: 1)
        try store.saveCalendar(calendar, commit: true)
        return calendar.calendarIdentifier
    }

    var defaultCalendarID: String? { store.defaultCalendarForNewEvents?.calendarIdentifier }

    private func save(_ event: EKEvent, _ draft: CalendarEventDraft) throws {
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.notes = draft.notes
        event.alarms = [EKAlarm(relativeOffset: draft.alarmOffset)]
        try store.save(event, span: .thisEvent, commit: true)
    }
}
