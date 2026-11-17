import XCTest

/// UX-audit Phase 3 + 5: the five user threads and the scenario battery, walked with real taps and typing.
/// Persona: ambitious amateur road cyclist, trains indoors with MyWhoosh, plans in the evening on the iPhone.
final class AuditWalkthroughTests: AuditCase {

    // MARK: Thread 1 – Morgens kurz reinschauen: Was steht heute an?

    func test01_Thread1_TodayToWorkout() {
        launch()
        route = "heute"
        shot("default")
        check(text(containing: "Nächste Einheit").exists, "Karte „Nächste Einheit“ sichtbar ohne Scrollen")
        check(text(containing: "Demo-Modus").exists, "Demo-Hinweis sichtbar")
        accessibilityAudit("Heute")

        app.swipeUp()
        log("Swiped up on dashboard")
        shot("scrolled")
        check(text(containing: "Wochenumfang").exists, "Wochenumfang-Karte erreichbar")
        app.swipeDown()
        app.swipeDown()
        log("Swiped back to top")

        // Pull-to-refresh in demo mode: does anything tell me nothing happened?
        app.swipeDown(velocity: .fast)
        log("Pull-to-refresh on Heute")
        shot("after-refresh")

        let card = button(containing: "Nächste Einheit")
        let start = Date()
        tap(card, "Karte Nächste Einheit")
        route = "einheit"
        let detailVisible = waitFast(text(containing: "Zeit in Zonen"))
        timing("Karte → Detail", ms(since: start))
        check(detailVisible, "Detail öffnet nach Tap auf die Karte")
        shot("detail-top")
        accessibilityAudit("Einheit-Detail")
        app.swipeUp()
        app.swipeUp()
        log("Scrolled detail to bottom")
        shot("detail-bottom")
        check(button(containing: "In Kalender eintragen").exists || button(containing: "Kalender aktualisieren").exists,
              "Kalender-Button am Ende des Details")
        back()
        route = "heute"
        check(app.navigationBars["Heute"].waitForExistence(timeout: 3), "Zurück landet auf Heute")

        tap(button(containing: "Zum Profil"), "Demo-Hinweis → Zum Profil")
        route = "profil"
        check(app.navigationBars["Profil"].waitForExistence(timeout: 3), "„Zum Profil“ wechselt in den Profil-Tab")
        shot("via-demo-hint")
    }

    // MARK: Thread 2 – Sonntagabend: nächste Woche planen

    func test02_Thread2_PlanNextWeek() {
        launch()
        openTab("Plan")
        let rowsBefore = rowCount
        log("Counted plan rows", "cells=\(rowsBefore)")
        shot("default")
        accessibilityAudit("Plan")

        tap(app.navigationBars.buttons["Planen"], "Toolbar Planen")
        _ = waitFast(app.navigationBars["Neuer Plan"])
        route = "planer"
        check(app.navigationBars["Neuer Plan"].waitForExistence(timeout: 4), "Planer-Sheet öffnet")
        shot("default")
        accessibilityAudit("Planer")

        tap(app.buttons["14 Tage"], "Segment 14 Tage")
        let range = text(containing: "–")
        log("Read range label", selector(range))

        let toggle = app.switches["Ab heute planen"]
        if toggle.waitForExistence(timeout: 3) {
            toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            log("Toggled Ab heute planen", selector(toggle) + " value=\(toggle.value ?? "?")")
        } else {
            check(false, "Toggle „Ab heute planen“ nicht gefunden")
        }

        let wish = input(placeholder: "Mittwoch")
        type(wish, "Mittwoch nur 45 Minuten, Fokus VO₂max", "Wunschfeld")
        shot("wish-typed")

        let create = button(containing: "Demo-Plan erstellen")
        check(create.exists && create.isHittable, "Primäraktion „Demo-Plan erstellen“ ohne Scrollen erreichbar (Tastatur offen)")
        _ = scrollUntilExists(create)
        shot("create-reached")
        let start = Date()
        tap(create, "Demo-Plan erstellen")
        let proposal = waitFast(app.navigationBars["Vorschlag"], timeout: 10)
        timing("Planen → Vorschlag", ms(since: start))
        check(proposal, "Vorschlag erscheint")
        route = "vorschlag"
        shot("proposal-top")
        accessibilityAudit("Vorschlag")
        let proposalDays = app.staticTexts.allElementsBoundByIndex.map(\.label)
            .filter { $0.range(of: #"^(Mo|Di|Mi|Do|Fr|Sa|So)\. \d"#, options: .regularExpression) != nil || $0 == "Heute" || $0 == "Morgen" }
        log("Proposal day labels", proposalDays.joined(separator: " / "))
        app.swipeUp()
        shot("proposal-scrolled")

        tap(button(containing: "Übernehmen & in Kalender"), "Übernehmen & in Kalender")
        route = "plan"
        let closed = waitFast(app.navigationBars["Plan"], timeout: 6)
            && !app.navigationBars["Vorschlag"].exists && !app.navigationBars["Neuer Plan"].exists
        check(closed, "Sheet schließt nach Übernehmen")
        let bannerShown = waitForBanner(containing: "Kalender")
        check(bannerShown, "Bestätigung nach Übernehmen sichtbar")
        shot("after-accept")

        // Collect all plan rows (list is lazy → scroll) and look for two workouts on the same day.
        var labels = Set<String>()
        for _ in 0..<5 {
            app.collectionViews.buttons.matching(NSPredicate(format: "label CONTAINS 'TSS'")).allElementsBoundByIndex
                .forEach { labels.insert($0.label) }
            app.swipeUp(velocity: .slow)
        }
        let days = labels.compactMap { $0.components(separatedBy: ", ").dropFirst().first }
        let duplicates = Dictionary(grouping: days, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        log("Plan rows after accept", "\(labels.count) rows; days: \(days.sorted().joined(separator: " / "))")
        check(labels.count > rowsBefore, "Liste zeigt neue Einheiten (\(rowsBefore) → \(labels.count))")
        check(duplicates.isEmpty, "Keine zwei Einheiten am selben Tag (doppelt: \(duplicates.joined(separator: ", ")))")
        shot("after-accept-scrolled")
    }

    // MARK: Thread 3 – Einheit nach MyWhoosh bringen

    func test03_Thread3_WorkoutToMyWhoosh() {
        launch()
        openTab("Plan")
        let firstRow = row(0)
        let title = firstRow.label
        tap(firstRow, "Erste Einheit im Plan")
        route = "einheit"
        shot("default")

        let calendar = button(containing: "In Kalender eintragen")
        tap(calendar, "In Kalender eintragen")
        check(waitForBanner(containing: "Kalender"), "Banner nach Kalender-Eintrag")
        check(button(containing: "Kalender aktualisieren").waitForExistence(timeout: 3),
              "Button wechselt zu „Kalender aktualisieren“")
        shot("after-calendar")

        let export = button(containing: "MyWhoosh exportieren")
        tap(export, "Für MyWhoosh exportieren (.zwo)")
        let sheet = app.otherElements["ActivityListView"].waitForExistence(timeout: 6)
            || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 2)
        check(sheet, "Teilen-Sheet öffnet sich")
        route = "teilen"
        shot("share-sheet")
        let close = app.buttons["Schließen"].exists ? app.buttons["Schließen"] : app.buttons["Close"]
        if close.exists { tap(close, "Teilen-Sheet schließen") } else {
            app.swipeDown(velocity: .fast)
            log("Swiped share sheet down")
        }
        route = "einheit"

        // Status über das ⋯-Menü ändern
        let menu = app.navigationBars.buttons.element(boundBy: app.navigationBars.buttons.count - 1)
        log("Menu button", selector(menu))
        tap(menu, "⋯-Menü")
        shot("menu-open")
        tap(app.buttons["Erledigt"], "Status Erledigt")
        check(text(containing: "Erledigt").waitForExistence(timeout: 3), "Status „Erledigt“ im Detail sichtbar")
        back()
        route = "plan"
        shot("after-status")
        let name = title.components(separatedBy: ", ").first ?? title
        let doneRow = app.collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        check(doneRow.exists, "Erledigte Einheit noch in der Liste (\(name))")
        log("Row after status change", doneRow.exists ? selector(doneRow) : "-")
    }

    // MARK: Thread 4 – Rückblick: Wie lief der letzte Monat?

    func test04_Thread4_History() {
        launch()
        openTab("Verlauf")
        shot("default")
        accessibilityAudit("Verlauf")
        let allCount = rowCount

        tap(app.buttons["Indoor"], "Filter Indoor")
        let indoorCount = rowCount
        check(!text(containing: "Sonntagsrunde").exists, "Indoor-Filter blendet Outdoor-Fahrten aus")
        shot("indoor")
        tap(app.buttons["Outdoor"], "Filter Outdoor")
        let outdoorCount = rowCount
        log("Counted rows", "alle=\(allCount) indoor=\(indoorCount) outdoor=\(outdoorCount)")
        shot("outdoor")

        let metricMenu = button(containing: "Metrik, Stunden")
        if metricMenu.exists {
            tap(metricMenu, "Metrik-Menü (Stunden)")
            let tssItem = [app.buttons["TSS"], app.menuItems["TSS"]].first { $0.waitForExistence(timeout: 2) } ?? app.buttons["TSS"]
            tap(tssItem, "Metrik TSS")
            _ = waitFast(app.buttons["Metrik, TSS"], timeout: 3)
            check(app.buttons["Metrik, TSS"].exists, "Metrik zeigt TSS")
            sleep(1) // menu dismissal animation
        } else {
            let tssSegment = app.segmentedControls.buttons["TSS"]
            log("Metric segment frame", "\(tssSegment.frame)")
            tap(tssSegment, "Metrik-Segment TSS")
            usleep(500_000)
            check(tssSegment.isSelected, "Metrik zeigt TSS nach einem Tap")
            if !tssSegment.isSelected {
                tssSegment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                log("Tapped TSS segment by coordinate", "\(tssSegment.frame)")
                usleep(500_000)
                check(tssSegment.isSelected, "Metrik zeigt TSS nach Koordinaten-Tap")
            }
        }
        shot("metric-tss")

        let ride = row(0)
        tap(ride, "Erste Fahrt")
        _ = waitFast(app.navigationBars.buttons["BackButton"], timeout: 4)
        route = "fahrt"
        shot("detail")
        accessibilityAudit("Fahrt-Detail")
        back()
        route = "verlauf"
        check(app.buttons["Outdoor"].isSelected, "Filter bleibt nach Zurück erhalten")
        shot("after-back")
    }

    // MARK: Thread 5 – Profil einrichten (erster Abend)

    func test05_Thread5_ProfileSetup() {
        launch()
        openTab("Profil")
        shot("default")
        accessibilityAudit("Profil")

        let ftp = app.steppers.firstMatch
        tap(ftp.buttons.element(boundBy: 1), "FTP +5")
        check(text(containing: "255 W").exists, "FTP steigt auf 255 W")

        let goal = input(placeholder: "FTP steigern")
        type(goal, " – Ötztaler Radmarathon '27 🚴", "Zielfeld")
        shot("goal-typed")

        tap(app.buttons["Montag"], "Trainingstag Montag")
        check(app.buttons["Montag"].isSelected, "Montag ist als gewählt markiert")

        // Close the goal keyboard first (Form does not scroll the key field into view while it is up).
        if app.keyboards.firstMatch.exists { app.swipeDown(velocity: .fast) }
        let key = scrollUntilExists(app.secureTextFields.firstMatch, maxSwipes: 12)
        log("Keyboard after goal", app.keyboards.firstMatch.exists ? "offen" : "zu")
        type(key, "sk-ant-short", "API-Key-Feld (zu kurz)")
        let save = app.buttons["API-Key speichern"]
        check(save.exists && !save.isEnabled, "Speichern bei zu kurzem Key deaktiviert")
        shot("key-short")
        let keyField = app.secureTextFields.firstMatch
        keyField.tap()
        keyField.typeText("-TESTKEY-not-real-0000000000")
        log("Typed more into API-Key-Feld", selector(keyField))
        check(save.isEnabled, "Speichern bei langem Key aktiv")
        tap(save, "API-Key speichern")
        check(text(containing: "Gespeichert").waitForExistence(timeout: 3), "„Gespeichert“ nach Key-Speichern")
        shot("key-saved")
        tap(app.buttons["API-Key entfernen"], "API-Key entfernen")
        check(app.secureTextFields.firstMatch.waitForExistence(timeout: 3), "Key-Feld wieder leer nach Entfernen")

        _ = scrollUntilExists(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Strava verbinden'")).firstMatch)
        let clientID = input(placeholder: "Client-ID")
        type(clientID, "12345", "Strava Client-ID")
        let secret = input(placeholder: "Client-Secret")
        type(secret, "test-secret-value", "Strava Client-Secret")
        let connect = button(containing: "Mit Strava verbinden")
        check(connect.exists && connect.isEnabled, "Verbinden-Button aktiv mit ID + Secret")
        shot("strava-filled")
        accessibilityAudit("Profil-ausgefüllt")

        // Round trip: Trainingstage im Planer
        openTab("Plan")
        let planen = app.navigationBars.buttons["Planen"]
        log("Planen nach Profil", "exists=\(planen.exists) hittable=\(planen.isHittable) keyboard=\(app.keyboards.firstMatch.exists)")
        shot("before-planen")
        let savePassword = app.staticTexts["Passwort sichern?"].waitForExistence(timeout: 3)
            || text(containing: "Passwort sichern").exists
        check(!savePassword && planen.isHittable, "Kein „Passwort sichern?“-Dialog nach Strava-/Key-Eingabe")
        tap(planen, "Toolbar Planen")
        _ = waitFast(app.navigationBars["Neuer Plan"])
        route = "planer"
        check(text(containing: "Mo,").waitForExistence(timeout: 3) || text(containing: "Mo").exists,
              "Planer zeigt Montag als Trainingstag")
        shot("days-roundtrip")
        tap(app.buttons["Abbrechen"], "Planer abbrechen")

        // Returning user: persistiert das Profil über einen Neustart?
        app.terminate()
        log("Terminated app")
        launch(seed: nil)
        openTab("Profil")
        check(text(containing: "255 W").exists, "FTP 255 W überlebt Neustart")
        check(app.buttons["Montag"].isSelected, "Montag überlebt Neustart")
        shot("after-relaunch")
    }

    // MARK: Scenario – Destructive confidence

    func test06_Scenario_DestructiveActions() {
        launch()
        openTab("Plan")
        let before = rowCount
        let firstRow = row(0)
        let title = firstRow.label
        firstRow.swipeLeft()
        log("Swiped left on first plan row", selector(firstRow))
        shot("swipe-actions")
        tap(app.buttons["Löschen"], "Swipe-Aktion Löschen")
        let asks = text(containing: "Einheit löschen?").waitForExistence(timeout: 2)
        check(asks, "Swipe-Löschen fragt nach, bevor Einheit (und Kalendereintrag) verschwinden (\(title))")
        shot("swipe-delete-confirm")
        if asks {
            let confirm = app.buttons.matching(NSPredicate(format: "label == 'Löschen'")).allElementsBoundByIndex.last ?? app.buttons["Löschen"]
            tap(confirm, "Löschen bestätigen (Swipe)")
        }
        _ = waitFast(app.navigationBars["Plan"])
        sleep(1) // row removal animation
        let after = rowCount
        log("Counted rows", "before=\(before) after=\(after)")
        check(after == before - 1, "Liste zeigt eine Einheit weniger (\(before) → \(after))")
        shot("after-swipe-delete")

        tap(row(0), "Nächste Einheit öffnen")
        route = "einheit"
        let menu = app.navigationBars.buttons.element(boundBy: app.navigationBars.buttons.count - 1)
        tap(menu, "⋯-Menü")
        tap(app.buttons["Löschen"], "Menü Löschen")
        check(app.sheets.firstMatch.waitForExistence(timeout: 2) || text(containing: "Einheit löschen?").exists,
              "Lösch-Bestätigung erscheint")
        shot("delete-confirm")
        let confirm = app.sheets.buttons["Löschen"].exists ? app.sheets.buttons["Löschen"] : app.buttons.matching(identifier: "Löschen").element(boundBy: 0)
        tap(confirm, "Löschen bestätigen")
        route = "plan"
        check(app.navigationBars["Plan"].waitForExistence(timeout: 4), "Nach Löschen zurück im Plan")
        shot("after-detail-delete")
    }

    // MARK: Scenario – Leerer Zustand (Tag 0)

    func test07_Scenario_EmptyState() {
        launch(seed: "empty")
        route = "heute"
        shot("empty")
        accessibilityAudit("Heute-leer")
        check(text(containing: "Nichts geplant").exists, "Leerzustand „Nichts geplant“")
        tap(button(containing: "Plan erstellen"), "Plan erstellen (Leerzustand)")
        route = "planer"
        check(waitFast(app.navigationBars["Neuer Plan"], timeout: 5), "„Plan erstellen“ öffnet direkt den Planer")
        shot("empty-context")
        check(!text(containing: "Form (TSB)").exists, "Planer ohne Fahrten blendet Form/Fitness = 0 aus")
        let create = button(containing: "Demo-Plan erstellen")
        check(create.exists && create.isHittable, "Primäraktion ohne Scrollen sichtbar")
        tap(create, "Demo-Plan erstellen (ohne Fahrten)")
        check(waitFast(app.navigationBars["Vorschlag"], timeout: 8), "Vorschlag auch ohne Fahrten")
        route = "vorschlag"
        shot("empty-proposal")
        tap(app.buttons["Abbrechen"], "Vorschlag abbrechen")
        route = "plan"
        _ = waitFast(app.navigationBars["Plan"])
        shot("empty")
        check(button(containing: "Plan erstellen").exists, "Leerer Plan bietet „Plan erstellen“-Button")
        openTab("Verlauf")
        shot("empty")
        accessibilityAudit("Verlauf-leer")
    }

    // MARK: Scenario – Unterbrochener Workflow

    func test08_Scenario_InterruptedPlanning() {
        launch()
        openTab("Plan")
        tap(app.navigationBars.buttons["Planen"], "Toolbar Planen")
        _ = waitFast(app.navigationBars["Neuer Plan"])
        route = "planer"
        let wish = input(placeholder: "Mittwoch")
        type(wish, "Freitag frei", "Wunschfeld")
        XCUIDevice.shared.press(.home)
        log("Pressed Home (app in background)")
        app.activate()
        log("Re-activated app")
        let kept = app.textFields.matching(NSPredicate(format: "value CONTAINS 'Freitag frei'")).firstMatch.waitForExistence(timeout: 3)
        check(kept, "Wunschtext übersteht Hintergrund")
        shot("after-background")

        app.terminate()
        log("Terminated app mid-planning")
        launch(seed: nil)
        route = "heute"
        shot("after-relaunch")
        check(app.navigationBars["Heute"].exists, "Neustart landet auf Heute (Planer-Entwurf verloren)")
    }

    // MARK: Scenario – Falsche Abzweigung

    func test09_Scenario_WrongTurnRecovery() {
        launch()
        openTab("Plan")
        tap(app.navigationBars.buttons["Planen"], "Toolbar Planen (versehentlich)")
        route = "planer"
        tap(app.buttons["Abbrechen"], "Abbrechen")
        route = "plan"
        check(app.navigationBars["Plan"].waitForExistence(timeout: 3), "Abbrechen schließt den Planer (1 Tap)")

        tap(app.navigationBars.buttons["Planen"], "Toolbar Planen")
        _ = waitFast(app.navigationBars["Neuer Plan"])
        route = "planer"
        tap(button(containing: "Demo-Plan erstellen"), "Demo-Plan erstellen")
        _ = app.navigationBars["Vorschlag"].waitForExistence(timeout: 8)
        route = "vorschlag"
        tap(app.buttons["Neu planen"], "Neu planen")
        check(app.navigationBars["Neuer Plan"].waitForExistence(timeout: 3), "„Neu planen“ führt zurück zum Formular")
        shot("after-replan")
        app.swipeDown(velocity: .fast)
        log("Swiped planner sheet down")
        route = "plan"
        check(app.navigationBars["Plan"].waitForExistence(timeout: 3), "Sheet per Wischgeste schließbar")

        // Secondary toolbar action discoverability
        let more = app.navigationBars["Plan"].buttons["Weitere"]
        log("Plan toolbar last button", selector(more))
        tap(more, "Toolbar-Überlauf")
        shot("toolbar-overflow")
        check(button(containing: "Alle in Kalender").exists, "„Alle in Kalender“ im Überlauf-Menü")
        if button(containing: "Alle in Kalender").exists {
            tap(button(containing: "Alle in Kalender"), "Alle in Kalender")
            check(waitForBanner(containing: "Kalender"), "Banner nach Alle in Kalender")
            shot("after-all-calendar")
        }
    }

    // MARK: Scenario – Viele Daten (2 Jahre Fahrten)

    func test10_Scenario_HeavyData() {
        launch(seed: "heavy")
        route = "heute"
        shot("heavy")
        openTab("Verlauf")
        let t2 = Date()
        tap(app.buttons["Indoor"], "Filter Indoor (viele Daten)")
        _ = row(0).waitForExistence(timeout: 3)
        timing("Filterwechsel bei vielen Daten", ms(since: t2))
        shot("heavy-indoor")
        tap(app.buttons["Alle"], "Filter Alle (viele Daten)")
        let start = Date()
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        timing("12 schnelle Swipes im Verlauf", ms(since: start))
        log("Fast-scrolled history 12×")
        shot("heavy-scrolled")
        openTab("Heute")
        shot("heavy-today")
    }

    // MARK: Regression – Metrik-Segment im Verlauf reagiert auf den ersten Tap

    func test12_MetricSegmentFirstTap() {
        launch()
        openTab("Verlauf")
        let tss = app.segmentedControls.buttons["TSS"]
        let hours = app.segmentedControls.buttons["Stunden"]
        tap(tss, "TSS (direkt nach Öffnen)")
        usleep(600_000)
        check(tss.isSelected, "TSS nach erstem Tap gewählt (frischer Screen)")
        tap(hours, "Stunden")
        usleep(600_000)
        check(hours.isSelected, "Stunden nach erstem Tap gewählt")
        tap(app.buttons["Outdoor"], "Filter Outdoor")
        usleep(600_000)
        tap(tss, "TSS (nach Filterwechsel)")
        usleep(600_000)
        check(tss.isSelected, "TSS nach erstem Tap gewählt (nach Filterwechsel)")
        shot("metric-after-filter")
    }

    // MARK: Regression – Strava-Felder nehmen Eingaben an, kein „Passwort sichern?“

    func test13_StravaCredentialsInput() {
        launch()
        openTab("Profil")
        let clientID = scrollUntilExists(app.textFields["Client-ID"], maxSwipes: 12)
        if !clientID.isHittable { app.swipeUp(velocity: .slow) }
        print("CLIENTID-DEBUG enabled=\(clientID.isEnabled) hittable=\(clientID.isHittable) frame=\(clientID.frame) value=\(clientID.value ?? "nil")")
        shot("before-clientid-tap")
        clientID.tap()
        shot("after-clientid-tap")
        let focusedCenter = app.keyboards.firstMatch.waitForExistence(timeout: 2)
        log("Tapped Client-ID (Zeilenmitte)", "keyboard=\(focusedCenter)")
        if !focusedCenter {
            clientID.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            log("Tapped Client-ID (rechts, auf dem Platzhalter)", "keyboard=\(app.keyboards.firstMatch.waitForExistence(timeout: 2))")
        }
        check(app.keyboards.firstMatch.exists, "Client-ID-Feld bekommt Fokus")
        clientID.typeText("54321")
        log("Typed \"54321\" into Strava Client-ID (frisch)", selector(clientID))
        check((clientID.value as? String)?.contains("54321") == true, "Client-ID übernimmt Eingabe")
        let secret = app.secureTextFields["Client-Secret"]
        type(secret, "abc123secret\n", "Strava Client-Secret (frisch) + Return")
        shot("strava-typed")
        openTab("Plan")
        let blocked = app.staticTexts["Passwort sichern?"].waitForExistence(timeout: 4)
        shot("after-leaving-profile")
        check(!blocked, "Kein „Passwort sichern?“-Dialog nach Verlassen des Profils")
        tap(app.navigationBars.buttons["Planen"], "Toolbar Planen")
        check(waitFast(app.navigationBars["Neuer Plan"], timeout: 4), "Planer öffnet nach Profil-Eingaben")
    }

    // MARK: Winter-Arc-Features (S10–S12)

    func test14_WinterArcFeatures() {
        launch()
        route = "heute"
        let arcCard = button(containing: "Winter Arc")
        check(scrollUntilExists(arcCard, maxSwipes: 3).exists, "Winter-Arc-Karte auf Heute")
        shot("arc-card")
        tap(arcCard, "Winter-Arc-Karte")
        route = "winterarc"
        check(waitFast(app.navigationBars["Winter Arc"]), "Winter-Arc-Detail öffnet")
        check(text(containing: "Level-Pfad").exists || scrollUntilExists(text(containing: "Level-Pfad")).exists, "Level-Pfad sichtbar")
        shot("detail")
        accessibilityAudit("WinterArc")
        app.swipeUp()
        shot("detail-scrolled")
        back()

        route = "heute"
        let formCard = button(containing: "Fitness & Form")
        _ = scrollUntilExists(formCard, maxSwipes: 4)
        tap(formCard, "Karte Fitness & Form")
        route = "fitness"
        check(waitFast(app.navigationBars["Fitness & Form"]), "Fitness-&-Form-Screen öffnet")
        tap(app.buttons["30 T"], "Zeitraum 30 Tage")
        check(app.buttons["30 T"].isSelected, "30 Tage gewählt")
        shot("range-30")
        let chart = app.otherElements["Verlauf von Fitness und Ermüdung"].firstMatch
        if chart.exists {
            chart.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            log("Tapped chart day", selector(chart))
            check(!text(containing: "Fitness in 7 Tagen").exists, "Tap auf einen Tag zeigt dessen Werte statt „Heute“")
        }
        shot("day-selected")
        accessibilityAudit("FitnessFreshness")
        back()

        openTab("Verlauf")
        check(text(containing: "Relative Effort · diese Woche").waitForExistence(timeout: 3), "Relative-Effort-Wochenkarte im Verlauf")
        shot("effort-week")
        tap(row(0), "Erste Fahrt")
        route = "fahrt"
        let reTitle = scrollUntilExists(text(containing: "Relative Effort"))
        check(reTitle.exists, "Relative-Effort-Karte im Fahrt-Detail")
        let peToggle = scrollUntilExists(app.switches["Gefühlte Anstrengung angeben"])
        peToggle.switches.firstMatch.exists ? peToggle.switches.firstMatch.tap() : peToggle.tap()
        log("Toggled PE", selector(peToggle))
        let slider = app.sliders.firstMatch
        if slider.waitForExistence(timeout: 2) {
            slider.adjust(toNormalizedSliderPosition: 0.85)
            log("Adjusted PE slider", selector(slider))
        }
        check(text(containing: "Sehr hart").exists || text(containing: "Extrem hart").exists || text(containing: "Hart").exists,
              "PE-Beschriftung folgt dem Slider")
        shot("pe-set")
        accessibilityAudit("Fahrt-RE")
    }

    // MARK: Scenario – Kalender verweigert

    func test11_Scenario_CalendarDenied() {
        launch()
        openTab("Plan")
        tap(row(0), "Erste Einheit")
        route = "einheit"
        tap(button(containing: "In Kalender eintragen"), "In Kalender eintragen (Zugriff verweigert)")
        // System alert may appear on first request
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            shot("system-alert")
            let deny = alert.buttons.element(boundBy: 0)
            log("System alert buttons", alert.buttons.allElementsBoundByIndex.map(\.label).joined(separator: ","))
            deny.tap()
            log("Denied calendar access")
        }
        let error = text(containing: "Kalender").waitForExistence(timeout: 5)
        check(error, "Fehlermeldung bei verweigertem Kalenderzugriff")
        shot("denied")
    }
}

/// Phase 3 multi-pane stress equivalent for iPhone: every tab at default and large Dynamic Type,
/// run on the small and the large simulator. Screenshots + accessibility audit (incl. textClipped).
final class AuditMatrixTests: AuditCase {
    func testMatrix() {
        let sizes = ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityL"]
        for size in sizes {
            launch(extra: ["-UIPreferredContentSizeCategoryName", size])
            let tag = size == sizes[0] ? "L" : "AXL"
            for tab in ["Heute", "Plan", "Verlauf", "Profil"] {
                openTab(tab)
                shot("\(tag)-top")
                accessibilityAudit("\(tab)@\(tag)")
                app.swipeUp()
                shot("\(tag)-scrolled")
            }
            openTab("Plan")
            app.swipeDown(); app.swipeDown() // back to the top after the scrolled screenshot
            tap(row(0), "Erste Einheit")
            _ = waitFast(app.navigationBars.buttons["BackButton"], timeout: 4)
            route = "einheit"
            shot("\(tag)-top")
            accessibilityAudit("Einheit@\(tag)")
            app.swipeUp()
            shot("\(tag)-scrolled")
            app.terminate()
        }
    }
}

/// Phase 4 performance budget equivalent: cold launch and tab-switch latency.
final class AuditPerformanceTests: AuditCase {
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(de)"]
            app.launch()
        }
    }

    func testTabSwitchLatency() {
        launch()
        for _ in 0..<3 {
            for tab in ["Plan", "Verlauf", "Profil", "Heute"] { openTab(tab) }
        }
    }
}
