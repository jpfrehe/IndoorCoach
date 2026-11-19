import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Aufzeichnung verdrahten (W3-A)")
@MainActor
struct StrengthRecordingFlowTests {
    static var keepAlive: [ModelContainer] = []
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeModel() throws -> AppModel {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let defaults = UserDefaults(suiteName: "w3a-\(UUID().uuidString)")!
        return AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                        transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
    }

    func result(kind: RecordingKind, title: String = "Kraft", seconds: Int = 600, hr: UInt8 = 120) -> RecordingResult {
        RecordingResult(kind: kind, title: title, startedAt: now.addingTimeInterval(-Double(seconds)), endedAt: now,
                        seconds: RideSeconds(power: Array(repeating: 0, count: seconds),
                                             heartRate: Array(repeating: hr, count: seconds)))
    }

    @Test("Übergabe je Art: Rad geht in den Merge-Weg, Kraft und Andere in das Abschluss-Sheet")
    func handOffByKind() throws {
        let model = try makeModel()
        #expect(model.handOff(result(kind: .ride, title: "Fahrt")) == .merged(.pending))
        #expect(model.pendingRecordings.count == 1)
        #expect(model.handOff(result(kind: .strength)) == .finishSheet)
        #expect(model.handOff(result(kind: .other, title: "Laufen")) == .finishSheet)
        #expect(model.pendingRecordings.count == 1)   // Kraft/Andere landen nicht im Fahrten-Speicher
        #expect(model.storedStrengthRows().isEmpty)   // und sind erst nach dem Sheet gespeichert
    }

    @Test("Andere Einheit mit Gurt: Sportart und Pulsspur werden gespeichert")
    func otherSportRecorded() throws {
        let model = try makeModel()
        let draft = StrengthDraft.otherSport("Laufen", exertion: 6, legShare: .heavy, note: "")
        let row = try #require(model.saveStrength(from: result(kind: .other, title: "Laufen"), draft: draft))
        #expect(row.sportName == "Laufen")
        #expect(row.isOtherSport)
        #expect(row.source == .recorded)
        #expect(row.heartRateSeries?.count == 600)
        #expect(row.legShareRaw == nil)            // Laufen: keine Beine-Frage
        #expect(row.feedsMuscleTrack == false)
        #expect(model.strengthSessions().isEmpty)
    }

    @Test("Muskuläre Sportart behält die Beine-Angabe")
    func muscularKeepsLegs() {
        let draft = StrengthDraft.otherSport("Bouldern", exertion: 7, legShare: .light, note: " x ")
        #expect(draft.legShare == .light)
        #expect(draft.sportName == "Bouldern")
        #expect(draft.note == "x")
    }

    @Test("Kraft: Zeit in Pulszonen ohne Watt-Zonen")
    func heartZonesWithoutPower() throws {
        let model = try makeModel()
        let draft = StrengthDraft(exercises: [PerformedExercise(exerciseID: "bench_press")], exertion: 6)
        let row = try #require(model.saveStrength(from: result(kind: .strength, hr: 130), draft: draft))
        let zones = try #require(model.heartZoneTime(for: row))
        #expect(zones.hasPower == false)
        #expect(zones.heartTotal == 600)
    }

    @Test("Ohne Puls keine Zonen")
    func noZonesWithoutPulse() throws {
        let model = try makeModel()
        let row = try #require(model.saveStrengthManual(start: now, durationMinutes: 30, exertion: 5, legShare: nil, exercises: []))
        #expect(model.heartZoneTime(for: row) == nil)
    }
}
