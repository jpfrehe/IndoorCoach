import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Gurt-Sitzung mit Stub")
@MainActor
struct StrapSessionTests {
    func make() -> (StrapSession, StubStrapController) {
        let stub = StubStrapController(autoplay: false)
        return (StrapSession(controller: stub), stub)
    }

    func settle() async {
        for _ in 0..<5 { await Task.yield(); try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("Suche liefert Gurte nach Signalstärke sortiert")
    func scan() async {
        let (session, stub) = make()
        session.startScan()
        stub.emit(.discovered(DiscoveredStrap(id: UUID(), name: "TICKR 1", rssi: -80)))
        stub.emit(.discovered(DiscoveredStrap(id: UUID(), name: "Polar H10 2", rssi: -50)))
        await settle()
        #expect(stub.isScanning)
        #expect(session.discovered.map(\.name) == ["Polar H10 2", "TICKR 1"])
    }

    @Test("Messwerte setzen Puls und RR-gesehen")
    func measurement() async throws {
        let (session, stub) = make()
        stub.emit(.state(.connected))
        stub.emit(.measurement(try #require(HeartRateMeasurement.parse(Data([0x10, 61, 0x00, 0x04]))), at: .now))
        await settle()
        #expect(session.liveHeartRate == 61)
        #expect(session.rrSeen)
        #expect(session.state == .connected)
    }

    @Test("Akku, Gerätename und Modellhinweis")
    func deviceInfo() async {
        let (session, stub) = make()
        stub.emit(.battery(15))
        stub.emit(.deviceInfo(name: "TICKR 4711", manufacturer: "Wahoo", model: nil))
        await settle()
        #expect(session.batteryLow)
        #expect(session.hint?.bleConnections == 3)
        #expect(session.manufacturer == "Wahoo")
    }

    @Test("Vergessen leert Anzeige und Controller")
    func forget() async {
        let (session, stub) = make()
        stub.emit(.battery(80))
        await settle()
        session.forget()
        #expect(stub.forgotten)
        #expect(session.batteryLevel == nil)
        #expect(session.liveHeartRate == nil)
    }

    @Test("Protokoll zählt Pakete und Reconnects")
    func recording() async throws {
        let (session, stub) = make()
        stub.emit(.battery(90))
        stub.emit(.state(.connected))
        await settle()
        session.startProtocol()
        let m = try #require(HeartRateMeasurement.parse(Data([0x00, 70])))
        stub.emit(.measurement(m, at: .now))
        stub.emit(.state(.reconnecting))
        await settle()
        let text = session.stopProtocol().joined(separator: "\n")
        #expect(text.contains("Pakete: 1"))
        #expect(text.contains("Reconnects: 1"))
        #expect(session.protocolRunning == false)
    }

    @Test("Stub-Autoplay: Verbinden liefert Puls")
    func autoplay() async {
        let stub = StubStrapController(autoplay: true)
        let session = StrapSession(controller: stub)
        session.startScan()
        for _ in 0..<50 where session.discovered.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        guard let first = session.discovered.first else { Issue.record("kein Gurt"); return }
        session.connect(first.id)
        for _ in 0..<80 where session.liveHeartRate == nil { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(session.liveHeartRate != nil)
        session.disconnect()
    }
}
