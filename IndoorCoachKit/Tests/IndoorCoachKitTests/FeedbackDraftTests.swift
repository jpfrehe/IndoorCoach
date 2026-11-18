import Foundation
import Testing
@testable import IndoorCoachKit

private let info = FeedbackDraft.AppInfo(version: "0.1 (1)", os: "iOS 18.2.1", device: "iPhone17,3")

private func queryItems(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
}

@Suite struct FeedbackDraftTests {
    @Test func templatesAndPrefixesPerKind() {
        #expect(FeedbackKind.bug.templateFile == "bug_report.yml")
        #expect(FeedbackKind.wish.templateFile == "feature_request.yml")
        #expect(FeedbackKind.praise.templateFile == "feedback.yml")
        #expect(FeedbackKind.bug.titlePrefix == "[Fehler] ")
        #expect(FeedbackKind.wish.bodyFieldID == "wunsch")
        #expect(FeedbackKind.bug.bodyFieldID == "beschreibung")
        #expect(FeedbackKind.praise.bodyFieldID == "feedback")
        #expect(Set(FeedbackKind.allCases.map(\.appInfoFieldID)) == ["app-info"])
    }

    @Test func urlCarriesTemplateTitleAndFields() {
        let draft = FeedbackDraft(kind: .wish, title: "Dunkler Modus für Karten", body: "Ich wünsche mir X & Y = Z.\nZeile 2")
        let url = draft.issueURL(appInfo: info, includeAppInfo: true)
        #expect(url.absoluteString.hasPrefix("https://github.com/jpfrehe/IndoorCoach/issues/new?"))
        let q = queryItems(url)
        #expect(q["template"] == "feature_request.yml")
        #expect(q["title"] == "[Wunsch] Dunkler Modus für Karten")
        #expect(q["wunsch"] == "Ich wünsche mir X & Y = Z.\nZeile 2")
        #expect(q["app-info"] == "App 0.1 (1) · iOS 18.2.1 · iPhone17,3")
        #expect(!url.absoluteString.contains(" "))
        #expect(url.absoluteString.contains("%26"))
    }

    @Test func appInfoOmittedWhenOff() {
        let draft = FeedbackDraft(kind: .bug, title: "Absturz beim Start", body: "Die App stürzt ab, sobald ich sie öffne.")
        let q = queryItems(draft.issueURL(appInfo: info, includeAppInfo: false))
        #expect(q["app-info"] == nil)
        #expect(q["beschreibung"] != nil)
    }

    @Test func redactsEmailsAndTokens() {
        let draft = FeedbackDraft(kind: .bug, title: "Fehler bei max@example.com",
                                  body: "Mein Key sk-ant-api03-ABCdef123_xyz und Mail erika@mustermann.de klappen nicht. Bearer abc.def.ghi")
        let q = queryItems(draft.issueURL(appInfo: info, includeAppInfo: true))
        let all = (q["title"] ?? "") + (q["beschreibung"] ?? "")
        #expect(!all.contains("@example.com"))
        #expect(!all.contains("mustermann"))
        #expect(!all.contains("ABCdef123"))
        #expect(!all.contains("abc.def.ghi"))
        #expect(all.contains("‹E-Mail›"))
        #expect(draft.plainText(appInfo: info, includeAppInfo: true).contains("‹E-Mail›"))
    }

    @Test func longBodyIsTruncatedBelowLimit() {
        let draft = FeedbackDraft(kind: .bug, title: "Sehr langer Text",
                                  body: String(repeating: "Übung äöü & Zeile\n", count: 2000))
        let url = draft.issueURL(appInfo: info, includeAppInfo: true)
        #expect(url.absoluteString.count < FeedbackDraft.maxURLLength)
        #expect(FeedbackDraft.maxURLLength == 8000)
        let body = queryItems(url)["beschreibung"] ?? ""
        #expect(body.hasSuffix("…(gekürzt)"))
        #expect(body.count > 200)
    }

    @Test func shortBodyIsNotTruncated() {
        let draft = FeedbackDraft(kind: .praise, title: "Tolle App", body: "Macht richtig Spaß, danke!")
        let body = queryItems(draft.issueURL(appInfo: info, includeAppInfo: true))["feedback"] ?? ""
        #expect(body == "Macht richtig Spaß, danke!")
    }

    @Test func validation() {
        #expect(!FeedbackDraft(kind: .bug, title: "abcd", body: "zehn Zeichen!").isValid)
        #expect(!FeedbackDraft(kind: .bug, title: "  abcd  ", body: "zehn Zeichen!").isValid)
        #expect(!FeedbackDraft(kind: .bug, title: "Titel ok", body: "kurz").isValid)
        #expect(!FeedbackDraft(kind: .bug, title: "Titel ok", body: "   kurz      ").isValid)
        #expect(FeedbackDraft(kind: .bug, title: "Titel", body: "Zehn Zeich").isValid)
    }

    @Test func plainTextExport() {
        let draft = FeedbackDraft(kind: .wish, title: "Mehr Farben", body: "Bitte mehr Farben.")
        let on = draft.plainText(appInfo: info, includeAppInfo: true)
        #expect(on.hasPrefix("[Wunsch] Mehr Farben\n\nBitte mehr Farben."))
        #expect(on.hasSuffix("App 0.1 (1) · iOS 18.2.1 · iPhone17,3"))
        let off = draft.plainText(appInfo: info, includeAppInfo: false)
        #expect(!off.contains("iPhone17,3"))
    }

    @Test func existingWishesLink() {
        let s = FeedbackDraft.existingWishesURL.absoluteString
        #expect(s.hasPrefix("https://github.com/jpfrehe/IndoorCoach/issues?"))
        #expect(s.contains("enhancement"))
    }

    /// Every field id the app sends must exist in the matching issue-form template, and each template's labels match.
    @Test func templatesContainAppFieldIDs() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent(".github/ISSUE_TEMPLATE")
        let expectedLabel: [FeedbackKind: String] = [.bug: "bug", .wish: "enhancement", .praise: "feedback"]
        for kind in FeedbackKind.allCases {
            let text = try String(contentsOf: dir.appendingPathComponent(kind.templateFile), encoding: .utf8)
            let ids = text.split(separator: "\n").compactMap { line -> String? in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("id:") else { return nil }
                return t.dropFirst(3).trimmingCharacters(in: .whitespaces)
            }
            #expect(ids.contains(kind.bodyFieldID), "\(kind.templateFile) fehlt id \(kind.bodyFieldID)")
            #expect(ids.contains(kind.appInfoFieldID), "\(kind.templateFile) fehlt id \(kind.appInfoFieldID)")
            #expect(text.contains("labels: [\(expectedLabel[kind]!)]"))
        }
        let config = try String(contentsOf: dir.appendingPathComponent("config.yml"), encoding: .utf8)
        #expect(config.contains("blank_issues_enabled: true"))
    }
}
