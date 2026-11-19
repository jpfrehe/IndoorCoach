import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// PO-Entscheidung: Ohne Claude-Einwilligung enthält der Plan-Kontext nichts aus Apple Health, keine Kraft-/Fremdsport-
/// Abschnitte und keine Check-ins; Fremdsport steht nie doppelt unter den letzten Einheiten.
@Suite("Plan-Kontext und Einwilligung", .serialized)
@MainActor
struct PlanContextConsentTests {
    static var keepAlive: [ModelContainer] = []
    let cal = Calendar.current
    var noon: Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.startOfDay(for: .now))! }

    func makeModel() throws -> AppModel {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        AppModel.recoveryWellnessProvider = nil
        return AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                        defaults: UserDefaults(suiteName: "pcc-\(UUID().uuidString)")!,
                        transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
    }

    /// Eine MyWhoosh-Fahrt, eine Health-Radfahrt, ein Health-Lauf, eine Fahrt mit Health-Puls, dazu Kraft und ein Check-in.
    func seed(_ model: AppModel) {
        let now = noon
        func at(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        let whoosh = RideSummary(id: -1, name: "MyWhoosh", sportType: "VirtualRide", startDate: at(30), movingTime: 3600, distance: 30_000,
                                 averageWatts: 200, weightedAverageWatts: 210, trainer: true)
        var health = RideSummary(id: -2, name: "Radfahren (Apple Watch)", sportType: "Ride", startDate: at(52), movingTime: 3600,
                                 distance: 0, averageHeartrate: 140, maxHeartrate: 160)
        health.healthUUID = UUID().uuidString
        var run = RideSummary(id: -3, name: "Laufen (Apple Watch)", sportType: "Run", startDate: at(76), movingTime: 2400,
                              distance: 6000, averageHeartrate: 150, maxHeartrate: 170)
        run.healthUUID = UUID().uuidString
        run.foreignSport = "running"
        run.estimatedTSS = 40
        let merged = RideSummary(id: -4, name: "Fahrt", sportType: "VirtualRide", startDate: at(100), movingTime: 3000, distance: 20_000,
                                 averageWatts: 180, weightedAverageWatts: 190, averageHeartrate: 148, maxHeartrate: 171, trainer: true)
        for ride in [whoosh, health, run] { model.context.insert(StoredRide(ride)) }
        let mergedRow = StoredRide(merged)
        mergedRow.stravaID = -5
        mergedRow.startDate = at(120)
        mergedRow.healthNote = "Puls aus Health ergänzt"
        mergedRow.mergedHealthUUID = UUID().uuidString
        model.context.insert(mergedRow)
        model.context.insert(StoredCheckIn(day: cal.startOfDay(for: now), answers: CheckIn.Answers(legs: .bad), offered: []))
        try? model.context.save()
        model.saveStrengthManual(start: at(20), durationMinutes: 60, exertion: 7, legShare: .heavy, exercises: [])
    }

    @Test func ohneEinwilligungNichtsAusHealthKeinKraftKeinCheckIn() throws {
        let model = try makeModel()
        seed(model)
        #expect(model.claudeConsent == nil)
        let ctx = model.planContext(wish: "", startToday: true, now: noon)
        #expect(ctx.recentRides.map(\.id).sorted() == [-5, -1])
        #expect(ctx.recentRides.allSatisfy { $0.healthUUID == nil && !$0.isForeignSport })
        // Puls einer mit Health zusammengeführten Fahrt kann aus Health stammen und bleibt draußen.
        #expect(ctx.recentRides.first { $0.id == -5 }?.averageHeartrate == nil)
        #expect(ctx.strength == nil)
        #expect(ctx.otherSports.isEmpty)
        #expect(ctx.recovery == nil)
        let text = PlanPrompt.userMessage(ctx)
        #expect(!text.contains("Kraft & andere Sportarten"))
        #expect(!text.contains("Laufen"))
        #expect(!text.contains("Apple Watch"))
        // Auch Wochenbelastung und Last speisen sich nur aus Rad-Daten (zwei Fahrten, keine Health-Fahrt, kein Lauf).
        #expect(ctx.weeks.reduce(0) { $0 + $1.rides } == 2)
    }

    @Test func mitEinwilligungAllesAggregiertFremdsportNichtDoppelt() throws {
        let model = try makeModel()
        seed(model)
        model.grantClaudeConsent(now: noon)
        let ctx = model.planContext(wish: "", startToday: true, now: noon)
        #expect(ctx.recentRides.map(\.id).sorted() == [-5, -2, -1])   // Health-Radfahrt ja, Lauf nur als Fremdsport
        #expect(ctx.strength?.sessions.count == 1)
        #expect(ctx.otherSports.count == 1)
        #expect(ctx.recovery?.checkIns.legsHeavy == 1)
    }

    @Test func fremdsportStehtNichtDoppeltInDenLetztenEinheiten() throws {
        let model = try makeModel()
        seed(model)
        model.grantClaudeConsent(now: noon)
        let ctx = model.planContext(wish: "", startToday: true, now: noon)
        #expect(ctx.recentRides.contains { $0.isForeignSport } == false)
        let text = PlanPrompt.userMessage(ctx)
        #expect(text.components(separatedBy: "Laufen").count - 1 == 1)   // nur unter „Andere Sportarten“
    }

    @Test func alteEinwilligungFragtNeuUndVorschauNenntKraftUndSport() throws {
        let model = try makeModel()
        seed(model)
        let old = ClaudeConsent(grantedAt: noon, version: ClaudeConsent.currentVersion - 1)
        model.defaults.set(try JSONEncoder().encode(old), forKey: AppModel.ConsentKeys.consent)
        model.defaults.set(true, forKey: AppModel.ConsentKeys.asked)
        #expect(model.needsClaudeConsentPrompt(now: noon))
        let preview = model.recoveryPreviewText(now: noon)
        #expect(preview.contains("Kraft & andere Sportarten"))
        #expect(preview.contains("Laufen"))
    }
}
