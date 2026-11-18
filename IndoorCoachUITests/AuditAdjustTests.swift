import XCTest

/// Paket A – "Einheit anpassen" (kürzer / leichter, mit Original wiederherstellen).
final class AuditAdjustTests: AuditCase {
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    /// The "Dauer" tile value of the workout detail (the label next to the "Dauer" caption).
    private func durationValue() -> String {
        let tiles = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"^(\d+ min|\d+:\d\d h|\d+:\d\d min)$"#))
        return tiles.firstMatch.exists ? tiles.firstMatch.label : ""
    }

    private func openNextWorkout() {
        route = "heute"
        tap(button(containing: "Nächste Einheit"), "Karte Nächste Einheit")
        route = "einheit"
        check(waitFast(text(containing: "Zeit in Zonen")), "Detail öffnet")
    }

    private func adjustTo45EasierBy5() -> (before: String, after: String) {
        let before = durationValue()
        let adjust = scrollUntilExists(app.buttons["workout.adjust"])
        check(adjust.exists, "Button „Anpassen“ bei geplanter Einheit")
        check(adjust.frame.height >= 44, "Anpassen-Button mindestens 44 pt hoch")
        tap(adjust, "Anpassen")
        route = "anpassen"
        let chosen = ["adjust.minutes.45", "adjust.minutes.30"].first { app.buttons[$0].waitForExistence(timeout: 3) }
        check(chosen != nil, "Kürzer-Optionen vorhanden")
        shot("sheet-open")
        if let chosen { tap(app.buttons[chosen], chosen) }
        tap(app.buttons["adjust.easier.5"], "−5 %")
        let preview = element("workout.adjust.preview")
        check(preview.waitForExistence(timeout: 3), "Live-Vorschau sichtbar")
        check(preview.label.contains("Dauer") && preview.label.contains("TSS") && preview.label.contains("→"),
              "Vorschau zeigt Dauer und TSS vorher → nachher: \(preview.label)")
        shot("sheet-preview")
        accessibilityAudit("Anpassen-Sheet")
        tap(app.buttons["workout.adjust.apply"], "Übernehmen")
        route = "einheit"
        check(waitForBanner(containing: "Einheit angepasst:"), "Banner „Einheit angepasst: …“")
        check(!app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Fehler'")).firstMatch.exists, "Kein Fehler-Banner")
        shot("after-adjust")
        let note = element("workout.adjust.note")
        check(scrollUntilExists(note).exists, "Hinweis „Angepasst · vorher …“ sichtbar")
        check(note.label.contains("Angepasst · vorher"), "Hinweistext: \(note.label)")
        app.swipeDown(); app.swipeDown()
        sleep(4) // banner fades out
        let after = durationValue()
        return (before, after)
    }

    func test35_AdjustWorkout() {
        launch()
        openNextWorkout()
        shot("detail-before")
        let (before, after) = adjustTo45EasierBy5()
        check(!before.isEmpty && before != after, "Dauer geändert: \(before) → \(after)")
        accessibilityAudit("Einheit-angepasst")

        let restore = scrollUntilExists(app.buttons["workout.adjust.restore"])
        check(restore.exists, "„Original wiederherstellen“ sichtbar")
        shot("note-row")
        tap(restore, "Original wiederherstellen")
        check(waitForBanner(containing: "Original wiederhergestellt"), "Banner nach dem Wiederherstellen")
        app.swipeDown(); app.swipeDown()
        sleep(1)
        check(durationValue() == before, "Originaldauer zurück: \(durationValue()) == \(before)")
        check(!element("workout.adjust.note").exists, "Hinweis nach dem Wiederherstellen weg")
        shot("restored")
    }

    func test35b_AdjustAfterMyWhooshSend() {
        launch(extra: ["-uiMyWhooshStub", "YES"])
        openNextWorkout()
        let send = scrollUntilExists(button(containing: "An MyWhoosh senden"))
        tap(send, "An MyWhoosh senden")
        check(waitForBanner(containing: "an MyWhoosh gesendet"), "Gesendet")
        sleep(4)
        app.swipeDown(); app.swipeDown()
        let (before, after) = adjustTo45EasierBy5()
        check(before != after, "Dauer geändert: \(before) → \(after)")
        check(button(containing: "In MyWhoosh aktualisieren").exists || scrollUntilExists(button(containing: "In MyWhoosh aktualisieren")).exists,
              "Weiterhin in MyWhoosh (ersetzt, kein Fehler)")
        shot("after-replace")
    }
}
