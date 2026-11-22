import XCTest

/// B1 – Gipfelmoment (docs/22). `-uiMoment levelUp|record|comeback|week` löst einen Beispiel-Moment aus (nur DEBUG).
@MainActor
final class AuditMomentsTests: AuditCase {
    private func launchMoment(_ kind: String, extra: [String] = []) {
        launch(extra: BegeisterungLaunch.moment(kind) + extra)
    }

    private var sheet: XCUIElement { app.descendants(matching: .any)[BegeisterungID.momentSheet].firstMatch }
    private var headline: XCUIElement { app.staticTexts[BegeisterungID.momentHeadline] }

    func test60_LevelUpShowsHeadlineCoachNoteShareAndCloses() {
        launchMoment("levelUp")
        check(sheet.waitForExistence(timeout: 12), "Feier erscheint von selbst")
        check(headline.waitForExistence(timeout: 3) && headline.label.contains("Level 4"), "Überschrift Level 4")
        check(app.descendants(matching: .any)[BegeisterungID.postcardView].firstMatch.exists, "Postkarte")
        check(app.descendants(matching: .any)[BegeisterungID.momentCoachNote].firstMatch.exists, "Coach-Notiz mit Quelle")
        check(app.staticTexts["moment.example"].exists, "Hinweis „Beispiel mit Demo-Daten“")
        check(app.buttons[BegeisterungID.momentShare].exists, "Teilen vorhanden")
        shot("levelup")
        let next = app.buttons[BegeisterungID.momentContinue]
        scrollTo(next)
        tap(next, "Weiter")
        check(!sheet.waitForExistence(timeout: 2), "Weiter schließt")
        // kein zweites Mal: in den Hintergrund und zurück
        XCUIDevice.shared.press(.home)
        app.activate()
        check(!sheet.waitForExistence(timeout: 7), "Kein zweites Mal nach Wiederaktivieren")
    }

    func test61_RecordCloseButton() {
        launchMoment("record")
        check(sheet.waitForExistence(timeout: 12), "Feier Bestleistung")
        check(headline.label.contains("Bestleistung"), "Überschrift Bestleistung")
        check(app.descendants(matching: .any)["moment.values"].firstMatch.exists, "Schalter Werte zeigen")
        tap(app.buttons["moment.close"], "Schließen")
        check(!sheet.waitForExistence(timeout: 2), "Schließen")
    }

    func test62_ComebackAndWeek() {
        launchMoment("comeback")
        check(sheet.waitForExistence(timeout: 12) && headline.label.contains("zurück"), "Comeback")
        launchMoment("week")
        check(sheet.waitForExistence(timeout: 12) && headline.label.contains("Plan der Woche"), "Woche geschafft")
    }

    func test63_MatrixAX5DarkAudit() {
        launchMoment("levelUp", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                       "-AppleInterfaceStyle", "Dark"])
        check(sheet.waitForExistence(timeout: 12), "Feier bei AX5 dunkel")
        let next = app.buttons[BegeisterungID.momentContinue]
        scrollTo(next)
        check(next.exists, "Weiter bei AX5 erreichbar")
        shot("ax5-dark")
        accessibilityAudit("Gipfelmoment AX5 dunkel")
    }
}
