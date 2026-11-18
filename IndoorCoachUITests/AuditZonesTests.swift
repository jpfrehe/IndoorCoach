import XCTest

/// Paket Z – Zeit in Zonen je Fahrt (needs the demo seed: its recent indoor rides carry 1 Hz data).
@MainActor
final class AuditZonesTests: AuditCase {
    func test36_RideZones() {
        launch()
        openTab("Verlauf")
        tap(app.buttons["Indoor"], "Filter Indoor")
        let ride = scrollUntilExists(row(0))
        tap(ride, "Neueste Indoor-Fahrt")
        _ = waitFast(app.navigationBars.buttons["BackButton"], timeout: 4)
        route = "fahrt"

        let card = scrollUntilExists(app.otherElements["ride.zones"])
        check(card.exists, "Karte Zeit in Zonen sichtbar")
        scrollTo(card)
        let power = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Zone 2 Grundlage' AND label CONTAINS 'Minute'")).firstMatch
        check(power.waitForExistence(timeout: 3), "Leistungszone mit Minuten")
        check(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' min'")).count > 0, "Minuten-Beschriftung")
        shot("power")

        let heart = app.segmentedControls.buttons["Puls"]
        if tap(heart, "Umschalter Puls") {
            let zone = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Zone 3 Tempo'")).firstMatch
            check(zone.waitForExistence(timeout: 3), "Pulszonen sichtbar")
        }
        shot("heart")
        accessibilityAudit("Fahrt-Zonen")
    }
}
