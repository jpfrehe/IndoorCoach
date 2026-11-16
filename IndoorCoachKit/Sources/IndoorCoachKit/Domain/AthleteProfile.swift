import Foundation

/// Settings and goals of the (single) athlete. Stored as JSON in UserDefaults – contains no secrets.
public struct AthleteProfile: Codable, Equatable, Sendable {
    public var name: String = ""
    public var ftp: Int = 250
    public var weightKg: Double = 75
    public var thresholdHeartRate: Int? = nil
    public var goal: String = "FTP steigern und im Frühjahr fit für lange Ausfahrten sein"
    public var goalDate: Date? = nil
    public var weeklyHours: Double = 5
    /// ISO weekdays (1 = Monday … 7 = Sunday) available for indoor sessions.
    public var trainingDays: [Int] = [2, 4, 6, 7]
    public var longestSessionMinutes: Int = 90
    public var preferredStartHour: Int = 18
    public var preferredStartMinute: Int = 30
    public var notes: String = ""
    public var planHorizonDays: Int = 7
    public var model: String = ClaudeModel.default.rawValue

    public init() {}

    public static let weekdayNames = [1: "Mo", 2: "Di", 3: "Mi", 4: "Do", 5: "Fr", 6: "Sa", 7: "So"]
    public static let weekdayLongNames = [1: "Montag", 2: "Dienstag", 3: "Mittwoch", 4: "Donnerstag",
                                          5: "Freitag", 6: "Samstag", 7: "Sonntag"]

    /// Converts a Foundation weekday (1 = Sunday) to ISO (1 = Monday).
    public static func isoWeekday(of date: Date, calendar: Calendar = .current) -> Int {
        let w = calendar.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }

    public var wattsPerKg: Double { weightKg > 0 ? Double(ftp) / weightKg : 0 }
}

public enum ClaudeModel: String, CaseIterable, Sendable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"

    public static let `default` = ClaudeModel.opus
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .opus: "Claude Opus 5.5 (beste Qualität)"
        case .sonnet: "Claude Sonnet 5.5 (günstiger, schneller)"
        }
    }
}
