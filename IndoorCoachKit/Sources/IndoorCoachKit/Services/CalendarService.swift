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
        let granted: Bool
        do { granted = try await store.requestFullAccessToEvents() } catch {
            Log.error(.calendar, "Zugriffsanfrage fehlgeschlagen: \(error.localizedDescription)")
            throw error
        }
        guard granted else { Log.error(.calendar, "Kein Kalenderzugriff (Status \(status.rawValue))"); throw CalendarError.accessDenied }
    }

    /// Creates or updates the event and returns its identifier.
    public func upsert(eventID: String?, title: String, start: Date, durationSeconds: Int, notes: String) async throws -> String {
        try await requestAccess()
        let event: EKEvent
        let isUpdate: Bool
        if let eventID, let existing = store.event(withIdentifier: eventID) {
            event = existing
            isUpdate = true
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = try trainingCalendar()
            isUpdate = false
        }
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(max(durationSeconds, 600)))
        event.notes = notes
        event.alarms = [EKAlarm(relativeOffset: -30 * 60)]
        do { try store.save(event, span: .thisEvent, commit: true) } catch {
            Log.error(.calendar, "Termin speichern fehlgeschlagen: \(error.localizedDescription)")
            throw error
        }
        Log.notice(.calendar, isUpdate ? "Termin aktualisiert" : (eventID == nil ? "Termin angelegt" : "Termin neu angelegt (alter Eintrag fehlte)"))
        return event.eventIdentifier
    }

    public func remove(eventID: String) async throws {
        try await requestAccess()
        guard let event = store.event(withIdentifier: eventID) else { Log.notice(.calendar, "Termin zum Löschen nicht gefunden"); return }
        do { try store.remove(event, span: .thisEvent, commit: true) } catch {
            Log.error(.calendar, "Termin löschen fehlgeschlagen: \(error.localizedDescription)")
            throw error
        }
        Log.notice(.calendar, "Termin gelöscht")
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
            do {
                try store.saveCalendar(calendar, commit: true)
                Log.notice(.calendar, "Kalender „\(Self.calendarTitle)“ angelegt (Quelle \(source.sourceType.rawValue))")
                return calendar
            } catch {
                Log.error(.calendar, "Eigener Kalender nicht anlegbar: \(error.localizedDescription) – nutze Standardkalender")
            }
        }
        guard let fallback = store.defaultCalendarForNewEvents else { Log.error(.calendar, "Kein beschreibbarer Kalender"); throw CalendarError.noCalendar }
        return fallback
    }
}
