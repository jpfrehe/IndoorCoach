import Foundation
import Testing
@testable import IndoorCoachKit

/// Open items after the MVP (docs review 17.11.2026).
@Suite("Qualität nach MVP")
struct QualityTests {
    @Test func formWordingHasOneSource() {
        for tsb in [-40.0, -20, 0, 10, 30] {
            #expect(WeeklyReview.formWord(tsb) == FitnessFreshness.formLabel(tsb).lowercased())
        }
        #expect(FitnessFreshness.formLabel(30) == "Formverlust")          // the review used to say "sehr ausgeruht"
    }

    @Test func feedbackFallsBackToAPrefilledPublicIssue() throws {
        #expect(AppConfig.feedbackMailURL(email: "", subject: "s", body: "b") == nil)
        let url = AppConfig.feedbackIssueURL(title: "Feedback: ", body: "Text\nApp 0.1 (1)")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "github.com" && components.path == "/jpfrehe/IndoorCoach/issues/new")
        #expect(components.queryItems?.first { $0.name == "body" }?.value == "Text\nApp 0.1 (1)")
    }
}
