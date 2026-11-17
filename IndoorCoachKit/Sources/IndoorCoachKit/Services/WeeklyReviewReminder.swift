import Foundation
import UserNotifications

public enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined, authorized, denied
}

/// The slice of `UNUserNotificationCenter` the reminder needs – a fake stands in for it in unit tests.
public protocol ReminderCenter: Sendable {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async -> Bool
    /// Schedules (or replaces, same `id`) a repeating weekly notification. `weekday` follows Foundation (1 = Sunday).
    func scheduleWeekly(id: String, weekday: Int, hour: Int, minute: Int, title: String, body: String) async throws
    func cancel(id: String)
}

/// Wochenrückblick reminder (K2): Sunday 18:00 local time, opt-in from Profil → Erinnerungen.
public enum WeeklyReviewReminder {
    public static let identifier = "weeklyReview.reminder"
    public static let weekday = 1 // Sunday in Foundation's numbering
    public static let hour = 18
    public static let minute = 0
    public static let title = "Dein Wochenrückblick ist da"
    public static let body = "Schau dir an, was du diese Woche geschafft hast."

    public enum Outcome: Equatable, Sendable {
        case scheduled
        /// Notifications are switched off for the app (or the user declined the prompt).
        case denied
        case failed
    }

    /// Asks for permission when needed, then schedules the weekly notification.
    public static func enable(center: any ReminderCenter) async -> Outcome {
        switch await center.authorization() {
        case .denied: return .denied
        case .notDetermined: guard await center.requestAuthorization() else { return .denied }
        case .authorized: break
        }
        return await schedule(center: center)
    }

    /// Re-registers the notification (replaces the pending one with the same identifier).
    public static func schedule(center: any ReminderCenter) async -> Outcome {
        do {
            try await center.scheduleWeekly(id: identifier, weekday: weekday, hour: hour, minute: minute, title: title, body: body)
            return .scheduled
        } catch {
            Log.error(.app, "Erinnerung nicht geplant: \(type(of: error))")
            return .failed
        }
    }

    public static func disable(center: any ReminderCenter) {
        center.cancel(id: identifier)
    }
}

/// Real implementation. Does nothing outside an app bundle (unit tests, the snapshot tool), where
/// `UNUserNotificationCenter.current()` would trap.
public struct SystemReminderCenter: ReminderCenter {
    public init() {}

    private var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    public func authorization() async -> ReminderAuthorization {
        guard isAvailable else { return .denied }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .authorized
        }
    }

    public func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func scheduleWeekly(id: String, weekday: Int, hour: Int, minute: Int, title: String, body: String) async throws {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                                                    repeats: true)
        // Same identifier replaces the pending request.
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    public func cancel(id: String) {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
