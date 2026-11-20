import XCTest

/// Paket STR (B42–B45) – Krafttraining erfassen: Nachtragen in unter 15 s, Vorlage → Abschluss, Verlauf.
/// Benötigt den Demo-Seed (enthält drei Krafteinheiten). Nicht automatisch im CI ausgeführt.
@MainActor
final class AuditStrengthTests: AuditCase {
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func test50_ManualEntryUnder15Seconds() {
        launch()
        route = "heute"
        let started = Date()
        let quick = element("strength.quick.kraft")
        check(quick.waitForExistence(timeout: 5), "Schnellstart „Kraft“ auf Heute")
        check(quick.frame.height >= 44, "Tipp-Ziel mindestens 44 pt hoch")
        tap(quick, "Kraft")
        tap(element("strength.start.manual"), "Nachtragen")
        route = "nachtragen"
        tap(element("strength.exertion.6"), "Härte 6")
        // Die Accessibility-Prüfung gehört nicht zur Bedienzeit des Fahrers.
        let auditStart = Date()
        accessibilityAudit("Kraft nachtragen")
        let auditTime = Date().timeIntervalSince(auditStart)
        tap(element("strength.entry.save"), "Speichern")
        let elapsed = Date().timeIntervalSince(started) - auditTime
        check(waitForBanner(containing: "Krafteinheit gespeichert"), "Bestätigung erscheint")
        check(elapsed < 15, "Nachtragen in unter 15 s (\(Int(elapsed)) s)")
        timing("kraft-nachtragen", Int(elapsed * 1000))
    }

    func test51_TemplateToFinish() {
        launch()
        route = "profil"
        openTab("Profil")
        let open = scrollUntilExists(element("profile.strength"))
        tap(open, "Profil → Kraft")
        tap(element("strength.template.new"), "Neue Vorlage")
        type(element("strength.template.name"), "Push", "Name")
        tap(element("strength.checklist.add"), "Übung hinzufügen")
        pickExercise(id: "bench_press", name: "Bankdrücken")
        tap(element("strength.template.save"), "Vorlage speichern")
        check(element("strength.template.Push").waitForExistence(timeout: 3), "Vorlage erscheint in der Liste")
        shot("vorlagen")

        openTab("Heute")
        route = "heute"
        tap(element("strength.quick.kraft"), "Kraft")
        tap(element("strength.start.template.Push"), "Vorlage Push")
        tap(element("strength.start.manual"), "Nachtragen")
        let details = element("strength.entry.exercises")
        check(details.waitForExistence(timeout: 3) || scrollUntilExists(details, maxSwipes: 4).exists, "Übungen mit Vorlage vorbelegt")
        tap(element("strength.checklist.bench_press"), "Bankdrücken abhaken")
        tap(element("strength.exertion.7"), "Härte 7")
        tap(element("strength.entry.save"), "Speichern")
        check(waitForBanner(containing: "Krafteinheit gespeichert"), "Gespeichert")

        openTab("Verlauf")
        route = "verlauf"
        tap(visibleButton("Kraft"), "Filter Kraft")
        let entry = element("history.strength.row")
        check(entry.waitForExistence(timeout: 3), "Krafteinheit im Verlauf")
        tap(entry, "Detail öffnen")
        check(element("strength.detail.delete").waitForExistence(timeout: 3), "Kraft-Detail sichtbar")
        shot("detail")
        accessibilityAudit("Kraft-Detail")
    }

    func test52_OtherSession() {
        launch()
        route = "heute"
        tap(element("strength.quick.other"), "Andere Einheit")
        tap(element("other.start.manual"), "Nachtragen")
        check(element("strength.entry.sport").waitForExistence(timeout: 3), "Sportart wählbar")
        tap(element("strength.exertion.5"), "Härte 5")
        tap(element("strength.entry.save"), "Speichern")
        check(waitForBanner(containing: "gespeichert"), "Gespeichert")
    }
}
