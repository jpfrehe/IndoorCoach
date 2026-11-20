import XCTest

/// Paket W4-B „Morgenmessung HRV“ (B54): mit Stub (`-uiStrapStub YES`) Gurt verbinden → Morgenmessung aktivieren →
/// Heute-Zeile → 60 s messen → Ergebnis (nur Trendtext). Die Heute-Zeile erscheint nur vor 11 Uhr, der Test
/// prüft sie deshalb weich. Nicht ausgeführt, nur geschrieben.
final class AuditMorningHRVTests: AuditCase {
    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func test50_MorningMeasurementEnableMeasureResult() {
        launch(extra: ["-uiStrapStub", "YES"])
        openTab("Profil")
        let entry = scrollUntilExists(anyElement("profile.strap"), maxSwipes: 6)
        check(entry.exists, "Eintrag „Brustgurt“ im Profil")
        tap(entry, "Brustgurt öffnen")
        route = "morgenmessung"

        let next = anyElement("strap.explainer.continue")
        if waitFast(next, timeout: 6) { tap(next, "Weiter") }
        let connect = anyElement("strap.connect")
        check(waitFast(connect, timeout: 8), "Stub-Gurt in der Suche")
        tap(connect, "Verbinden")
        check(waitFast(anyElement("strap.livePulse"), timeout: 10), "Live-Puls sichtbar")

        let toggle = scrollUntilExists(anyElement("morning.toggle"), maxSwipes: 6)
        check(toggle.exists, "Schalter „Morgenmessung“ (RR vorhanden)")
        check(text(containing: "3× pro Woche reicht").exists, "Hinweis 3× pro Woche")
        // A Toggle row's centre is its label; only the switch itself flips it (audit 3: stayed off).
        clearOfTabBar(toggle)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        log("Tapped Morgenmessung aktivieren (Schalter)", "morning.toggle")
        check((toggle.value as? String) == "1", "Schalter steht auf an")
        shot("aktiviert")

        openTab("Heute")
        let row = anyElement("morning.row")
        guard waitFast(row, timeout: 5) else {
            check(Calendar.current.component(.hour, from: .now) >= MorningHRVUITime.latestHour,
                  "Heute-Zeile fehlt nur nach 11 Uhr")
            return
        }
        tap(row, "Morgenmessung öffnen")
        let start = anyElement("morning.start")
        check(waitFast(start, timeout: 5), "Startknopf")
        tap(start, "Messung starten")
        check(waitFast(anyElement("morning.countdown"), timeout: 5), "Fortschrittsring läuft")
        shot("messung")

        let result = anyElement("morning.result")
        check(result.waitForExistence(timeout: 75), "Ergebnis nach 60 s")
        check(text(containing: "bis zum Trend").exists, "„Noch X Messungen bis zum Trend“")
        check(text(containing: "gemessen (Gurt)").exists, "Quelle „gemessen (Gurt)“")
        shot("ergebnis")
        accessibilityAudit("Morgenmessung-Ergebnis")
    }
}

private enum MorningHRVUITime { static let latestHour = 11 }
