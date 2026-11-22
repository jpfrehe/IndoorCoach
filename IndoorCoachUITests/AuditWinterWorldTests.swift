import XCTest

/// Agent B · Winterwelt (docs/22, B2–B4): Postkarten-Album, Winterlicht, Willkommen zurück, Dein Warum.
/// Startschalter: `-uiSeed demo` plus `-uiToday yyyy-MM-dd` (nur DEBUG, setzt „heute“ für die neuen Funktionen).
final class AuditWinterWorldTests: AuditCase {
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openWinterArc() {
        route = "heute"
        tap(scrollUntilExists(button(containing: "Winter Arc")), "Winter-Arc-Karte")
        route = "winterarc"
        check(waitFast(app.navigationBars["Winter Arc"]), "Winter-Arc-Hub öffnet")
        settle()
    }

    // MARK: B2 Postkarten

    func test70_PostcardAlbum() {
        launch(extra: BegeisterungLaunch.today("2027-01-10"))
        openWinterArc()
        let album = scrollUntilExists(element(BegeisterungID.postcardAlbum))
        check(album.exists, "Album (postcard.album) im Hub")
        shot("album")
        let first = scrollUntilExists(element("postcard.tile.1"))
        tap(first, "Karte 1 (Garmisch)")
        check(element(BegeisterungID.postcardView).waitForExistence(timeout: 5), "Karte groß sichtbar (postcard.view)")
        check(element(BegeisterungID.postcardView).label.contains("Garmisch"), "Karte nennt den Ort")
        check(element(BegeisterungID.postcardShare).waitForExistence(timeout: 5), "Teilen (postcard.share) vorhanden")
        shot("card-open")
        accessibilityAudit("Postkarte")
        // Zur gesperrten Karte wischen: Sie nennt „noch nicht erreicht“.
        for _ in 0..<9 { app.swipeLeft() }
        let locked = element(BegeisterungID.postcardView)
        check(locked.waitForExistence(timeout: 3) && locked.label.contains("Noch nicht erreicht"), "Letzte Karte ist gesperrt: \(locked.label)")
        shot("card-locked")
        tap(app.buttons["postcard.done"], "Fertig")
        // Die nächste gesperrte Karte nennt den Prozentwert.
        // Das Raster lädt träge: die gesperrte Kachel erst in den Bildschirm scrollen.
        let lockedQuery = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Prozent bis'")).firstMatch
        // Nach „Fertig“ kann das Album über oder unter der Bildschirmmitte liegen: erst nach oben, dann nach unten suchen.
        var upSwipes = 0
        while !lockedQuery.waitForExistence(timeout: 1) && upSwipes < 3 { app.swipeDown(); upSwipes += 1 }
        let lockedTile = lockedQuery.exists ? lockedQuery : scrollUntilExists(lockedQuery)
        check(lockedTile.exists, "Eine gesperrte Kachel nennt „noch n Prozent bis …“")
    }

    // MARK: B3 Winterlicht

    /// Die Hub-Zeile trägt ein gesprochenes Label („17 Minuten mehr Tageslicht …“), die Heute-Karte den Chip („+17 min Licht“):
    /// beide Schreibweisen sind richtig.
    private func winterlight(_ day: String, expects: [String], label: String) {
        launch(extra: BegeisterungLaunch.today(day))
        route = "heute"
        let arc = scrollUntilExists(button(containing: "Winter Arc"))
        let combined = arc.label
        check(expects.contains { combined.contains($0) }, "\(label): Heute-Karte nennt das Licht (\(combined))")
        openWinterArc()
        let line = scrollUntilExists(element(BegeisterungID.winterlightLine))
        check(line.exists && expects.contains { line.label.contains($0) }, "\(label): Hub-Zeile (\(line.label))")
        shot("winterlight-\(day)")
    }

    func test71_WinterlightJanuary() { winterlight("2027-01-10", expects: ["min Tageslicht", "min Licht", "Minuten mehr Tageslicht"], label: "Nach der Sonnenwende") }
    func test72_WinterlightSolstice() { winterlight("2026-12-21", expects: ["Wintersonnenwende", "Sonnenwende"], label: "Am 21.12.") }
    func test73_WinterlightBefore() { winterlight("2026-12-12", expects: ["Noch 9 Tage"], label: "Vor der Sonnenwende") }

    // MARK: B4 Willkommen zurück und Dein Warum

    func test74_ComebackAndWhy() {
        launch(extra: BegeisterungLaunch.today("2027-01-01"))
        openWinterArc()
        let field = scrollUntilExists(element(BegeisterungID.whyField))
        check(field.exists, "Dein Warum: Eingabefeld")
        type(field, "Im Mai die RTF mit Freunden", "Warum")
        tap(app.buttons["why.save"], "Speichern")
        back()
        route = "heute"
        let card = scrollUntilExists(element(BegeisterungID.comebackCard))
        check(card.exists, "Willkommen-zurück-Karte nach langer Pause")
        check(card.label.contains("Neues Jahr") || text(containing: "Neues Jahr").exists, "Neujahr ergänzt den Satz")
        check(text(containing: "Im Mai die RTF mit Freunden").exists, "Der eigene Satz kehrt wörtlich zurück")
        shot("comeback")
        accessibilityAudit("Willkommen zurück")
        tap(element(BegeisterungID.comebackStart), "Heute locker einsteigen")
        let adjust = app.buttons["adjust.minutes.30"].waitForExistence(timeout: 6)
        let swap = app.buttons["Tauschen"].waitForExistence(timeout: 1)
        let detail = text(containing: "Zeit in Zonen").waitForExistence(timeout: 3)
        check(adjust || swap || detail, "Startbare Einheit: Anpassen (30 min), Tausch oder Grundlage-Detail")
        shot("comeback-start")
    }

    // MARK: Matrix: Dark und größte Schrift

    func test75_MatrixDarkAX5() {
        launch(extra: BegeisterungLaunch.today("2027-01-01") + ["-AppleInterfaceStyle", "Dark",
                                                                 "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        route = "heute"
        check(scrollUntilExists(element(BegeisterungID.comebackCard)).exists, "Karte bei AX5 sichtbar")
        shot("comeback-ax5-dark")
        accessibilityAudit("Willkommen zurück AX5 Dark")
        openWinterArc()
        check(scrollUntilExists(element(BegeisterungID.winterlightLine)).exists, "Winterlicht-Zeile bei AX5")
        shot("hub-ax5-dark")
        accessibilityAudit("Winter-Arc-Hub AX5 Dark")
    }
}
