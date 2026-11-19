import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Gerätetest-Protokoll Brustgurt")
struct StrapProtocolRecorderTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func recorder() -> StrapProtocolRecorder {
        var r = StrapProtocolRecorder(start: t0, battery: 87, appActive: true, modelName: "Polar H10")
        r.packet(at: t0.addingTimeInterval(1), hasRR: true)
        r.packet(at: t0.addingTimeInterval(2), hasRR: false)
        return r
    }

    @Test("Zählt Pakete und RR-Pakete")
    func counts() {
        let r = recorder()
        #expect(r.packetCount == 2)
        #expect(r.rrPacketCount == 1)
    }

    @Test("Lücke > 2 s wird mit Zeitpunkt und Dauer erfasst, genau 2 s nicht")
    func gaps() {
        var r = recorder()
        r.packet(at: t0.addingTimeInterval(4), hasRR: true)      // 2 s: no gap
        r.setAppActive(false, at: t0.addingTimeInterval(5))
        r.packet(at: t0.addingTimeInterval(12), hasRR: true)     // 8 s gap, ended in background
        #expect(r.gaps.count == 1)
        #expect(r.gaps[0].duration == 8)
        #expect(r.gaps[0].offset == 4)
        #expect(r.gaps[0].inBackground)
    }

    @Test("Reconnects und Akku Start/Ende")
    func reconnectBattery() {
        var r = recorder()
        r.reconnect()
        r.reconnect()
        r.setBattery(85)
        #expect(r.reconnects == 2)
        #expect(r.batteryStart == 87)
        #expect(r.batteryEnd == 85)
    }

    @Test("Zeit in Vordergrund und Hintergrund")
    func appStateTime() {
        var r = recorder()
        r.setAppActive(false, at: t0.addingTimeInterval(10))
        let text = r.reportLines(end: t0.addingTimeInterval(70)).joined(separator: "\n")
        #expect(text.contains("Vordergrund 10 s"))
        #expect(text.contains("Hintergrund 60 s"))
    }

    @Test("Bericht enthält Zähler, aber keine Pulswerte oder Rohnamen")
    func redacted() {
        var r = recorder()
        r.packet(at: t0.addingTimeInterval(9), hasRR: true)
        let lines = r.reportLines(end: t0.addingTimeInterval(60))
        let text = lines.joined(separator: "\n")
        #expect(text.contains("Polar H10"))
        #expect(text.contains("Pakete: 3"))
        #expect(text.contains("Lücken > 2 s: 1"))
        #expect(text.contains("Akku: Start 87 %, Ende 87 %"))
        #expect(!text.contains("bpm"))
        #expect(lines.allSatisfy { !$0.contains("\n") })
    }
}
