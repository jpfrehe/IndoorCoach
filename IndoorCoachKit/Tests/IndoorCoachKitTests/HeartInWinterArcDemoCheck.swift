import Foundation
import Testing
@testable import IndoorCoachKit

@MainActor
enum HeartInWinterArcDemoCheck {
    static func run() async throws {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "heart-\(UUID().uuidString)")!)
        model.bootstrap()
        #expect(model.isDemoMode)
        let range = WinterArc.defaultSeason(containing: .now)
        let status = WinterArc.status(start: range.start, goal: range.goal, today: .now, startCTL: 24, currentCTL: 34,
                                      bestCTLSinceStart: 35, targetCTL: 44)
        let heart = await model.heartInWinterArc(rides: model.allRides(), status: status)
        #expect(!heart.isEmpty)
        #expect(heart.resting?.sourceText == "Apple Health · Demo")
        #expect((heart.resting?.change ?? 0) < -2)
        #expect(heart.sentence != nil)
        #expect(heart.strengthTotal > 5)

        // Die Demo-Kurve muss an jedem Tag des Jahres klar fallen, nicht nur heute (am 21.11.2026 lag die
        // Monatsdifferenz durch Rauschen und Rundung bei genau −2).
        for offset in stride(from: 0, to: 365, by: 3) {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
            let card = await model.heartInWinterArc(rides: [], status: status, now: day)
            #expect((card.resting?.change ?? 0) < -2, "Demo-Ruhepuls fällt nicht klar ab: \(day)")
        }
    }
}
