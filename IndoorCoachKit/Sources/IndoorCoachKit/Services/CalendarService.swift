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

/// Writes planned workouts into the iOS calendar (own calendar "Indoor Training" when possible).
@MainActor
public final class CalendarService {
    public static let calendarTitle = "Indoor Training"
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return }
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw CalendarError.accessDenied }
    }

    /// Creates or updates the event and returns its identifier.
    public func upsert(eventID: String?, title: String, start: Date, durationSeconds: Int, notes: String) async throws -> String {
        try await requestAccess()
        let event: EKEvent
        if let eventID, let existing = store.event(withIdentifier: eventID) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = try trainingCalendar()
        }
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(max(durationSeconds, 600)))
        event.notes = notes
        event.alarms = [EKAlarm(relativeOffset: -30 * 60)]
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    public func remove(eventID: String) async throws {
        try await requestAccess()
        guard let event = store.event(withIdentifier: eventID) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    /// "Alle Daten löschen": removes the given events (they may live in the default calendar when the own
    /// calendar could not be created) and the app's own calendar "Indoor Training" with everything in it.
    /// Never asks for access: without full access nothing the app wrote is reachable, so there is nothing to do.
    public func removeAppData(eventIDs: [String]) {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        for id in eventIDs {
            if let event = store.event(withIdentifier: id) { try? store.remove(event, span: .thisEvent, commit: false) }
        }
        for calendar in store.calendars(for: .event) where calendar.title == Self.calendarTitle && calendar.allowsContentModifications {
            try? store.removeCalendar(calendar, commit: false)
        }
        try? store.commit()
    }

    private func trainingCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle && $0.allowsContentModifications }) {
            return existing
        }
        // Prefer the source of the default calendar (usually iCloud) so the calendar syncs to the Mac.
        let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
        if let source {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = Self.calendarTitle
            calendar.source = source
            calendar.cgColor = CGColor(red: 0.98, green: 0.36, blue: 0.13, alpha: 1)
            if (try? store.saveCalendar(calendar, commit: true)) != nil { return calendar }
        }
        guard let fallback = store.defaultCalendarForNewEvents else { throw CalendarError.noCalendar }
        return fallback
    }
}
