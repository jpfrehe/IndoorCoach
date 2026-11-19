import XCTest

/// Paket W3-A – Krafteinheit mit Gurt aufzeichnen (Stub `-uiStrapStub YES`):
/// Gurt koppeln → Kraft → „Mit Gurt aufzeichnen“ → Start → Übung abhaken → Stopp → Härte → Speichern → im Verlauf.
@MainActor
final class AuditStrengthRecordingTests: AuditCase {
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

    func test60_RecordStrengthWithStubStrap() {
        launch(extra: ["-uiStrapStub", "YES"])
        pairStub()
        openTab("Heute")
        route = "heute"
        tap(element("strength.quick.kraft"), "Kraft")
        tap(element("strength.start.none"), "Ohne Vorlage")
        tap(element("strength.start.record"), "Mit Gurt aufzeichnen")

        let start = element("recording.start")
        check(waitFast(start, timeout: 10), "Aufzeichnung bereit")
        check(!element("recording.noStrap").exists, "Gurt gekoppelt: kein Hinweis")
        tap(element("strength.checklist.add"), "Übung hinzufügen")
        pickExercise(id: "bench_press", name: "Bankdrücken")
        tap(start, "Start")
        check(waitFast(element("recording.pulse"), timeout: 10), "Puls sichtbar")
        tap(element("strength.checklist.bench_press"), "Bankdrücken abhaken")
        shot("laeuft")
        sleep(3)   // ein paar Pulssekunden sammeln

        tap(element("recording.stop"), "Stopp")
        tap(element("recording.stop.confirm"), "Beenden")
        check(waitFast(element("strength.finish.save"), timeout: 6), "Abschluss-Sheet")
        tap(element("strength.exertion.6"), "Härte 6")
        shot("abschluss")
        tap(element("strength.finish.save"), "Speichern")
        check(waitForBanner(containing: "Krafteinheit gespeichert"), "Gespeichert")

        openTab("Verlauf")
        route = "verlauf"
        tap(visibleButton("Kraft"), "Filter Kraft")
        let entry = element("history.strength.row")
        check(entry.waitForExistence(timeout: 4), "Aufgezeichnete Krafteinheit im Verlauf")
        tap(entry, "Detail öffnen")
        check(element("strength.detail.delete").waitForExistence(timeout: 3), "Detail sichtbar")
        shot("detail")
    }
}
