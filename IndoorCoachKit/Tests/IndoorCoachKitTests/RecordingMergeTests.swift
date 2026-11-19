import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Aufzeichnung ↔ Fahrt (B40)")
struct RecordingMergeTests {
    let t0 = Date(timeIntervalSince1970: 1_794_000_000)

    func ride(id: Int = 1, offset: TimeInterval = 0, duration: Int = 3600, trainer: Bool = true) -> RideSummary {
        RideSummary(id: id, name: "Fahrt", sportType: trainer ? "VirtualRide" : "Ride", startDate: t0.addingTimeInterval(offset),
                    movingTime: duration, distance: 0, trainer: trainer)
    }

    func stored(duration: Int = 3600, start: Date? = nil) -> StoredRecording {
        StoredRecording(id: UUID(), kind: .ride, title: "Sweet Spot", startedAt: start ?? t0,
                        endedAt: (start ?? t0).addingTimeInterval(TimeInterval(duration)),
                        heartRate: Data(repeating: 120, count: duration), gapSeconds: 0, reconnects: 0, plannedWorkoutID: nil)
    }

    // MARK: Zuordnung

    @Test("Fahrt mit Start ±30 min und ähnlicher Dauer passt, die nächste gewinnt")
    func matchesNearest() {
        let rec = stored()
        let far = ride(id: 1, offset: 20 * 60)
        let near = ride(id: 2, offset: 4 * 60, duration: 3500)
        #expect(RecordingMerge.bestMatch(for: rec, in: [far, near])?.id == 2)
    }

    @Test("Zu weit weg, anderer Tag oder völlig andere Dauer passt nicht")
    func rejects() {
        let rec = stored()
        #expect(RecordingMerge.bestMatch(for: rec, in: [ride(offset: 31 * 60)]) == nil)
        #expect(RecordingMerge.bestMatch(for: rec, in: [ride(duration: 900)]) == nil)
        #expect(RecordingMerge.bestMatch(for: rec, in: [ride(offset: 24 * 3600)]) == nil)
        #expect(RecordingMerge.bestMatch(for: rec, in: [ride(trainer: false)]) == nil)
    }

    @Test("Health-Radfahrt passt (auch ohne Indoor-Kennzeichen), Health-Fremdsport und Outdoor-Fahrt ohne Health nicht")
    func healthRides() {
        let rec = stored()
        var health = ride(id: 5, trainer: false)
        health.healthUUID = UUID().uuidString
        #expect(RecordingMerge.bestMatch(for: rec, in: [health])?.id == 5)
        var run = ride(id: 6, trainer: false)
        run.healthUUID = UUID().uuidString
        run.foreignSport = "running"
        #expect(RecordingMerge.bestMatch(for: rec, in: [run]) == nil)
        #expect(RecordingMerge.bestMatch(for: rec, in: [ride(id: 7, trainer: false)]) == nil)
    }

    // MARK: Ausrichtung

    @Test("Grundversatz: Fahrt startet später → führende Pulssekunden fallen weg")
    func baseShift() {
        let rec = stored(start: t0)
        #expect(RecordingMerge.baseShift(recording: rec, rideStart: t0.addingTimeInterval(45)) == 45)
        #expect(RecordingMerge.baseShift(recording: rec, rideStart: t0.addingTimeInterval(-20)) == -20)
    }

    @Test("align verschiebt, füllt Lücken mit 0 und kappt auf die Länge")
    func align() {
        let hr: [UInt8] = [10, 11, 12, 13, 14]
        #expect(RecordingMerge.align(hr, shift: 2, length: 5) == [12, 13, 14, 0, 0])
        #expect(RecordingMerge.align(hr, shift: -2, length: 6) == [0, 0, 10, 11, 12, 13])
        #expect(RecordingMerge.align(hr, shift: 0, length: 3) == [10, 11, 12])
    }

    /// Puls 100, steigt ab Sekunde `riseAt` über 60 s auf 150.
    func risingPulse(riseAt: Int, count: Int = 1200) -> [UInt8] {
        (0..<count).map { i in
            if i < riseAt { return 100 }
            let p = min(1.0, Double(i - riseAt) / 60)
            return UInt8(100 + 50 * p)
        }
    }

    @Test("Feinkorrektur findet den Pulsanstieg am Ende des Aufwärmens")
    func fineShift() {
        // erwartet bei 600 s, Puls steigt erst bei 640 s
        let shift = RecordingMerge.fineShift(hr: risingPulse(riseAt: 640), expectedRiseAt: 600)
        #expect((15...45).contains(shift))
        let near = RecordingMerge.fineShift(hr: risingPulse(riseAt: 615), expectedRiseAt: 600)
        #expect(abs(near) <= 15)
    }

    @Test("Ohne klaren Anstieg bleibt die Feinkorrektur 0")
    func fineShiftFlat() {
        #expect(RecordingMerge.fineShift(hr: [UInt8](repeating: 120, count: 1200), expectedRiseAt: 600) == 0)
        #expect(RecordingMerge.fineShift(hr: [], expectedRiseAt: 600) == 0)
    }

    @Test("Feinkorrektur ist auf ±90 s begrenzt")
    func fineShiftClamped() {
        let shift = RecordingMerge.fineShift(hr: risingPulse(riseAt: 1000, count: 1500), expectedRiseAt: 600)
        #expect(abs(shift) <= 90)
    }

    // MARK: Zusammenführen

    @Test("Echte Leistung bleibt, Puls füllt nur Lücken")
    func mergeKeepsPower() {
        let existing = RideSeconds(power: [200, 210, 220, 230], heartRate: [140, 0, 142, 0])
        let merged = RecordingMerge.merge(existing: existing, heartRate: [90, 91, 92, 93])
        #expect(merged.power == [200, 210, 220, 230])
        #expect(merged.heartRate == [140, 91, 142, 93])
    }

    @Test("Ohne Bestand: Leistung 0, Puls vom iPhone")
    func mergeFresh() {
        let merged = RecordingMerge.merge(existing: nil, heartRate: [90, 91, 92])
        #expect(merged.power == [0, 0, 0])
        #expect(merged.heartRate == [90, 91, 92])
        #expect(!RecordingMerge.hasPower(merged))
    }

    @Test("Bestand ohne Leistung wird ersetzt, der iPhone-Puls bleibt erhalten")
    func upgrade() {
        let iphone = RideSeconds(power: [0, 0, 0], heartRate: [90, 91, 92])
        let fit = RideSeconds(power: [200, 200, 200], heartRate: nil)
        let up = RecordingMerge.upgrade(existing: iphone, incoming: fit)
        #expect(up?.power == [200, 200, 200])
        #expect(up?.heartRate == [90, 91, 92])
        // Echte Leistung im Bestand wird nie ersetzt.
        #expect(RecordingMerge.upgrade(existing: fit, incoming: RideSeconds(power: [1, 1, 1], heartRate: nil)) == nil)
        // Kein Bestand → Eingang.
        #expect(RecordingMerge.upgrade(existing: nil, incoming: fit) == fit)
    }

    // MARK: ERG-Annahme

    @Test("ERG-Annahme nur für stationäre Blöcke ≥ 2 min, Rampen und kurze Intervalle nicht auswertbar")
    func ergBlocks() {
        let def = WorkoutDefinition(title: "T", type: .mixed, summary: "", segments: [
            .warmup(10, from: 0.5, to: 0.7),
            .steady(6, at: 0.55, text: "Aufwärm-Check"),
            .intervals(3, on: 60, at: 1.1, off: 60, at: 0.5),
            .steady(20, at: 0.9),
            .ramp(5, from: 0.6, to: 0.9),
            .steady(1, at: 0.6)
        ])
        let a = ERGAssumption.analyze(definition: def, ftp: 250)
        #expect(a.blocks.map(\.start) == [600, 1320])
        #expect(a.blocks.map(\.watts) == [138, 225])   // 0,55·250 = 137,5 → 138
        #expect(a.blocks.map(\.duration) == [360, 1200])
        #expect(a.unassessableSeconds == 600 + 360 + 300 + 60)
    }

    @Test("Mittlerer Puls je ERG-Block")
    func ergPulse() {
        let blocks = [ERGAssumption.Block(start: 10, duration: 100, watts: 150)]
        var hr = [UInt8](repeating: 100, count: 200)
        for i in 70..<110 { hr[i] = 140 }
        let means = ERGAssumption.meanPulse(hr: hr, blocks: blocks)
        #expect(means.count == 1)
        #expect(abs((means[0] ?? 0) - (100 * 60 + 140 * 40) / 100.0) < 0.1)
    }
}
