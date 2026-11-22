import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// „Dein Warum“ (docs/22, B4): Normalisierung, Chips, wörtliche Wiederkehr.
@Suite("Dein Warum · Text")
struct WhyNoteTests {
    private var de: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    @Test func trimsWhitespaceAndNewlines() {
        #expect(WhyNote.normalize("  Im Mai die RTF mit Freunden \n") == "Im Mai die RTF mit Freunden")
        #expect(WhyNote.normalize("Erste Zeile\nZweite Zeile") == "Erste Zeile Zweite Zeile")
        #expect(WhyNote.normalize("Viel    Platz") == "Viel Platz")
    }

    @Test func emptyOrBlankBecomesNil() {
        #expect(WhyNote.normalize("") == nil)
        #expect(WhyNote.normalize("   \n\t ") == nil)
        #expect(WhyNote.normalize(nil) == nil)
    }

    @Test func isCutAtOneHundredFortyCharacters() {
        let long = String(repeating: "a", count: 200)
        #expect(WhyNote.normalize(long)?.count == 140)
        #expect(WhyNote.maxLength == 140)
        let exact = String(repeating: "b", count: 140)
        #expect(WhyNote.normalize(exact) == exact)
    }

    @Test func cutNeverSplitsAnEmojiOrAUmlaut() {
        let text = String(repeating: "ä", count: 139) + "🚴‍♀️🚴‍♀️"
        let cut = WhyNote.normalize(text)
        #expect(cut?.count == 140)
        #expect(cut?.last == "🚴‍♀️")
        #expect(cut?.unicodeScalars.last?.properties.isEmoji != nil)
    }

    @Test func trimmingAfterTheCutLeavesNoTrailingSpace() {
        let text = String(repeating: "a", count: 139) + " bbb"
        #expect(WhyNote.normalize(text) == String(repeating: "a", count: 139))
    }

    @Test func fourSuggestionChipsAndTheGoalChipOpensTheSentence() {
        #expect(WhyNote.suggestions.map(\.label) == ["Im Frühling mit meiner Gruppe mithalten", "Fit durch den Winter, ohne Stress",
                                                      "Ein Ziel: ______", "Rad und Studio kombinieren"])
        #expect(WhyNote.suggestions[0].text == "Im Frühling mit meiner Gruppe mithalten")
        #expect(WhyNote.suggestions[2].text == "Mein Ziel: ")
        #expect(WhyNote.suggestions[2].needsCompletion)
        #expect(WhyNote.suggestions.filter(\.needsCompletion).count == 1)
        #expect(WhyNote.suggestions.allSatisfy { $0.text.count <= WhyNote.maxLength })
    }

    @Test func onlyTheOpenChipNeedsMoreText() {
        // „Mein Ziel: “ allein ist noch kein Satz.
        #expect(WhyNote.isComplete("Mein Ziel: ") == false)
        #expect(WhyNote.isComplete("Mein Ziel: Alpencross") == true)
        #expect(WhyNote.isComplete("Fit durch den Winter, ohne Stress") == true)
        #expect(WhyNote.isComplete(nil) == false)
    }

    @Test func quoteLinesUseTheSentenceWordForWord() {
        let sentence = "Im Mai die RTF mit Freunden."
        #expect(WhyNote.quote(sentence) == "„Im Mai die RTF mit Freunden.“")
        #expect(WhyNote.spokenQuote(sentence) == "Zitat: Im Mai die RTF mit Freunden.")
        #expect(WhyNote.writtenLine(sentence) == "Du hast geschrieben: „Im Mai die RTF mit Freunden.“")
    }

    @Test func momentLineNamesTheMonthItWasWritten() {
        let sentence = "Fit in den Frühling, ohne Stress"
        let november = de.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        #expect(WhyNote.momentLine(sentence, savedOn: november, calendar: de) == "Du hast im November geschrieben: „Fit in den Frühling, ohne Stress“")
        #expect(WhyNote.momentLine(sentence, savedOn: nil, calendar: de) == "Du hast geschrieben: „Fit in den Frühling, ohne Stress“")
        #expect(WhyNote.momentLine(nil, savedOn: november, calendar: de) == nil)
    }

    @Test func promptTextsAreInviting() {
        #expect(WhyNote.question == "Warum fährst du diesen Winter?")
        #expect(WhyNote.privacyNote == "Bleibt auf deinem iPhone. Geht nicht an Claude.")
        #expect(WhyNote.promptTitle == "Magst du deinem Winter einen Satz geben?")
    }
}

// MARK: - Speicher

@MainActor
@Suite("Dein Warum · Speicher", .serialized)
struct WhyNoteStoreTests {
    static var keepAlive: [ModelContainer] = []

    func makeModel(_ suite: String) throws -> (AppModel, UserDefaults) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let defaults = UserDefaults(suiteName: suite)!
        return (AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                         transport: RoutingTransport { _ in (200, Data("{}".utf8)) }), defaults)
    }

    @Test func savingNormalizesAndRemembersTheDay() throws {
        let suite = "why-\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let day = Date(timeIntervalSince1970: 1_793_000_000)
        model.saveWhy("  Im Mai die RTF mit Freunden \n", on: day)
        #expect(model.whyNote == "Im Mai die RTF mit Freunden")
        #expect(model.whyNoteSavedOn == day)
        #expect(defaults.string(forKey: "why.note") == "Im Mai die RTF mit Freunden")
    }

    @Test func editingKeepsTheOriginalDayWhenTheWordsStay() throws {
        let suite = "why-\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Date(timeIntervalSince1970: 1_793_000_000), later = first.addingTimeInterval(9 * 86_400)
        model.saveWhy("Fit durch den Winter", on: first)
        model.saveWhy("Fit durch den Winter ", on: later)
        #expect(model.whyNoteSavedOn == first)
        model.saveWhy("Im Mai die RTF", on: later)
        #expect(model.whyNoteSavedOn == later)
    }

    @Test func clearingRemovesSentenceAndDay() throws {
        let suite = "why-\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        model.saveWhy("Etwas", on: .now)
        model.saveWhy("   ", on: .now)
        #expect(model.whyNote == nil && model.whyNoteSavedOn == nil)
        #expect(defaults.object(forKey: "why.note") == nil && defaults.object(forKey: WhyNote.savedOnKey) == nil)
    }

    @Test func deleteAllDataRemovesTheWhyDayAndTheHighlightMemory() async throws {
        let suite = "why-\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        model.saveWhy("Mein Grund", on: .now)
        defaults.set("2026-12-20", forKey: Comeback.dismissedKey)
        defaults.set(true, forKey: WhyNote.promptDismissedKey)
        await model.deleteAllData()
        for key in ["why.note", WhyNote.savedOnKey, Comeback.dismissedKey, WhyNote.promptDismissedKey] {
            #expect(defaults.object(forKey: key) == nil, "\(key)")
        }
    }
}

// MARK: - Datenschutz-Regression: „Dein Warum“ geht nie an Claude

@MainActor
@Suite("Dein Warum · nie an Claude", .serialized)
struct WhyNotePrivacyTests {
    static var keepAlive: [ModelContainer] = []
    static let secret = "GEHEIMER-WARUM-SATZ-4711 Im Mai die RTF"

    func makeModel() throws -> AppModel {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        AppModel.recoveryWellnessProvider = nil
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "whyp-\(UUID().uuidString)")!,
                             transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
        model.saveWhy(Self.secret, on: .now)
        return model
    }

    @Test func thePlanPromptNeverContainsTheSentence() throws {
        let model = try makeModel()
        #expect(model.whyNote == Self.secret)
        for consent in [false, true] {
            if consent { model.grantClaudeConsent() }
            let ctx = model.planContext(wish: "", startToday: true)
            let user = PlanPrompt.userMessage(ctx)
            #expect(!user.contains("GEHEIMER-WARUM"), "Einwilligung \(consent)")
            #expect(!user.contains("RTF"))
            #expect(!PlanPrompt.system.contains("GEHEIMER-WARUM"))
            #expect(!String(describing: ctx).contains("GEHEIMER-WARUM"))   // jedes Feld des Kontexts
        }
    }

    @Test func theDiagnosticsExportNeverContainsTheSentence() async throws {
        let model = try makeModel()
        let report = await model.diagnosticsReport(since: .now.addingTimeInterval(-86_400)) { _ in [] }
        #expect(!report.contains("GEHEIMER-WARUM"))
        #expect(!report.contains("RTF"))
        #expect(!report.contains("why.note"))
    }

    @Test func noClaudeFacingSourceFileReadsTheSentence() throws {
        // Die Quelltexte, die mit Claude sprechen oder Berichte bauen, dürfen den Satz nie berühren.
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/IndoorCoachKit", isDirectory: true)
        let guarded: Set<String> = ["PlanPrompt.swift", "ClaudeClient.swift", "AppModel+Diagnostics.swift", "AppModel+Consent.swift",
                                    "PilotMetrics.swift", "AppModel+WeeklyReview.swift", "Log.swift", "FeedbackDraft.swift",
                                    "HealthExportService.swift", "AppModel+HealthExport.swift"]
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        let swiftFiles = files.filter { $0.pathExtension == "swift" }
        #expect(swiftFiles.count > 100, "Quelltexte gefunden")
        var seen = 0
        for file in swiftFiles where guarded.contains(file.lastPathComponent) {
            seen += 1
            let text = try String(contentsOf: file, encoding: .utf8)
            for needle in ["whyNote", "why.note", "WhyNote", "saveWhy"] {
                #expect(!text.contains(needle), "\(file.lastPathComponent) berührt \(needle)")
            }
        }
        #expect(seen >= 6)
    }
}
