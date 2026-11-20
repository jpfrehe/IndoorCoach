import XCTest

/// Audit 3: Dynamic-Type-Matrix (L und Accessibility-L) für die Oberflächen aus v0.2 „Die ganze Woche im Blick“:
/// Kraft-Schnellstart, Kraft nachtragen, Verlauf mit Filter „Kraft“, Krafteinheit, „Dein Herz im Winter Arc“.
/// Je Oberfläche Screenshot + Accessibility-Audit; Soft-Checks auf abgeschnittene Kernwerte.
@MainActor
final class AuditMatrixWeekTests: AuditCase {
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testMatrixWeekSurfaces() {
        let sizes = ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityL"]
        for size in sizes {
            let tag = size == sizes[0] ? "L" : "AXL"
            launch(extra: ["-UIPreferredContentSizeCategoryName", size])

            route = "heute"
            let quick = scrollUntilExists(element("strength.quick.kraft"), maxSwipes: 4)
            check(quick.exists, "Kraft-Schnellstart sichtbar @\(tag)")
            shot("\(tag)-schnellstart")
            accessibilityAudit("Heute-Schnellstart@\(tag)")
            tap(quick, "Kraft-Schnellstart öffnen")
            route = "kraft-start"
            settle()
            shot("\(tag)-sheet")
            accessibilityAudit("Kraft-Start@\(tag)")
            if tap(element("strength.start.manual"), "Nachtragen") {
                route = "kraft-nachtragen"
                settle()
                shot("\(tag)-formular")
                accessibilityAudit("Kraft-Nachtragen@\(tag)")
                app.swipeUp(); settle(0.8); shot("\(tag)-formular-unten")
                check(element("strength.entry.save").exists, "Speichern erreichbar @\(tag)")
            }
            app.terminate()

            launch(extra: ["-UIPreferredContentSizeCategoryName", size])
            openTab("Verlauf")
            route = "verlauf-kraft"
            let kraft = app.buttons["Kraft"].firstMatch
            tap(kraft, "Filter Kraft")
            settle(0.8)
            shot("\(tag)-filter")
            let header = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Last'")).firstMatch
            check(header.exists, "Wochenkopf zeigt Muskel-Last @\(tag)")
            check(!app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'TSS 0'")).firstMatch.exists,
                  "Kein „TSS 0“ im Filter Kraft @\(tag)")
            accessibilityAudit("Verlauf-Kraft@\(tag)")
            let row = element("history.strength.row")
            if tap(row, "Krafteinheit öffnen") {
                route = "kraft-detail"
                settle()
                shot("\(tag)-top")
                accessibilityAudit("Kraft-Detail@\(tag)")
                app.swipeUp(); settle(0.8); shot("\(tag)-unten")
                back()
            }

            openTab("Heute")
            route = "winterarc"
            let arc = scrollUntilExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Winter Arc'")).firstMatch)
            tap(arc, "Winter Arc öffnen")
            settle()
            let heart = scrollUntilExists(element("heart.card"), maxSwipes: 8)
            check(heart.exists, "„Dein Herz im Winter Arc“ erreichbar @\(tag)")
            shot("\(tag)-herz")
            accessibilityAudit("Herz-im-Winter-Arc@\(tag)")
            app.terminate()
        }
    }
}
