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
    // Winter Arc features
    public var restingHeartRate: Int = 50
    public var maxHeartRate: Int? = nil
    /// Start of the personal Winter Arc; nil → 1 November of the current season.
    public var arcStart: Date? = nil
    /// Fitness (CTL) to reach by the goal date; nil → `WinterArc.defaultTarget`.
    public var targetCTL: Double? = nil
    /// Send accepted plans straight to MyWhoosh when connected.
    public var autoSendToMyWhoosh: Bool = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case name, ftp, weightKg, thresholdHeartRate, goal, goalDate, weeklyHours, trainingDays, longestSessionMinutes,
             preferredStartHour, preferredStartMinute, notes, planHorizonDays, model,
             restingHeartRate, maxHeartRate, arcStart, targetCTL, autoSendToMyWhoosh
    }

    /// Tolerant decoding: keys added in later versions fall back to their defaults instead of failing –
    /// otherwise an app update would silently reset the athlete's profile.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AthleteProfile()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        ftp = try c.decodeIfPresent(Int.self, forKey: .ftp) ?? d.ftp
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? d.weightKg
        thresholdHeartRate = try c.decodeIfPresent(Int.self, forKey: .thresholdHeartRate)
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? d.goal
        goalDate = try c.decodeIfPresent(Date.self, forKey: .goalDate)
        weeklyHours = try c.decodeIfPresent(Double.self, forKey: .weeklyHours) ?? d.weeklyHours
        trainingDays = try c.decodeIfPresent([Int].self, forKey: .trainingDays) ?? d.trainingDays
        longestSessionMinutes = try c.decodeIfPresent(Int.self, forKey: .longestSessionMinutes) ?? d.longestSessionMinutes
        preferredStartHour = try c.decodeIfPresent(Int.self, forKey: .preferredStartHour) ?? d.preferredStartHour
        preferredStartMinute = try c.decodeIfPresent(Int.self, forKey: .preferredStartMinute) ?? d.preferredStartMinute
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? d.notes
        planHorizonDays = try c.decodeIfPresent(Int.self, forKey: .planHorizonDays) ?? d.planHorizonDays
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        restingHeartRate = try c.decodeIfPresent(Int.self, forKey: .restingHeartRate) ?? d.restingHeartRate
        maxHeartRate = try c.decodeIfPresent(Int.self, forKey: .maxHeartRate)
        arcStart = try c.decodeIfPresent(Date.self, forKey: .arcStart)
        targetCTL = try c.decodeIfPresent(Double.self, forKey: .targetCTL)
        autoSendToMyWhoosh = try c.decodeIfPresent(Bool.self, forKey: .autoSendToMyWhoosh) ?? d.autoSendToMyWhoosh
    }

    /// Heart-rate anchors for Relative Effort. Max HR falls back to LTHR / 0.9, then 190.
    public var heartRateProfile: RelativeEffort.HeartRateProfile {
        let max = maxHeartRate ?? thresholdHeartRate.map { Int((Double($0) / 0.9).rounded()) } ?? 190
        return RelativeEffort.HeartRateProfile(resting: restingHeartRate, max: max)
    }

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
