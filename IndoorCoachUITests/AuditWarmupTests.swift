import XCTest

/// Paket WU – Aufwärm-Check (needs the demo seed: its recent indoor rides carry a steady 6-minute block with a falling pulse).
@MainActor
final class AuditWarmupTests: AuditCase {
    func test40_WarmupCheckInPerformance() {
        launch()
        openTab("Verlauf")
        let open = app.descendants(matching: .any)["performance.open"].firstMatch
        check(waitFast(open), "Zeile „Leistung“ oben im Verlauf")
        tap(open, "Leistung öffnen")
        route = "leistung"

        let card = scrollUntilExists(app.otherElements["warmup.card"])
        check(card.exists, "Karte Aufwärm-Check sichtbar")
        scrollTo(card)
        let headline = app.staticTexts["warmup.headline"]
        check(headline.waitForExistence(timeout: 3), "Überschrift mit Puls bei Referenzleistung")
        check(headline.label.contains("Puls bei") && headline.label.contains("Messungen"), "Puls, Watt und Anzahl der Messungen")
        check(app.staticTexts["warmup.source"].exists, "Etikett gemessen/angenommen")
        check(!app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'LSCT'")).firstMatch.exists, "kein LSCT im Text")
        shot("trend")
        accessibilityAudit("Aufwärm-Check Leistung")
    }

    func test41_WarmupCheckInRideAndNewBase() {
        launch()
        openTab("Verlauf")
        tap(app.buttons["Indoor"], "Filter Indoor")
        let ride = scrollUntilExists(row(0))
        tap(ride, "Neueste Indoor-Fahrt")
        _ = waitFast(app.navigationBars.buttons["BackButton"], timeout: 4)
        route = "fahrt"

        let card = scrollUntilExists(app.otherElements["warmup.card"])
        check(card.exists, "Karte Aufwärm-Check in der Fahrt")
        scrollTo(card)
        check(app.staticTexts["warmup.ride"].exists || app.otherElements["warmup.ride"].exists, "Wert dieser Fahrt")

        let newBase = app.buttons["warmup.newBase"]
        if tap(newBase, "Neue Basis ab heute") {
            let confirm = app.buttons["Neue Basis setzen"]
            check(confirm.waitForExistence(timeout: 3), "Bestätigung erscheint")
            tap(confirm, "Neue Basis setzen")
            // After the reset no measurement counts yet: the trend hint (or no card for this ride) takes over.
            settle()
            shot("neue-basis")
        }
        accessibilityAudit("Aufwärm-Check Fahrt")
    }
}
