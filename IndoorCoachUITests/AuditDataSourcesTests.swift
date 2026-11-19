import XCTest

/// Paket W3-D (B51) – Profil → Datenquellen: Health aktivieren, Quellen und ehrliche Lücken sichtbar, Export standardmäßig aus.
/// Läuft mit dem Health-Stub (`-uiHealthStub YES`), ohne echte Freigabe. Nicht automatisch im CI ausgeführt.
@MainActor
final class AuditDataSourcesTests: AuditCase {
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func test60_EnableHealthShowsSources() {
        launch(extra: ["-uiHealthStub", "YES"])
        route = "profil"
        openTab("Profil")
        tap(scrollUntilExists(element("profile.dataSources")), "Profil → Datenquellen")
        route = "datenquellen"

        let toggle = element("dataSources.healthToggle")
        check(toggle.waitForExistence(timeout: 5), "Schalter Apple Health")
        tap(toggle, "Apple Health einschalten")

        // Die Quellen laden nach dem Einschalten asynchron: erst abwarten, dann scrollen (sonst rauscht man daran vorbei).
        let sources = element("dataSources.sources")
        if !waitFast(sources, timeout: 8) { _ = scrollUntilExists(sources) }
        check(sources.exists, "Erkannte Quellen erscheinen nach dem Einschalten")
        check(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Apple Watch'")).firstMatch.waitForExistence(timeout: 4),
              "Apple Watch als Quelle")
        shot("quellen")

        let gaps = scrollUntilExists(element("dataSources.gaps"))
        check(gaps.exists, "Ehrliche Lücken sichtbar")
        check(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'kein HRV'")).firstMatch.exists, "Hinweis zu HRV")
        accessibilityAudit("Datenquellen")
    }

    func test61_ExportIsOffByDefaultAndMethodPageOpens() {
        launch(extra: ["-uiHealthStub", "YES"])
        openTab("Profil")
        tap(scrollUntilExists(element("profile.dataSources")), "Profil → Datenquellen")

        let strength = scrollUntilExists(element("dataSources.export.strength"))
        check(strength.exists, "Export-Schalter Kraft")
        check((strength.value as? String) == "0", "Export ist standardmäßig aus")

        tap(scrollUntilExists(element("dataSources.method")), "So rechnet IndoorCoach")
        check(element("dataSources.methodView").waitForExistence(timeout: 4), "Methodenseite")
        check(app.staticTexts["Puls-TSS (hrTSS)"].exists, "Puls-TSS erklärt")
        shot("methode")
    }
}
