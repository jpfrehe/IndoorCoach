import XCTest

/// Paket CI (B28/B29) – Check-in vor der Einheit: Karte in „Heute“ → Fragen → Angebot „45 min“ → Einheit angepasst.
/// Der Check-in ist in UI-Test-Läufen mit Seed ausgeblendet, `-uiCheckIn YES` schaltet ihn ein.
final class AuditCheckInTests: AuditCase {
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func test40_CheckInOffersShorterWorkout() {
        launch(extra: ["-uiCheckIn", "YES"])
        route = "heute"
        let start = element("checkin.card.start")
        check(start.waitForExistence(timeout: 5), "Check-in-Karte in „Heute“ (geplante Einheit heute)")
        check(start.frame.height >= 44, "Karten-Button mindestens 44 pt hoch")
        shot("card")
        tap(start, "Check-in")
        route = "checkin"

        let legs = app.buttons["checkin.legs.bad"], sleep = app.buttons["checkin.sleep.bad"]
        check(legs.waitForExistence(timeout: 3), "Frage „Beine“ sichtbar")
        check(legs.frame.height >= 44 && sleep.frame.height >= 44, "Tipp-Ziele mindestens 44 pt hoch")
        check(app.buttons["checkin.skip"].exists, "Überspringen möglich")
        tap(legs, "Beine schwer")
        tap(sleep, "Schlaf schlecht")
        shot("answers")
        accessibilityAudit("Check-in-Sheet")
        tap(app.buttons["checkin.done"], "Fertig")

        // Angebote: kürzer (bevorzugt 45 min), tauschen, ggf. Joker.
        let shorten = app.buttons.matching(NSPredicate(format: "label CONTAINS '45 min'")).firstMatch
        check(shorten.waitForExistence(timeout: 3), "Angebot „45 min“ sichtbar")
        check(element("checkin.offer.swap").exists, "Angebot „Gegen Grundlage tauschen“ sichtbar")
        shot("offers")
        accessibilityAudit("Check-in-Angebote")
        tap(shorten, "45 min")
        route = "heute"
        check(waitForBanner(containing: "Einheit angepasst:"), "Banner „Einheit angepasst: 45 min …“")
        check(!element("checkin.card.start").exists, "Karte nach dem Check-in weg")
        shot("after")
    }

    func test41_CheckInCanBeSkipped() {
        launch(extra: ["-uiCheckIn", "YES"])
        route = "heute"
        let start = element("checkin.card.start")
        check(start.waitForExistence(timeout: 5), "Check-in-Karte")
        tap(start, "Check-in")
        tap(app.buttons["checkin.skip"], "Überspringen")
        check(!element("checkin.card.start").waitForExistence(timeout: 2), "Karte nach dem Überspringen weg")
    }
}
