import XCTest

/// Paket „HR · Brustgurt-Basis“ (B36): Profil → Dienste & Geräte → Brustgurt, mit Stub (`-uiStrapStub YES`):
/// Erklärseite → Suche → Verbinden → Live-Puls sichtbar. Nicht ausgeführt, nur geschrieben.
final class AuditStrapTests: AuditCase {
    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func test40_StrapSearchConnectLivePulse() {
        launch(extra: ["-uiStrapStub", "YES"])
        openConnections()
        let entry = scrollUntilExists(anyElement("profile.strap"), maxSwipes: 6)
        check(entry.exists, "Eintrag „Brustgurt“ unter Dienste & Geräte")
        tap(entry, "Brustgurt öffnen")
        route = "brustgurt"

        let next = anyElement("strap.explainer.continue")
        check(waitFast(next, timeout: 6), "Erklärseite vor der Bluetooth-Abfrage")
        check(text(containing: "Nichts verlässt das iPhone").exists, "Datenschutz-Satz")
        shot("erklaerung")
        tap(next, "Weiter")

        let connect = anyElement("strap.connect")
        check(waitFast(connect, timeout: 8), "Stub-Gurt in der Suche")
        shot("suche")
        tap(connect, "Verbinden")

        let pulse = anyElement("strap.livePulse")
        check(waitFast(pulse, timeout: 10), "Live-Puls sichtbar")
        check(pulse.label.contains("bpm"), "Puls in bpm (\(pulse.label))")
        check(text(containing: "empfangen").exists, "RR-Intervalle ✓")
        shot("live")
        accessibilityAudit("Brustgurt-Live")
    }
}
