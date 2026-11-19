import Testing
@testable import IndoorCoachKit

@Suite("Gurt-Modellhinweise")
struct StrapModelHintsTests {
    @Test("Bekannte Modelle", arguments: [
        ("TICKR 1A2B", 3), ("TICKR X 9F8E", 3), ("Polar H10 A1B2C3D4", 2), ("Polar H9 12345678", 1),
        ("HRM-Pro Plus:123456", 3), ("HRM 600", 3), ("COOSPO H9Z 0001", 2)
    ])
    func known(name: String, connections: Int) {
        #expect(StrapModelHints.hint(forName: name).bleConnections == connections)
    }

    @Test("Coospo H9Z wird nicht als Polar H9 erkannt")
    func h9z() {
        #expect(StrapModelHints.hint(forName: "H9Z-1234").model == "Coospo H9Z")
    }

    @Test("Polar H10 erinnert an die Aktivierung in Polar Beat")
    func h10Note() {
        #expect(StrapModelHints.hint(forName: "Polar H10 AB12").note.contains("Polar Beat"))
    }

    @Test("Unbekannt: kein Limit, nur Hinweis")
    func unknown() {
        let h = StrapModelHints.hint(forName: "NoName Band")
        #expect(h.bleConnections == nil)
        #expect(!h.note.isEmpty)
        #expect(StrapModelHints.hint(forName: nil).bleConnections == nil)
    }
}
