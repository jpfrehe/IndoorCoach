import XCTest

/// Hilfen für die Einführung in 7 Schritten (docs/20, §6 und Identifier-Vertrag §6.8).
/// Schritt-Nummern sind 0-basiert (0 Willkommen … 6 Alles bereit); die Seitenanzeige zeigt „Schritt n+1 von 7“.
extension AuditCase {
    func obEl(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Beliebiges Element (Karte, Knopf, Text) mit diesem Teil im Label.
    func anyText(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    var obIndicator: XCUIElement { app.otherElements["onboarding.pageIndicator"] }

    /// Der Hauptknopf der unteren Leiste, wie er gerade heißt (Weiter, Ohne Verbindung weiter, Ohne Claude weiter, …).
    func obBarButton() -> XCUIElement? {
        for id in ["onboarding.next", "onboarding.later", "onboarding.noClaude", "onboarding.start", "onboarding.tour", "onboarding.strava"] {
            let button = app.buttons[id]
            if button.exists { return button }
        }
        return nil
    }

    /// Wartet auf Titel und Seitenanzeige „Schritt n von 7“.
    func obExpect(step index: Int, title: String, timeout: TimeInterval = 8) {
        check(waitFast(text(containing: title), timeout: timeout), "Schritt \(index + 1): „\(title)“ sichtbar")
        let expected = "Schritt \(index + 1) von 7"
        let end = Date().addingTimeInterval(2)
        while obIndicator.label != expected && Date() < end { usleep(100_000) }
        check(obIndicator.label == expected, "Seitenanzeige „\(expected)“ (\(obIndicator.label))")
    }

    /// Tastatur schließen, damit die untere Leiste wieder da ist.
    func obDismissKeyboard() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        for name in ["Fertig", "Done", "Return", "return"] where keyboard.buttons[name].exists {
            keyboard.buttons[name].tap()
            break
        }
        if keyboard.exists {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        usleep(400_000)
    }

    /// Tippt den Hauptknopf der unteren Leiste, egal ob „Weiter“ (`onboarding.next`), „Ohne Verbindung weiter“
    /// (`onboarding.later`) oder „Ohne Claude weiter“ (`onboarding.noClaude`).
    @discardableResult
    func obAdvance(_ description: String = "Weiter") -> Bool {
        obDismissKeyboard()
        let end = Date().addingTimeInterval(8)
        while Date() < end {
            for id in ["onboarding.next", "onboarding.later", "onboarding.noClaude"] {
                let button = app.buttons[id]
                if button.exists, button.isHittable, button.isEnabled {
                    return tap(button, "\(description) (\(id))")
                }
            }
            usleep(150_000)
        }
        check(false, "Hauptknopf der unteren Leiste nicht gefunden: \(description)")
        return false
    }

    /// Tippt ein Element über seinen Identifier; scrollt es bei Bedarf ins Bild und aus der unteren Leiste (iPhone SE).
    @discardableResult
    func obTap(_ identifier: String, _ description: String) -> Bool {
        let element = obEl(identifier)
        if !element.waitForExistence(timeout: 4) { scrollFinding(element) }
        if element.exists, let bar = obBarButton() { lift(element, above: bar) }
        return tap(element, description)
    }

    func obSelected(_ identifier: String) -> Bool { obEl(identifier).isSelected }

    /// Wartet, bis Label oder Wert des Elements den Text enthalten (Groß-/Kleinschreibung egal).
    @discardableResult
    func obWaitLabel(_ element: XCUIElement, contains part: String, timeout: TimeInterval = 8) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        let needle = part.lowercased()
        while Date() < end {
            if element.exists {
                let haystack = "\(element.label) \((element.value as? String) ?? "")".lowercased()
                if haystack.contains(needle) { return true }
            }
            usleep(150_000)
        }
        return false
    }

    /// Schritt 1 „Dein Training“: einen Trainingstag wählen (sonst bleibt „Weiter“ deaktiviert).
    func obPickTrainingDay(_ day: String = "Montag") {
        let button = app.buttons[day]
        _ = button.waitForExistence(timeout: 6)
        if let bar = obBarButton() { lift(button, above: bar) }
        if !button.isSelected { tap(button, "Trainingstag \(day)") }
    }

    /// Willkommen → Training (Montag) → bis zum Schritt „Womit fährst du drinnen?“.
    func obWalkToQuestions() {
        obExpect(step: 0, title: "Willkommen bei IndoorCoach")
        tap(app.buttons["onboarding.next"], "Los geht’s")
        obExpect(step: 1, title: "Dein Training")
        obPickTrainingDay()
        obAdvance("Weiter")
        obExpect(step: 2, title: "Womit fährst du drinnen?")
    }

    /// Die Karten stehen in dieser Reihenfolge von oben nach unten.
    func obCheckOrder(_ identifiers: [String], _ label: String) {
        let positions = identifiers.map { obEl($0).frame.minY }
        let present = identifiers.allSatisfy { obEl($0).exists }
        let ordered = zip(positions, positions.dropFirst()).allSatisfy { $0 < $1 }
        check(present && ordered, "Reihenfolge \(label): \(positions.map { Int($0) })")
    }
}
