import Foundation
import Testing
@testable import IndoorCoachKit

@MainActor
final class FakeActivityBackend: RecordingActivityBackend {
    var isAvailable = true
    var requestSucceeds = true
    private(set) var calls: [String] = []
    private(set) var stale: [Date] = []
    private(set) var dismiss: [TimeInterval] = []

    func request(_ state: RecordingLiveState, staleDate: Date) -> Bool {
        calls.append("request"); stale.append(staleDate); return requestSucceeds
    }
    func update(_ state: RecordingLiveState, staleDate: Date) async { calls.append("update"); stale.append(staleDate) }
    func end(_ state: RecordingLiveState, dismissAfter: TimeInterval) async { calls.append("end"); dismiss.append(dismissAfter) }
}

@Suite("Live-Activity-Anzeige")
struct RecordingLiveDisplayTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static func state(hr: Int? = 142, connected: Bool = true, block: String? = "Sweet Spot 2/3",
                      end: Date? = t0.addingTimeInterval(90)) -> RecordingLiveState {
        RecordingLiveState(kind: .ride, title: "Rolle", startedAt: t0, heartRate: hr, connected: connected,
                           blockTitle: block, blockEndsAt: end)
    }

    @Test("Puls und Platzhalter")
    func heartRate() {
        #expect(RecordingLiveDisplay(Self.state()).heartRateText == "142")
        #expect(RecordingLiveDisplay(Self.state(hr: nil)).heartRateText == "–")
        #expect(RecordingLiveDisplay(Self.state(hr: 0)).hasHeartRate == false)
    }

    @Test("Verbindungsstatus")
    func connection() {
        #expect(RecordingLiveDisplay(Self.state()).connectionWarning == nil)
        #expect(RecordingLiveDisplay(Self.state(connected: false)).connectionWarning == "Gurt getrennt")
    }

    @Test("Block und Restzeit")
    func block() {
        let d = RecordingLiveDisplay(Self.state(block: "  "))
        #expect(d.blockText == nil)
        let ok = RecordingLiveDisplay(Self.state())
        #expect(ok.blockEnd(at: Self.t0) != nil)
        #expect(ok.blockEnd(at: Self.t0.addingTimeInterval(100)) == nil)
    }

    @Test("VoiceOver-Label")
    func accessibility() {
        let label = RecordingLiveDisplay(Self.state(connected: false)).accessibilityLabel(at: Self.t0)
        #expect(label.contains("Puls 142 Schläge pro Minute"))
        #expect(label.contains("Gurt getrennt"))
        #expect(label.contains("Sweet Spot 2/3, noch"))
        #expect(RecordingLiveDisplay(Self.state(hr: nil)).accessibilityLabel(at: Self.t0).contains("Kein Pulswert"))
    }

    @Test("Symbol je Art")
    func symbols() {
        for kind in RecordingKind.allCases {
            var s = Self.state(); s.kind = kind
            #expect(!RecordingLiveDisplay(s).kindSymbol.isEmpty)
        }
    }
}

@MainActor
@Suite("Live-Activity-Zustandsmaschine")
struct RecordingLiveControllerTests {
    let s1 = RecordingLiveDisplayTests.state()
    var s2: RecordingLiveState { RecordingLiveDisplayTests.state(hr: 150) }

    @Test("start, update, end in Reihenfolge")
    func lifecycle() async {
        let fake = FakeActivityBackend()
        let c = RecordingLiveController(backend: fake)
        c.start(s1); c.update(s2); c.end(nil)
        await c.waitUntilIdle()
        #expect(fake.calls == ["request", "update", "end"])
        #expect(fake.dismiss == [RecordingLiveController.dismissDelay])
        #expect(!c.isRunning)
    }

    @Test("ohne Berechtigung: Noop")
    func disabled() async {
        let fake = FakeActivityBackend(); fake.isAvailable = false
        let c = RecordingLiveController(backend: fake)
        c.start(s1); c.update(s2); c.end(s2)
        await c.waitUntilIdle()
        #expect(fake.calls.isEmpty)
    }

    @Test("Request schlägt fehl: kein Update/Ende")
    func requestFails() async {
        let fake = FakeActivityBackend(); fake.requestSucceeds = false
        let c = RecordingLiveController(backend: fake)
        c.start(s1); c.end(nil)
        await c.waitUntilIdle()
        #expect(fake.calls == ["request"])
    }

    @Test("Update vor Start startet, doppeltes Ende ist harmlos, spätes Update lebt nicht auf")
    func tolerant() async {
        let fake = FakeActivityBackend()
        let c = RecordingLiveController(backend: fake)
        c.update(s1)
        c.end(nil); c.end(nil)
        c.update(s2)
        await c.waitUntilIdle()
        #expect(fake.calls == ["request", "end"])
    }

    @Test("Doppelter Start und identische Updates erzeugen keine neue Aktivität")
    func dedupe() async {
        let fake = FakeActivityBackend()
        let c = RecordingLiveController(backend: fake)
        c.start(s1); c.start(s2); c.update(s2)
        await c.waitUntilIdle()
        #expect(fake.calls == ["request", "update"])
    }

    @Test("Neustart nach Ende")
    func restart() async {
        let fake = FakeActivityBackend()
        let c = RecordingLiveController(backend: fake)
        c.start(s1); c.end(nil); c.start(s2)
        await c.waitUntilIdle()
        #expect(fake.calls == ["request", "end", "request"])
    }

    @Test("staleDate liegt nach der Aktualisierungsfrist")
    func stale() async {
        let fake = FakeActivityBackend()
        let t = RecordingLiveDisplayTests.t0
        let c = RecordingLiveController(backend: fake, now: { t })
        c.start(s1)
        await c.waitUntilIdle()
        #expect(fake.stale == [t.addingTimeInterval(RecordingLiveDisplay.staleInterval)])
    }
}
