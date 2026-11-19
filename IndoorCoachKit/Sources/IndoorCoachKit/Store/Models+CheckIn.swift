import Foundation
import SwiftData

/// One check-in per day (`day` = start of day). Skipped check-ins are stored too, so the card does not come back.
@Model
public final class StoredCheckIn {
    @Attribute(.unique) public var day: Date
    public var createdAt: Date
    public var skipped: Bool
    public var legsRaw: String
    public var sleepRaw: String
    public var moodRaw: String
    /// Comma-separated `CheckIn.Tag` raw values.
    public var tagsRaw: String
    /// Comma-separated `CheckIn.Action.raw` values offered at that time.
    public var offeredRaw: String
    public var chosenRaw: String?

    public init(day: Date, answers: CheckIn.Answers, offered: [CheckIn.Action], skipped: Bool = false, createdAt: Date = .now) {
        self.day = day
        self.createdAt = createdAt
        self.skipped = skipped
        legsRaw = answers.legs.rawValue
        sleepRaw = answers.sleep.rawValue
        moodRaw = answers.mood.rawValue
        tagsRaw = answers.tags.map(\.rawValue).sorted().joined(separator: ",")
        offeredRaw = offered.map(\.raw).joined(separator: ",")
    }

    public var answers: CheckIn.Answers {
        CheckIn.Answers(legs: CheckIn.Level(rawValue: legsRaw) ?? .ok, sleep: CheckIn.Level(rawValue: sleepRaw) ?? .ok,
                        mood: CheckIn.Level(rawValue: moodRaw) ?? .ok,
                        tags: Set(tagsRaw.split(separator: ",").compactMap { CheckIn.Tag(rawValue: String($0)) }))
    }

    public var offered: [CheckIn.Action] { offeredRaw.split(separator: ",").compactMap { CheckIn.Action(raw: String($0)) } }
    public var chosen: CheckIn.Action? { chosenRaw.flatMap(CheckIn.Action.init(raw:)) }
}
