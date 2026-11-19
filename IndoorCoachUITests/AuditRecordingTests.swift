import XCTest

/// Paket REC – Aufzeichnung mit Gurt am iPhone (B37/B39), mit Stub (`-uiStrapStub YES`):
/// Gurt koppeln → Einheit von heute → „Puls am iPhone mitschreiben“ → Start → Puls sichtbar → Stopp → Ergebnis.
/// Braucht eine für heute geplante Einheit (Demo-Seed). Nicht ausgeführt, nur geschrieben.
@MainActor
final class AuditRecordingTests: AuditCase {
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func pairStub() {
        openTab("Profil")
        let entry = scrollUntilExists(element("profile.strap"), maxSwipes: 6)
        tap(entry, "Brustgurt öffnen")
        let next = element("strap.explainer.continue")
        if waitFast(next, timeout: 6) { tap(next, "Weiter") }
        let connect = element("strap.connect")
        if waitFast(connect, timeout: 8) { tap(connect, "Verbinden") }
        check(waitFast(element("strap.livePulse"), timeout: 10), "Stub-Gurt verbunden")
    }

    func test40_RecordRideWithStubStrap() {
        launch(extra: ["-uiStrapStub", "YES"])
        pairStub()
        openTab("Heute")
        route = "heute"
        tap(button(containing: "Nächste Einheit"), "Karte Nächste Einheit")
        let entry = scrollUntilExists(element("recording.entry"))
        check(entry.exists, "Knopf „Puls am iPhone mitschreiben“ (Einheit heute geplant, Gurt gekoppelt)")
        guard entry.exists else { return }
        tap(entry, "Aufzeichnung öffnen")
        route = "aufzeichnung"

        let start = element("recording.start")
        check(waitFast(start), "Start-Knopf „Los, wenn MyWhoosh startet“")
        check(start.frame.height >= 44, "Start-Knopf mindestens 44 pt hoch")
        shot("bereit")
        tap(start, "Los, wenn MyWhoosh startet")

        let pulse = element("recording.pulse")
        check(waitFast(pulse, timeout: 10), "Puls groß sichtbar")
        check(pulse.label.contains("Schläge pro Minute"), "Puls vorgelesen (\(pulse.label))")
        check(element("recording.elapsed").exists, "Zeit läuft")
        check(element("recording.connection").exists, "Verbindungsstatus")
        shot("laeuft")
        accessibilityAudit("Aufzeichnung läuft")

        tap(element("recording.stop"), "Stopp")
        let confirm = element("recording.stop.confirm")
        check(waitFast(confirm, timeout: 4), "Bestätigung vor dem Beenden")
        tap(confirm, "Beenden und speichern")

        check(waitFast(element("recording.result"), timeout: 6), "Ergebnis sichtbar")
        check(element("recording.pending").exists || element("recording.source").exists, "Zuordnung oder „wartet auf Fahrt“")
        check(element("recording.powerHint").exists, "Hinweis: echte Watt brauchen die Mac-Brücke")
        shot("ergebnis")
        accessibilityAudit("Aufzeichnung Ergebnis")
    }
}
