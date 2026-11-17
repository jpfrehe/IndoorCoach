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
    /// Schedules (or replaces, same `id`) a one-shot notification at `date`.
    func scheduleOnce(id: String, at date: Date, title: String, body: String) async throws
    /// Removes every pending notification whose identifier starts with `prefix`.
    func cancelAll(withPrefix prefix: String) async
}

extension ReminderCenter {
    public func scheduleOnce(id: String, at date: Date, title: String, body: String) async throws {}
    public func cancelAll(withPrefix prefix: String) async {}
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

/// G7: local notification 30 minutes before each planned workout (next 14 days, at most 20 pending).
public enum WorkoutReminder {
    public static let idPrefix = "workout."
    public static let leadTime: TimeInterval = 30 * 60
    public static let horizon: TimeInterval = 14 * 24 * 3600
    public static let maxPending = 20
    public static let title = "Gleich geht's los"

    public struct Item: Equatable, Sendable {
        public var id: UUID
        public var title: String
        public var start: Date
        public var duration: Int
        public var tss: Double
        public var status: WorkoutStatus
    }

    public struct Request: Equatable, Sendable {
        public var id: String
        public var fireDate: Date
        public var body: String
    }

    /// Pure planning: open workouts whose reminder time lies ahead and within 14 days, earliest 20.
    public static func plan(items: [Item], now: Date) -> [Request] {
        items.filter { $0.status == .planned }
            .map { Request(id: idPrefix + $0.id.uuidString, fireDate: $0.start.addingTimeInterval(-leadTime),
                           body: "Gleich: \($0.title) · \(Formatters.duration($0.duration)) · TSS \(Int($0.tss.rounded()))") }
            .filter { $0.fireDate > now && $0.fireDate <= now.addingTimeInterval(horizon) }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maxPending).map { $0 }
    }

    /// Replaces all pending workout reminders. Never prompts: without permission nothing is scheduled.
    public static func reschedule(items: [Item], now: Date = .now, center: any ReminderCenter) async {
        await center.cancelAll(withPrefix: idPrefix)
        guard await center.authorization() == .authorized else { return }
        for r in plan(items: items, now: now) {
            do { try await center.scheduleOnce(id: r.id, at: r.fireDate, title: title, body: r.body) } catch {
                Log.error(.app, "Einheiten-Erinnerung nicht geplant: \(type(of: error))")
            }
        }
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

    public func scheduleOnce(id: String, at date: Date, title: String, body: String) async throws {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    public func cancelAll(withPrefix prefix: String) async {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
