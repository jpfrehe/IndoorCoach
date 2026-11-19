import Foundation
import Testing
@testable import IndoorCoachKit

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var date: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@Suite("Aufzeichnung (B37)")
@MainActor
struct RecordingServiceTests {
    let t0 = Date(timeIntervalSince1970: 1_794_000_000)

    func tempStore() -> RecordingStore {
        RecordingStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)"))
    }

    func make(clock: TestClock, store: RecordingStore? = nil, presenter: NoopRecordingLivePresenter = NoopRecordingLivePresenter())
        -> (RecordingService, RecordingStore, NoopRecordingLivePresenter) {
        let store = store ?? tempStore()
        let service = RecordingService(strap: nil, now: { clock.date }, store: store, presenter: { presenter }, autoTick: false)
        return (service, store, presenter)
    }

    @Test("Eine Spur pro Sekunde: letzter Wert gewinnt, Sekunden ohne Wert sind Lücke")
    func track() throws {
        let clock = TestClock(t0)
        let (service, _, _) = make(clock: clock)
        service.start(kind: .ride, title: "Test")
        service.ingest(heartRate: 100, at: t0.addingTimeInterval(0.2))
        service.ingest(heartRate: 105, at: t0.addingTimeInterval(0.8))   // gleiche Sekunde → 105
        service.ingest(heartRate: 110, at: t0.addingTimeInterval(1.5))
        service.ingest(heartRate: 120, at: t0.addingTimeInterval(4.1))   // Sekunden 2 und 3 ohne Wert
        clock.advance(6)
        let result = try #require(service.stop())
        #expect(result.seconds.heartRate == [105, 110, 0, 0, 120, 0])
        #expect(result.seconds.power == [0, 0, 0, 0, 0, 0])
        #expect(result.gapSeconds == 3)
        #expect(result.kind == .ride)
        #expect(result.duration == 6)
    }

    @Test("Unplausible Werte und Werte vor dem Start zählen nicht")
    func implausible() throws {
        let clock = TestClock(t0)
        let (service, _, _) = make(clock: clock)
        service.start(kind: .other, title: "X")
        service.ingest(heartRate: 0, at: t0.addingTimeInterval(0.5))
        service.ingest(heartRate: 300, at: t0.addingTimeInterval(1.5))
        service.ingest(heartRate: 90, at: t0.addingTimeInterval(-5))
        clock.advance(3)
        let result = try #require(service.stop())
        #expect(result.seconds.heartRate == [0, 0, 0])
    }

    @Test("Reconnects werden gezählt, Verbindungsstatus folgt")
    func reconnects() throws {
        let clock = TestClock(t0)
        let (service, _, _) = make(clock: clock)
        service.start(kind: .ride, title: "T")
        service.ingest(state: .connected)
        #expect(service.connected)
        service.ingest(state: .reconnecting)
        #expect(!service.connected)
        service.ingest(state: .connected)
        service.ingest(state: .reconnecting)
        service.ingest(state: .reconnecting)   // doppelte Meldung zählt nicht
        service.ingest(state: .connected)
        clock.advance(10)
        #expect(try #require(service.stop()).reconnects == 2)
    }

    @Test("Zwischenspeicherung alle 30 s, Stopp löscht die Datei")
    func autosave() throws {
        let clock = TestClock(t0)
        let (service, store, _) = make(clock: clock)
        service.start(kind: .ride, title: "T", plannedWorkoutID: UUID())
        service.ingest(heartRate: 100, at: t0)
        clock.advance(10); service.tick()
        #expect(store.load() == nil)
        clock.advance(25); service.tick()
        let saved = try #require(store.load())
        #expect(saved.title == "T")
        #expect(saved.plannedWorkoutID != nil)
        #expect(saved.heartRate.first == 100)
        _ = service.stop()
        #expect(store.load() == nil)
    }

    @Test("Unterbrochene Aufzeichnung wird beim Start erkannt und kann gespeichert werden")
    func interruptedSave() throws {
        let clock = TestClock(t0)
        let store = tempStore()
        let (first, _, _) = make(clock: clock, store: store)
        first.start(kind: .ride, title: "Abbruch")
        for s in 0..<40 { first.ingest(heartRate: 110, at: t0.addingTimeInterval(Double(s) + 0.1)) }
        clock.advance(40); first.tick()
        // App-Ende: Dienst verschwindet, Datei bleibt. 10 min später neuer Start.
        clock.advance(600)
        let (second, _, _) = make(clock: clock, store: store)
        let found = try #require(second.interrupted)
        #expect(found.title == "Abbruch")
        let result = try #require(second.finishInterrupted())
        #expect(result.seconds.count == 40)             // endet beim letzten Speichern
        #expect(result.seconds.heartRate?.allSatisfy { $0 == 110 } == true)
        #expect(second.interrupted == nil)
        #expect(store.load() == nil)
    }

    @Test("Fortsetzen: Lücke bleibt 0, Aufzeichnung läuft weiter")
    func interruptedResume() throws {
        let clock = TestClock(t0)
        let store = tempStore()
        let (first, _, _) = make(clock: clock, store: store)
        first.start(kind: .ride, title: "Weiter")
        for s in 0..<30 { first.ingest(heartRate: 100, at: t0.addingTimeInterval(Double(s) + 0.1)) }
        clock.advance(30); first.tick()
        clock.advance(20)
        let (second, _, _) = make(clock: clock, store: store)
        second.resumeInterrupted()
        #expect(second.isRunning)
        second.ingest(heartRate: 130, at: t0.addingTimeInterval(50.2))
        clock.advance(10)
        let result = try #require(second.stop())
        #expect(result.seconds.count == 60)
        #expect(result.seconds.heartRate?[10] == 100)
        #expect(result.seconds.heartRate?[35] == 0)
        #expect(result.seconds.heartRate?[50] == 130)
        #expect(result.startedAt == t0)
    }

    @Test("Verwerfen löscht die Datei")
    func discard() {
        let clock = TestClock(t0)
        let store = tempStore()
        let (first, _, _) = make(clock: clock, store: store)
        first.start(kind: .other, title: "x")
        clock.advance(40); first.tick()
        let (second, _, _) = make(clock: clock, store: store)
        #expect(second.interrupted != nil)
        second.discardInterrupted()
        #expect(second.interrupted == nil)
        #expect(store.load() == nil)
    }

    @Test("Live-Darstellung: start, Update höchstens alle 5 s, Blockwechsel sofort, end")
    func presenter() throws {
        let clock = TestClock(t0)
        let spy = CountingPresenter()
        let service = RecordingService(strap: nil, now: { clock.date }, store: tempStore(), presenter: { spy }, autoTick: false)
        let plan = WorkoutDefinition(title: "P", type: .endurance, summary: "", segments: [
            .warmup(1, from: 0.5, to: 0.6), .steady(5, at: 0.7)
        ])
        service.start(kind: .ride, title: "P", definition: plan)
        #expect(spy.starts == 1)
        clock.advance(2); service.tick()
        #expect(spy.updates == 0)
        clock.advance(4); service.tick()          // 6 s seit Start
        #expect(spy.updates == 1)
        clock.advance(1); service.tick()
        #expect(spy.updates == 1)
        clock.advance(56); service.tick()         // Blockwechsel bei 60 s
        #expect(spy.updates == 2)
        #expect(spy.last?.blockTitle == "Konstant")
        _ = service.stop()
        #expect(spy.ends == 1)
    }

    @Test("Plan-Zeitleiste: aktueller Block und Restzeit")
    func planBlocks() {
        let plan = WorkoutDefinition(title: "P", type: .sweetSpot, summary: "", segments: [
            .warmup(10, from: 0.5, to: 0.7),
            .intervals(2, on: 600, at: 0.9, off: 300, at: 0.5),
            .cooldown(5, from: 0.6, to: 0.4)
        ])
        let blocks = RecordingPlan.blocks(from: plan)
        #expect(blocks.map(\.title) == ["Aufwärmen", "Intervall 1/2", "Pause", "Intervall 2/2", "Pause", "Ausfahren"])
        #expect(blocks.last?.end == 600 + 2 * 900 + 300)
        let now = RecordingPlan.current(in: blocks, elapsed: 650)
        #expect(now?.block.title == "Intervall 1/2")
        #expect(now?.remaining == 550)
        #expect(RecordingPlan.current(in: blocks, elapsed: 99_999) == nil)
    }

    @Test("Akku unter 20 % ist ein Hinweis vor dem Start")
    func battery() async {
        let stub = StubStrapController(autoplay: false)
        let strap = StrapSession(controller: stub)
        let service = RecordingService(strap: strap, now: { .now }, store: tempStore(), presenter: { NoopRecordingLivePresenter() }, autoTick: false)
        #expect(!service.lowBattery)
        stub.emit(.battery(15))
        for _ in 0..<5 { await Task.yield(); try? await Task.sleep(for: .milliseconds(10)) }
        #expect(service.lowBattery)
    }

    @Test("Gurt-Ereignisse der StrapSession landen in der Spur")
    func strapIntegration() async throws {
        let stub = StubStrapController(autoplay: false)
        let strap = StrapSession(controller: stub)
        let clock = TestClock(.now)
        let service = RecordingService(strap: strap, now: { clock.date }, store: tempStore(), presenter: { NoopRecordingLivePresenter() }, autoTick: false)
        service.start(kind: .ride, title: "S")
        stub.emit(.state(.connected))
        stub.emit(.measurement(try #require(HeartRateMeasurement.parse(Data([0x00, 88]))), at: clock.date))
        for _ in 0..<5 { await Task.yield(); try? await Task.sleep(for: .milliseconds(10)) }
        #expect(service.heartRate == 88)
        #expect(service.connected)
        clock.advance(2)
        #expect(try #require(service.stop()).seconds.heartRate?.first == 88)
    }
}

@MainActor
final class CountingPresenter: RecordingLivePresenting {
    var starts = 0, updates = 0, ends = 0
    var last: RecordingLiveState?
    func start(_ state: RecordingLiveState) { starts += 1; last = state }
    func update(_ state: RecordingLiveState) { updates += 1; last = state }
    func end(_ state: RecordingLiveState?) { ends += 1 }
}
