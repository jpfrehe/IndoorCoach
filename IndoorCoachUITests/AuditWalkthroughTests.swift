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
        check(app.navigationBars["Dienste & Geräte"].waitForExistence(timeout: 5), "„Zum Profil“ springt nach kurzer Pause zu „Dienste & Geräte“")
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
        // The success banner stays 3 s – look for it before the slower sheet checks.
        let bannerShown = waitForBanner(containing: "Kalender")
        let closed = waitFast(app.navigationBars["Plan"], timeout: 6)
            && !app.navigationBars["Vorschlag"].exists && !app.navigationBars["Neuer Plan"].exists
        check(closed, "Sheet schließt nach Übernehmen")
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

        // Seit dem Direkt-Upload (B21) steckt der .zwo-Export im aufklappbaren Bereich „Alternativ: .zwo-Datei“.
        let export = button(containing: "MyWhoosh exportieren")
        if !export.exists { tap(button(containing: "Alternativ: .zwo-Datei"), "Alternativ: .zwo-Datei aufklappen") }
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
            // The glass segment animates for ~0.5 s; wait for the selected state instead of a fixed sleep (audit 3).
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: tssSegment)
            _ = XCTWaiter.wait(for: [selected], timeout: 2)
            log("TSS-Segment nach Tap", tssSegment.debugDescription.replacingOccurrences(of: "\n", with: " ").prefix(200).description)
            check(tssSegment.isSelected || tssSegment.debugDescription.contains("Selected"), "Metrik zeigt TSS nach einem Tap")
            if !tssSegment.isSelected {
                tssSegment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                log("Tapped TSS segment by coordinate", "\(tssSegment.frame)")
                usleep(500_000)
                check(tssSegment.isSelected, "Metrik zeigt TSS nach Koordinaten-Tap")
            }
        }
        shot("metric-tss")

        let ride = scrollUntilExists(row(0))                       // rides sit below the "Leistung" section
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
        launch(extra: ["-uiClaudeStub", "YES"]) // key check runs against the stub
        openTab("Profil")
        shot("default")
        accessibilityAudit("Profil")

        let ftp = app.steppers.firstMatch
        tap(ftp.buttons.element(boundBy: 1), "FTP +5")
        check(text(containing: "255 W").exists, "FTP steigt auf 255 W")

        let goal = input(placeholder: "FTP steigern")
        type(goal, " – Ötztaler Radmarathon '27 🚴", "Zielfeld")
        shot("goal-typed")

        // The Form is lazy: scroll the training days into existence (they sit in "Verfügbarkeit" on the start page).
        // Audit 3: the profile keyboard has "Fertig" (Ziel is multi-line; on the SE the emoji keyboard covered the list).
        let done = app.buttons["keyboard.done"]
        check(done.exists, "Tastatur hat „Fertig“")
        if done.exists { tap(done, "Fertig") } else if app.keyboards.firstMatch.exists { app.swipeDown(velocity: .fast) }
        check(!app.keyboards.firstMatch.exists, "„Fertig“ schließt die Tastatur")
        tap(scrollUntilExists(app.buttons["Montag"], maxSwipes: 8), "Trainingstag Montag")
        check(app.buttons["Montag"].isSelected, "Montag ist als gewählt markiert")

        // Close the goal keyboard first (Form does not scroll the key field into view while it is up).
        if app.keyboards.firstMatch.exists { app.swipeDown(velocity: .fast) }
        // AP4: der Claude-Key liegt auf der Unterseite „Coach · Claude“.
        tap(scrollUntilExists(app.descendants(matching: .any)["profile.coach"].firstMatch), "Profil → Coach · Claude")
        let key = scrollUntilExists(app.secureTextFields.firstMatch, maxSwipes: 4)
        log("Keyboard after goal", app.keyboards.firstMatch.exists ? "offen" : "zu")
        type(key, "sk-ant-test", "API-Key-Feld (zu kurz)")
        let save = app.buttons["claude.key.save"]
        check(save.exists && !save.isEnabled, "Speichern bei zu kurzem Key deaktiviert")
        shot("key-short")
        let keyField = app.secureTextFields.firstMatch
        keyField.tap()
        keyField.typeText("-0000000000000000")
        log("Typed more into API-Key-Feld", selector(keyField))
        check(save.isEnabled, "Speichern bei langem Key aktiv")
        tap(save, "Prüfen & speichern")
        check(text(containing: "Gespeichert").waitForExistence(timeout: 3), "„Gespeichert“ nach Key-Speichern")
        shot("key-saved")
        tap(app.buttons["API-Key entfernen"], "API-Key entfernen")
        check(app.secureTextFields.firstMatch.waitForExistence(timeout: 3), "Key-Feld wieder leer nach Entfernen")
        back()

        // AP2: die Strava-Zugangsdaten liegen auf der Detailseite unter Dienste & Geräte.
        openService("profile.strava")
        check(waitFast(app.navigationBars["Strava"], timeout: 6), "Strava-Detailseite")
        let clientID = input(placeholder: "Client-ID")
        type(clientID, "12345", "Strava Client-ID")
        let secret = input(placeholder: "Client-Secret")
        type(secret, "test-secret-value", "Strava Client-Secret")
        let connect = button(containing: "Mit Strava verbinden")
        check(connect.exists && connect.isEnabled, "Verbinden-Button aktiv mit ID + Secret")
        shot("strava-filled")
        accessibilityAudit("Strava-ausgefüllt")

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
        check(scrollUntilExists(app.buttons["Montag"]).isSelected, "Montag überlebt Neustart")
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
        openService("profile.strava")
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
        // SE: close the Client-ID keyboard first, as a user would with "Fertig", so the tap lands on a still field.
        if app.buttons["keyboard.done"].exists { tap(app.buttons["keyboard.done"], "Fertig") }
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
        // The "Leistung" section sits above the rides; the list is lazy, so scroll the first ride into existence.
        tap(scrollUntilExists(row(0)), "Erste Fahrt")
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

    // MARK: MyWhoosh-Direktupload (B21) mit Stub-Konto

    func test17_MyWhooshDirectUpload() {
        launch(extra: ["-uiMyWhooshStub", "YES"])
        openTab("Plan")
        tap(row(0), "Erste Einheit")
        route = "einheit"
        let send = scrollUntilExists(button(containing: "An MyWhoosh senden"))
        check(send.exists, "Primäraktion „An MyWhoosh senden“ bei verbundenem Konto")
        shot("before-send")
        tap(send, "An MyWhoosh senden")
        check(waitForBanner(containing: "an MyWhoosh gesendet"), "Bestätigung nach dem Senden")
        check(button(containing: "In MyWhoosh aktualisieren").waitForExistence(timeout: 3), "Button wechselt zu „In MyWhoosh aktualisieren“")
        check(text(containing: "im MyWhoosh-Kalender").exists, "Status zeigt Eintrag im MyWhoosh-Kalender")
        shot("after-send")
        sleep(4) // let the confirmation banner fade out before auditing contrast
        check(!text(containing: "an MyWhoosh gesendet").exists, "Banner vor dem Audit ausgeblendet")
        shot("before-audit")
        accessibilityAudit("Einheit-MyWhoosh")
        let fallback = button(containing: "Alternativ: .zwo-Datei")
        check(fallback.exists, ".zwo bleibt als eingeklappte Alternative")
        openService("profile.mywhoosh")
        check(waitFast(app.navigationBars["MyWhoosh"], timeout: 6), "MyWhoosh-Detailseite")
        let connected = scrollUntilExists(text(containing: "test@example.com"))
        check(connected.exists, "MyWhoosh-Seite zeigt verbundenes Konto")
        check(app.switches["Neue Pläne automatisch senden"].exists, "Schalter für automatisches Senden")
        let history = scrollUntilExists(button(containing: "Fahrten aus MyWhoosh laden"))
        check(history.exists, "Fahrten-Import aus MyWhoosh angeboten")
        tap(history, "Fahrten aus MyWhoosh laden")
        check(waitForBanner(containing: "keine neuen Fahrten"), "Import meldet sich (Stub: keine Fahrten)")
        shot("profile-connected")
    }

    func test18_MyWhooshNotConnected() {
        launch()
        openTab("Plan")
        tap(row(0), "Erste Einheit")
        route = "einheit"
        _ = scrollUntilExists(button(containing: "Alternativ: .zwo-Datei"))
        check(!button(containing: "An MyWhoosh senden").exists, "Ohne Konto kein Sende-Button")
        check(text(containing: "Verbinde MyWhoosh unter Profil → Dienste & Geräte").exists, "Hinweis auf die Verbindung unter Dienste & Geräte")
        shot("not-connected")
        openConnections()
        check(scrollUntilExists(button(containing: "FIT-Dateien importieren")).exists, "FIT-Import auch ohne Konto")
        tap(scrollUntilExists(app.descendants(matching: .any)["profile.mywhoosh"].firstMatch), "Dienste & Geräte → MyWhoosh")
        let login = scrollUntilExists(button(containing: "Bei MyWhoosh anmelden"))
        check(login.exists && !login.isEnabled, "Anmelden erst mit E-Mail und Passwort aktiv")
        shot("profile-login")
        accessibilityAudit("Profil-MyWhoosh")
    }

    // MARK: Leistung – Leistungskurve, Bestleistungen, VO2max

    func test19_PerformanceAndVO2max() {
        launch()                                     // demo seed: rides carry synthetic measured curves
        openTab("Verlauf")
        let open = app.descendants(matching: .any)["performance.open"].firstMatch
        check(waitFast(open), "Zeile „Leistung“ oben im Verlauf")
        tap(open, "Leistung öffnen")
        route = "leistung"
        check(waitFast(app.navigationBars["Leistung"]), "Leistung-Screen öffnet")
        check(app.descendants(matching: .any)["performance.curve"].firstMatch.waitForExistence(timeout: 5), "Leistungskurve sichtbar")
        let best5min = app.descendants(matching: .any)["performance.best.300"].firstMatch
        check(scrollUntilExists(best5min).exists, "Bestleistung 5 min in der Liste")
        check(app.descendants(matching: .any)["performance.best.1200"].firstMatch.exists, "Bestleistung 20 min in der Liste")
        shot("kurve")
        tap(app.buttons["6 Wochen"], "Zeitraum 6 Wochen")
        check(app.buttons["6 Wochen"].isSelected, "6 Wochen gewählt")
        check(scrollUntilExists(app.descendants(matching: .any)["vo2max.card"].firstMatch).exists, "VO₂max-Karte in Leistung")
        check(text(containing: "Schätzung, kein Labortest").exists, "Hinweis „kein Labortest“")
        shot("vo2max")
        accessibilityAudit("Leistung")
        back()

        openTab("Heute")
        route = "heute"
        let card = app.descendants(matching: .any)["vo2max.card"].firstMatch
        check(scrollUntilExists(card).exists, "VO₂max-Karte auf Heute")
        shot("heute-vo2max")
    }

    // ANCHOR-UITEST-K1
    func test20_ConsistencyStreak() {
        launch()
        route = "heute"
        let arcCard = button(containing: "Winter Arc")
        check(scrollUntilExists(arcCard, maxSwipes: 3).exists, "Winter-Arc-Karte auf Heute")
        tap(arcCard, "Winter-Arc-Karte")
        route = "winterarc"
        check(waitFast(app.navigationBars["Winter Arc"]), "Winter-Arc-Detail öffnet")
        let card = app.descendants(matching: .any)["consistency.card"].firstMatch
        check(scrollUntilExists(card).exists || card.exists, "Karte „Konstanz“ im Winter-Arc-Detail")
        check(text(containing: "Konstanz").exists, "Titel „Konstanz“ sichtbar")
        check(text(containing: "Joker").exists, "Joker-Erklärung/Legende sichtbar")
        shot("konstanz-karte")
        accessibilityAudit("Konstanz")
        back()

        openTab("Plan")
        route = "plan"
        let adherence = app.descendants(matching: .any)["plan.adherence"].firstMatch
        check(scrollUntilExists(adherence, maxSwipes: 4).exists, "Plan-Kopf zeigt Plan-Treue („x von y Einheiten · z % TSS“)")
        shot("plan-treue")
    }


    // ---

    // ANCHOR-UITEST-K2

    // MARK: K2 – Wochenrückblick (Karte auf Heute, Detail, Erinnerung im Profil)

    func test21_WeeklyReview() {
        launch(extra: ["-uiWeeklyReview", "YES"])
        route = "heute"
        let card = app.descendants(matching: .any)["weeklyReview.card"].firstMatch
        check(waitFast(card), "Wochenrückblick-Karte sichtbar (Debug-Override)")
        check(app.buttons["weeklyReview.dismiss"].exists, "„Ausblenden“ angeboten")
        shot("karte")
        accessibilityAudit("Heute-Wochenrückblick")

        tap(card, "Wochenrückblick-Karte")
        route = "wochenrueckblick"
        check(waitFast(app.navigationBars["Wochenrückblick"]), "Wochenrückblick öffnet")
        check(text(containing: "Frühere Wochen").exists || scrollUntilExists(text(containing: "Frühere Wochen")).exists,
              "Frühere Wochen aufgelistet")
        shot("detail")
        accessibilityAudit("Wochenrückblick")
        back()

        route = "heute"
        tap(app.buttons["weeklyReview.dismiss"], "Ausblenden")
        check(!app.descendants(matching: .any)["weeklyReview.card"].firstMatch.waitForExistence(timeout: 2),
              "Karte nach „Ausblenden“ verschwunden")

        openTab("Profil")
        route = "profil"
        tap(scrollUntilExists(app.descendants(matching: .any)["profile.reminders"].firstMatch), "Profil → Erinnerungen")
        let toggle = app.descendants(matching: .any)["reminder.toggle"].firstMatch
        check(scrollUntilExists(toggle).exists, "Schalter „Wochenrückblick am Sonntag“ im Profil")
        shot("erinnerung")
    }

    // ---

    // ANCHOR-UITEST-K3

    // MARK: Challenges + Trophäenschrank (K3)

    func test22_ChallengesAndTrophies() {
        launch()                                     // demo in November: Monats-Konstanz November läuft
        route = "heute"
        // Highlight slot shows one card; Sun 16:00 – Tue the weekly review has priority – hide it first.
        let review = app.descendants(matching: .any)["weeklyReview.dismiss"].firstMatch
        if review.waitForExistence(timeout: 2) {
            tap(review, "Wochenrückblick ausblenden")
            check(!app.descendants(matching: .any)["weeklyReview.card"].firstMatch.waitForExistence(timeout: 1),
                  "Ausgeblendeter Rückblick macht Platz für die Challenge")
        }
        // Das Highlight hängt vom Datum ab: Es erscheint nur bei einer laufenden Challenge oder einer, die in ≤ 7 Tagen
        // startet (mit den Demo-Daten z. B. nicht vom 16. bis 24. November). Sonst über die Winter-Arc-Karte weiter.
        let highlight = app.descendants(matching: .any)["challenge.highlight"].firstMatch
        if scrollUntilExists(highlight, maxSwipes: 3).exists {
            check(true, "Challenge-Highlight auf Heute")
            shot("challenge-highlight")
            tap(highlight, "Challenge-Highlight öffnen")
        } else {
            log("No challenge highlight today (date-dependent)", "")
            tap(button(containing: "Winter Arc"), "Winter-Arc-Karte")
        }
        route = "winterarc"
        check(waitFast(app.navigationBars["Winter Arc"]), "Winter-Arc-Detail öffnet")
        let challenges = app.descendants(matching: .any)["challenges.card"].firstMatch
        check(scrollUntilExists(challenges).exists, "Karte „Challenges“")
        shot("challenges")
        let trophies = app.descendants(matching: .any)["trophies.card"].firstMatch
        check(scrollUntilExists(trophies).exists, "Karte „Trophäen“")
        let all = app.descendants(matching: .any)["trophies.all"].firstMatch
        check(scrollUntilExists(all).exists, "„Alle anzeigen“ in der Trophäen-Karte")
        tap(all, "Alle Trophäen anzeigen")
        check(waitFast(app.navigationBars["Trophäen"]), "Trophäenschrank öffnet")
        check(app.descendants(matching: .any)["trophies.count"].firstMatch.waitForExistence(timeout: 5), "Trophäen-Zähler sichtbar")
        shot("trophaeenschrank")
        accessibilityAudit("Trophaeenschrank")
        back()
        back()
    }

    // ---

    /// B05 acceptance (open since WP4): the diagnostics export opens the share sheet; feedback has a route.
    func test24_DiagnosticsShareSheet() {
        launch()
        openTab("Profil")
        tap(scrollUntilExists(app.descendants(matching: .any)["profile.help"].firstMatch), "Profil → Hilfe & Feedback")
        let export = scrollUntilExists(app.buttons["diagnostics.export"], maxSwipes: 8)
        check(export.exists, "„Diagnose exportieren“ im Profil")
        tap(export, "Diagnose exportieren")
        let share = app.buttons["diagnostics.share"]
        check(share.waitForExistence(timeout: 8), "Export fertig: „Diagnose teilen“ erscheint")
        tap(share, "Diagnose teilen")
        let sheet = app.otherElements["ActivityListView"]
        let opened = sheet.waitForExistence(timeout: 6) || app.navigationBars["UIActivityContentView"].exists
        check(opened, "Teilen-Menü öffnet sich")
        shot("share-sheet")
        if opened { app.swipeDown(velocity: .fast) }
        check(scrollUntilExists(app.descendants(matching: .any)["feedback.open"].firstMatch, maxSwipes: 4).exists,
              "Feedback-Weg vorhanden (Mail oder GitHub-Issue)")
    }

    // ANCHOR-UITEST-P1

    /// A5/A8/A6: goal forecast with what-if slider (Winter Arc), distribution and eFTP history (Leistung).
    func test25_ForecastAndDistribution() {
        launch()
        route = "heute"
        let arcCard = button(containing: "Winter Arc")
        check(scrollUntilExists(arcCard, maxSwipes: 3).exists, "Winter-Arc-Karte auf Heute")
        tap(arcCard, "Winter-Arc-Karte")
        route = "winterarc"
        check(waitFast(app.navigationBars["Winter Arc"]), "Winter-Arc-Detail öffnet")
        let forecast = app.descendants(matching: .any)["forecast.card"].firstMatch
        check(scrollUntilExists(forecast).exists, "Karte „Prognose zum Ziel“")
        check(app.descendants(matching: .any)["forecast.slider"].firstMatch.exists, "Regler „Stunden pro Woche“")
        check(text(containing: "Bei ").exists, "Prognose-Satz („Bei x h/Woche …“)")
        shot("prognose")
        accessibilityAudit("Prognose")
        back()

        openTab("Verlauf")
        let open = app.descendants(matching: .any)["performance.open"].firstMatch
        check(waitFast(open), "Zeile „Leistung“ oben im Verlauf")
        tap(open, "Leistung öffnen")
        route = "leistung"
        check(waitFast(app.navigationBars["Leistung"]), "Leistung-Screen öffnet")
        let distribution = app.descendants(matching: .any)["distribution.card"].firstMatch
        check(scrollUntilExists(distribution).exists, "Karte „Trainingsverteilung“")
        check(text(containing: "Grundlage").exists, "Zonen-Gruppe „Grundlage“ sichtbar")
        shot("verteilung")
        accessibilityAudit("Verteilung")
        let history = app.descendants(matching: .any)["ftpHistory.card"].firstMatch
        check(scrollUntilExists(history).exists, "Karte „eFTP-Verlauf“")
        shot("eftp-verlauf")
        accessibilityAudit("eFTP-Verlauf")
    }

    // ---

    // ANCHOR-UITEST-P2

    func test26_AbilitiesAndDurability() {
        launch()                                     // demo seed: rides carry measured power curves
        openTab("Verlauf")
        tap(scrollUntilExists(app.buttons["performance.open"]), "Leistung öffnen")
        route = "leistung"
        check(waitFast(app.navigationBars["Leistung"]), "Leistung-Screen öffnet")
        let abilities = app.descendants(matching: .any)["abilities.card"].firstMatch
        check(scrollUntilExists(abilities).exists, "Karte „Fähigkeiten“ in Leistung")
        check(app.descendants(matching: .any)["abilities.row.1200"].firstMatch.exists, "Zeile „Schwelle“ (20 min)")
        check(text(containing: "Level").exists, "Level-Angabe sichtbar")
        shot("faehigkeiten")
        accessibilityAudit("Leistung-Fähigkeiten")
        let durability = app.descendants(matching: .any)["durability.card"].firstMatch
        check(scrollUntilExists(durability).exists, "Karte „Ermüdungsresistenz“ in Leistung")
        shot("ermuedungsresistenz")
        accessibilityAudit("Leistung-Ermüdungsresistenz")
        back()

        // Fahrt-Detail: the row exists only for FIT rides of at least 60 minutes, so its absence is not an error.
        route = "verlauf"
        tap(scrollUntilExists(row(0)), "Erste Fahrt")
        route = "fahrt"
        settle()
        let rideRow = app.descendants(matching: .any)["ride.durability"].firstMatch
        if scrollUntilExists(rideRow, maxSwipes: 6).exists {
            shot("fahrt-ermuedungsresistenz")
            accessibilityAudit("Fahrt-Ermüdungsresistenz")
        }
    }

    // ---

    // ANCHOR-UITEST-P3
    /// G6 + G5: the demo seed carries a previous year → "Vorjahr" legend in both charts; "Saisonrückblick teilen" opens the share sheet.
    func test27_SeasonShadowAndShare() {
        launch()                                      // demo seed: recent rides + a deterministic "last winter" block
        route = "heute"
        let arcCard = button(containing: "Winter Arc")
        check(scrollUntilExists(arcCard, maxSwipes: 3).exists, "Winter-Arc-Karte auf Heute")
        tap(arcCard, "Winter-Arc-Karte")
        route = "winterarc"
        check(waitFast(app.navigationBars["Winter Arc"]), "Winter-Arc-Detail öffnet")
        let legend = app.descendants(matching: .any)["shadow.legend"].firstMatch
        check(scrollUntilExists(legend).exists, "Legende „Vorjahr“ unter dem Kurs-Chart")
        check(text(containing: "Vorjahr").exists, "Text „Vorjahr“ sichtbar")
        shot("vorjahr-kurs")

        let share = app.descendants(matching: .any)["season.share"].firstMatch
        check(scrollUntilExists(share).exists, "„Saisonrückblick teilen“ im Winter-Arc-Detail")
        settle()
        // The image is rendered after the screen appears; the button is enabled once the PNG exists.
        let ready = NSPredicate(format: "isEnabled == true")
        let enabled = XCTNSPredicateExpectation(predicate: ready, object: share)
        check(XCTWaiter.wait(for: [enabled], timeout: 8) == .completed, "Bild fertig, Teilen-Knopf aktiv")
        accessibilityAudit("Saisonrueckblick")
        tap(share, "Saisonrückblick teilen")
        let sheet = app.otherElements["ActivityListView"]
        let opened = sheet.waitForExistence(timeout: 8) || app.navigationBars["UIActivityContentView"].exists
        check(opened, "Teilen-Menü öffnet sich")
        shot("share-sheet")
        if opened { app.swipeDown(velocity: .fast) }
        back()

        route = "heute"
        let formCard = button(containing: "Fitness & Form")
        _ = scrollUntilExists(formCard, maxSwipes: 4)
        tap(formCard, "Karte Fitness & Form")
        route = "fitness"
        check(waitFast(app.navigationBars["Fitness & Form"]), "Fitness-&-Form-Screen öffnet")
        check(app.buttons["90 T"].isSelected, "90 Tage ist vorgewählt (Vorjahr liegt in der Demo im Zeitraum)")
        check(app.descendants(matching: .any)["shadow.legend"].firstMatch.waitForExistence(timeout: 5), "Legende „Vorjahr“ im Fitness-Chart")
        shot("vorjahr-fitness")
    }

    // ---

    // ANCHOR-UITEST-P4

    // MARK: P4 – Winter-Reise und Erinnerung vor Einheiten

    func test28_JourneyAndReminder() {
        launch()
        route = "heute"
        let arcCard = button(containing: "Winter Arc")
        check(scrollUntilExists(arcCard, maxSwipes: 3).exists, "Winter-Arc-Karte auf Heute")
        tap(arcCard, "Winter-Arc-Karte")
        route = "winterarc"
        check(waitFast(app.navigationBars["Winter Arc"]), "Winter-Arc-Detail öffnet")
        let journey = app.descendants(matching: .any)["journey.card"].firstMatch
        check(scrollUntilExists(journey).exists, "Karte „Winter-Reise“ im Winter-Arc-Detail")
        check(journey.label.hasPrefix("Etappe "), "VoiceOver nennt Etappe und Fortschritt: \(journey.label)")
        shot("winter-reise")
        accessibilityAudit("Winter-Reise")
        back()

        openTab("Profil")
        route = "profil"
        tap(scrollUntilExists(app.descendants(matching: .any)["profile.reminders"].firstMatch), "Profil → Erinnerungen")
        let toggle = app.descendants(matching: .any)["reminder.workoutToggle"].firstMatch
        check(scrollUntilExists(toggle).exists, "Schalter „Erinnerung 30 Minuten vor der Einheit“ im Profil")
        shot("einheiten-erinnerung")
    }

    // ---

    // ANCHOR-UITEST-K4

    // MARK: K4 – Aerobe Effizienz und Entkopplung

    func test23_AerobicEfficiency() {
        launch()                                     // demo seed: rides carry average heart rate and decoupling
        openTab("Verlauf")
        let open = app.descendants(matching: .any)["performance.open"].firstMatch
        check(waitFast(open), "Zeile „Leistung“ oben im Verlauf")
        tap(open, "Leistung öffnen")
        route = "leistung"
        check(waitFast(app.navigationBars["Leistung"]), "Leistung-Screen öffnet")
        let card = app.descendants(matching: .any)["efficiency.card"].firstMatch
        check(scrollUntilExists(card).exists, "Karte „Aerobe Effizienz“ in Leistung")
        check(text(containing: "Fahrten mit Leistung und Puls").exists, "Abdeckung „x von y Fahrten mit Leistung und Puls“")
        check(app.descendants(matching: .any)["efficiency.chart"].firstMatch.exists, "Effizienz-Verlauf (Chart) sichtbar")
        shot("effizienz")
        accessibilityAudit("Leistung-Effizienz")
        back()

        route = "verlauf"
        tap(scrollUntilExists(row(0)), "Erste Fahrt")
        route = "fahrt"
        let tile = app.descendants(matching: .any)["ride.efficiency"].firstMatch
        check(scrollUntilExists(tile).exists, "Effizienz im Fahrt-Detail")
        check(text(containing: "Entkopplung").exists, "Entkopplung im Fahrt-Detail (Demo-Fahrten haben FIT-Werte)")
        shot("fahrt-effizienz")
        accessibilityAudit("Fahrt-Effizienz")
    }

    // MARK: B01 – Onboarding beim ersten Start

    func test15_Onboarding() {
        launch(seed: "empty", extra: ["-uiOnboarding", "YES"])
        route = "onboarding"
        let indicator = app.otherElements["onboarding.pageIndicator"]
        check(waitFast(text(containing: "Willkommen bei IndoorCoach"), timeout: 8), "Schritt 1 „Willkommen“ beim ersten Start")
        check(indicator.label == "Schritt 1 von 5", "Seitenanzeige „Schritt 1 von 5“")
        check(app.buttons["onboarding.skip"].exists, "„Überspringen“ angeboten")
        shot("1-willkommen")
        accessibilityAudit("Onboarding-Willkommen")

        tap(app.buttons["onboarding.next"], "Los geht’s")
        check(waitFast(text(containing: "Dein Training")), "Schritt 2 „Dein Training“")
        check(indicator.label == "Schritt 2 von 5", "Seitenanzeige „Schritt 2 von 5“")
        // The value lives in the stepper's label ("250 W, FTP"), not in a separate static text.
        check(app.steppers["onboarding.ftp"].label.contains("250 W") || text(containing: "250 W").exists, "FTP-Standard 250 W")
        let ftp = app.steppers["onboarding.ftp"]
        // „Weiß ich nicht“: 2,5 W/kg × 75 kg = 187,5 → 190 W.
        tap(app.buttons["onboarding.ftpUnknown"], "FTP „Weiß ich nicht“")
        check(ftp.label.contains("190 W") || text(containing: "190 W").exists, "FTP wird auf 190 W geschätzt")
        tap(ftp.buttons.element(boundBy: 1), "FTP +5")
        tap(ftp.buttons.element(boundBy: 1), "FTP +5")
        // The value lives in the stepper's label ("200 W, FTP"), not in a separate static text.
        check(ftp.label.contains("200 W") || text(containing: "200 W").exists, "FTP steigt auf 200 W")
        // SE: the days sit under the fixed "Weiter" bar and still count as hittable; scroll them clear first (audit 3).
        let monday = app.buttons["Montag"]
        lift(monday, above: app.buttons["onboarding.next"])
        tap(monday, "Trainingstag Montag")
        check(monday.isSelected, "Montag ist als gewählt markiert")
        shot("2-training")
        accessibilityAudit("Onboarding-Training")

        tap(app.buttons["onboarding.next"], "Weiter")
        check(waitFast(text(containing: "Deine Trainings-App")), "Schritt 3 „Trainings-App“")
        check(indicator.label == "Schritt 3 von 5", "Seitenanzeige „Schritt 3 von 5“")
        check(app.buttons["whoosh.login"].exists, "MyWhoosh-Anmeldung angeboten")
        check(app.buttons["onboarding.strava"].exists, "Link „Strava oder FIT-Dateien?“")
        shot("3-trainings-app")
        accessibilityAudit("Onboarding-Trainings-App")

        tap(app.buttons["onboarding.later"], "Später")
        check(waitFast(text(containing: "Dein Coach")), "Schritt 4 „Coach“")
        check(indicator.label == "Schritt 4 von 5", "Seitenanzeige „Schritt 4 von 5“")
        check(app.buttons["claude.key.save"].exists && !app.buttons["claude.key.save"].isEnabled,
              "„Prüfen & speichern“ ohne Key deaktiviert")
        shot("4-coach")
        accessibilityAudit("Onboarding-Coach")

        tap(app.buttons["onboarding.noClaude"], "Ohne Claude weiter")
        check(waitFast(text(containing: "Alles bereit")), "Schritt 5 „Fertig“")
        check(indicator.label == "Schritt 5 von 5", "Seitenanzeige „Schritt 5 von 5“")
        check(app.descendants(matching: .any)["onboarding.status.mywhoosh"].exists, "Status-Checkliste sichtbar")
        check(app.buttons["onboarding.tour"].exists, "„Kurze Tour ansehen“ angeboten")
        shot("5-fertig")
        accessibilityAudit("Onboarding-Fertig")

        tap(app.buttons["onboarding.start"], "Direkt starten")
        route = "heute"
        check(waitFast(app.navigationBars["Heute"], timeout: 6), "Onboarding endet auf Heute")
        // The cover is still in the tree while it slides away.
        let closing = Date().addingTimeInterval(4)
        while app.buttons["onboarding.start"].exists && Date() < closing { usleep(200_000) }
        check(!app.buttons["onboarding.start"].exists && !app.otherElements["onboarding.pageIndicator"].exists, "Onboarding geschlossen")
        check(app.tabBars.buttons["Heute"].isSelected, "Tab „Heute“ aktiv")
        check(waitFast(text(containing: "Nächste Einheit")) && !text(containing: "Nichts geplant").exists,
              "Demo-Daten geladen: Heute zeigt eine Einheit")
        shot("nach-onboarding")
        openTab("Profil")
        check(text(containing: "200 W").exists, "FTP aus dem Onboarding im Profil")

        // Zweiter Start: kein Onboarding mehr.
        app.terminate()
        log("Terminated app")
        launch(seed: nil)
        route = "heute"
        check(app.navigationBars["Heute"].waitForExistence(timeout: 5), "Zweiter Start landet direkt auf Heute")
        check(!text(containing: "Willkommen bei IndoorCoach").exists, "Kein Onboarding beim zweiten Start")
        shot("zweiter-start")
    }

    func test16_OnboardingStravaChoice() {
        launch(seed: "empty", extra: ["-uiOnboarding", "YES"])
        route = "onboarding"
        tap(app.buttons["onboarding.next"], "Los geht’s")
        tap(app.buttons["onboarding.next"], "Weiter")
        tap(app.buttons["onboarding.strava"], "Strava oder FIT-Dateien? Unter Dienste & Geräte einrichten")
        route = "strava"
        check(waitFast(app.navigationBars["Strava"], timeout: 8), "Der Link öffnet direkt die Strava-Seite im Profil")
        let clientID = input(placeholder: "Client-ID")
        let end = Date().addingTimeInterval(4)
        while !clientID.isHittable && Date() < end { usleep(200_000) }
        check(clientID.isHittable, "Strava-Seite zeigt das Feld Client-ID")
        shot("strava-abschnitt")
    }

    // MARK: Dienste & Geräte – dauerhafter Fehler (Badge, Hinweiszeile, Sprung zur Detailseite)

    func test16b_ConnectionErrorBadgeAndAttentionRow() {
        launch(extra: ["-uiConnectionErrorSeed", "YES"])
        let profileTab = app.tabBars.buttons["Profil"]
        check(waitFast(profileTab), "Tab „Profil“")
        let badge = "\(profileTab.value as? String ?? "")\(profileTab.label)"
        check(badge.contains("1"), "Profil-Tab trägt das Badge „1“ (\(badge))")
        openTab("Profil")
        let hint = scrollUntilExists(app.descendants(matching: .any)["profile.attention.strava"].firstMatch, maxSwipes: 10)
        check(hint.exists, "Hinweiszeile „Strava: …“ unter Verbindungen")
        shot("hinweiszeile")
        tap(hint, "Hinweiszeile Strava")
        check(waitFast(app.navigationBars["Strava"], timeout: 6), "Die Zeile öffnet direkt die Seite „Strava“")
        check(text(containing: "Zugang abgelaufen").exists, "Fehlertext im Status-Kopf")
        check(input(placeholder: "Client-ID").exists, "Zugangsdaten zum erneuten Verbinden sichtbar")
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

    /// Audit 2 (erweiterte Version): every surface added since the first audit, at L and Accessibility-L.
    func testMatrixNewSurfaces() {
        let sizes = ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityL"]
        for size in sizes {
            let tag = size == sizes[0] ? "L" : "AXL"
            launch(extra: ["-UIPreferredContentSizeCategoryName", size, "-uiWeeklyReview", "YES"])
            route = "heute"
            shot("\(tag)-highlight")
            accessibilityAudit("Heute-Highlight@\(tag)")
            let review = app.descendants(matching: .any)["weeklyReview.card"].firstMatch
            if review.waitForExistence(timeout: 3) {
                tap(review, "Wochenrückblick öffnen")
                route = "wochenrueckblick"
                settle()
                shot("\(tag)-top")
                accessibilityAudit("Wochenrückblick@\(tag)")
                app.swipeUp(); shot("\(tag)-scrolled")
                back()
            }
            openTab("Verlauf")
            tap(scrollUntilExists(app.buttons["performance.open"]), "Leistung öffnen")
            route = "leistung"
            settle()
            shot("\(tag)-top")
            accessibilityAudit("Leistung@\(tag)")
            for _ in 0..<3 { app.swipeUp(); settle(0.8); shot("\(tag)-scrolled") }
            accessibilityAudit("Leistung-unten@\(tag)")
            back()
            openTab("Heute")
            let arc = scrollUntilExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Winter Arc'")).firstMatch)
            tap(arc, "Winter Arc öffnen")
            route = "winterarc"
            settle()
            shot("\(tag)-top")
            accessibilityAudit("WinterArc@\(tag)")
            for _ in 0..<4 { app.swipeUp(); settle(0.8); shot("\(tag)-scrolled") }
            accessibilityAudit("WinterArc-unten@\(tag)")
            let all = app.descendants(matching: .any)["trophies.all"].firstMatch
            if scrollUntilExists(all, maxSwipes: 4).exists {
                tap(all, "Alle Trophäen")
                route = "trophaeen"
                settle()
                shot("\(tag)-top")
                accessibilityAudit("Trophaeenschrank@\(tag)")
                app.swipeUp(); shot("\(tag)-scrolled")
            } else {
                log("Trophäenschrank", "„Alle anzeigen“ nicht gefunden")
            }
            app.terminate()
        }
    }

    // MARK: Konstanz-Serie mit Joker + Plan-Treue (K1)


    // ---
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

/// Paket „Öffnung“ (docs/12): Onboarding-Journey, Feature-Tour, Feedback.
final class AuditOpeningTests: AuditCase {
    /// UX-Matrix für das Paket „Öffnung“: Onboarding (5 Schritte), Tour und Feedback bei L/Dark und AX5/Light.
    func testMatrixOpening() {
        let combos: [(size: String, tag: String, dark: Bool)] = [
            ("UICTContentSizeCategoryL", "L-dark", true),
            ("UICTContentSizeCategoryAccessibilityXXXL", "AX5", false)
        ]
        for combo in combos {
            XCUIDevice.shared.appearance = combo.dark ? .dark : .light
            launch(seed: "empty", extra: ["-UIPreferredContentSizeCategoryName", combo.size, "-uiOnboarding", "YES",
                                          "-uiClaudeStub", "YES", "-uiMyWhooshStubLogin", "YES"])
            route = "onboarding"
            let steps: [(name: String, advance: String)] = [("1-willkommen", "onboarding.next"), ("2-training", "onboarding.next"),
                                                            ("3-trainings-app", "onboarding.later"), ("4-coach", "onboarding.noClaude")]
            for step in steps {
                settle()
                shot("\(combo.tag)-\(step.name)")
                accessibilityAudit("Onboarding-\(step.name)@\(combo.tag)")
                app.swipeUp()
                shot("\(combo.tag)-\(step.name)-scrolled")
                tap(app.buttons[step.advance], step.advance)
            }
            settle()
            shot("\(combo.tag)-5-fertig")
            accessibilityAudit("Onboarding-fertig@\(combo.tag)")
            tap(app.buttons["onboarding.tour"], "Kurze Tour ansehen")
            route = "tour"
            _ = app.buttons["tour.skip"].waitForExistence(timeout: 6)
            usleep(3_200_000)
            shot("\(combo.tag)-seite-1")
            accessibilityAudit("Tour@\(combo.tag)")
            tap(app.buttons["tour.skip"], "Tour überspringen")
            route = "feedback"
            openTab("Profil")
            tap(scrollUntilExists(app.descendants(matching: .any)["profile.help"].firstMatch), "Profil → Hilfe & Feedback")
            let open = scrollUntilExists(app.descendants(matching: .any)["feedback.open"].firstMatch, maxSwipes: 8)
            tap(open, "Feedback & Wünsche")
            settle()
            shot("\(combo.tag)-feedback")
            accessibilityAudit("Feedback@\(combo.tag)")
            app.swipeUp()
            shot("\(combo.tag)-feedback-scrolled")
            app.terminate()
        }
        XCUIDevice.shared.appearance = .light
    }

    // ANCHOR-UITEST-O1 (Onboarding-Journey & Verbindungen)

    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Launch arguments for the onboarding journey: forced onboarding, stubbed MyWhoosh login and Claude key check.
    /// iOS offers to save the MyWhoosh password in the Passwords app once the login form disappears.
    private func dismissSavePasswordPrompt() {
        // Not the onboarding's own "Später" (onboarding.later).
        let notOurs = NSPredicate(format: "(label == 'Später' OR label == 'Not Now') AND identifier != 'onboarding.later'")
        for candidate in [app.buttons.matching(notOurs).firstMatch,
                          XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons.matching(notOurs).firstMatch] {
            if candidate.waitForExistence(timeout: 1.5) { tap(candidate, "Passwort sichern? – Später"); return }
        }
    }

    private var journeyArguments: [String] {
        ["-uiOnboarding", "YES", "-uiMyWhooshStubLogin", "YES", "-uiClaudeStub", "YES"]
    }

    /// Komplette Journey: Stub-Login, geprüfter Test-Key, Fertig → Tour → Heute.
    func test29_OnboardingJourneyWithConnections() {
        launch(seed: "empty", extra: journeyArguments)
        route = "onboarding"
        let indicator = app.otherElements["onboarding.pageIndicator"]
        check(waitFast(text(containing: "Willkommen bei IndoorCoach"), timeout: 8), "Willkommen")
        tap(app.buttons["onboarding.next"], "Los geht’s")
        check(waitFast(text(containing: "Dein Training")), "Dein Training")
        tap(app.buttons["Montag"], "Trainingstag Montag")
        tap(app.buttons["onboarding.next"], "Weiter")

        check(waitFast(text(containing: "Deine Trainings-App")), "Trainings-App")
        check(indicator.label == "Schritt 3 von 5", "Seitenanzeige „Schritt 3 von 5“")
        type(anyElement("whoosh.email"), "test@example.com", "MyWhoosh-E-Mail")
        type(anyElement("whoosh.password"), "irgendein-test-passwort", "MyWhoosh-Passwort")
        shot("3-login-ausgefuellt")
        let password = anyElement("whoosh.password")
        check(((password.value as? String) ?? "").count > 0, "Passwortfeld enthält Text (\((password.value as? String) ?? "nil"))")
        check(app.buttons["whoosh.login"].isEnabled, "Anmelden-Button aktiv")
        tap(app.buttons["whoosh.login"], "Bei MyWhoosh anmelden")
        let status = anyElement("onboarding.myWhooshStatus")
        let loginError = anyElement("whoosh.error")
        let deadline = Date().addingTimeInterval(15)
        while !status.exists && !loginError.exists && Date() < deadline { usleep(250_000) }
        dismissSavePasswordPrompt()
        shot("3-nach-login")
        if loginError.exists { check(false, "Login-Fehler: \(loginError.label)") }
        check(status.exists, "Erfolgsstatus nach dem Login")
        check(status.label.contains("Verbunden") && status.label.contains("Fahrten geladen"),
              "Status „Verbunden · N Fahrten geladen“ (\(status.label))")
        check(!anyElement("whoosh.password").exists, "Passwortfeld nach dem Login weg")
        shot("3-verbunden")
        accessibilityAudit("Onboarding-Verbunden")
        tap(app.buttons["onboarding.next"], "Weiter")

        check(waitFast(text(containing: "Dein Coach")), "Coach")
        let testKeyField = scrollUntilExists(anyElement("claude.key.field"), maxSwipes: 6)
        lift(testKeyField, above: app.buttons["onboarding.noClaude"])
        type(testKeyField, "sk-ant-test-0000000000000000000000", "Claude-Test-Key")
        tap(app.buttons["claude.key.save"], "Prüfen & speichern")
        check(waitFast(anyElement("claude.key.saved"), timeout: 10), "Key geprüft und gespeichert")
        shot("4-key-gespeichert")
        tap(app.buttons["onboarding.next"], "Weiter")

        check(waitFast(text(containing: "Alles bereit")), "Fertig")
        check(anyElement("onboarding.status.mywhoosh").label.contains("verbunden"), "MyWhoosh in der Checkliste verbunden")
        check(anyElement("onboarding.status.coach").label.contains("Claude-Key gespeichert"), "Coach in der Checkliste eingerichtet")
        shot("5-fertig")
        accessibilityAudit("Onboarding-Fertig-verbunden")

        tap(app.buttons["onboarding.tour"], "Kurze Tour ansehen")
        route = "tour"
        // The tour's own buttons belong to package O2: leave it through "Überspringen" or its finish button.
        let skip = button(containing: "Überspringen")
        let finish = app.buttons["tour.finish"]
        let end = Date().addingTimeInterval(10)
        while !skip.exists && !finish.exists && Date() < end { usleep(200_000) }
        check(skip.exists || finish.exists, "Feature-Tour erscheint")
        shot("tour")
        if skip.exists { tap(skip, "Tour überspringen") } else { tap(finish, "Tour beenden") }
        route = "heute"
        check(waitFast(app.navigationBars["Heute"], timeout: 8), "Nach der Tour: Heute")
        check(app.tabBars.buttons["Heute"].isSelected, "Tab „Heute“ aktiv")
        check(!text(containing: "Alles bereit").exists, "Onboarding geschlossen")
    }

    /// Falscher Key zeigt einen Fehler und wird nicht gespeichert; nach Abbruch macht der nächste Start am selben Schritt weiter.
    func test30_OnboardingWrongKeyAndResume() {
        launch(seed: "empty", extra: journeyArguments)
        route = "onboarding"
        let indicator = app.otherElements["onboarding.pageIndicator"]
        tap(app.buttons["onboarding.next"], "Los geht’s")
        tap(app.buttons["onboarding.next"], "Weiter")
        tap(app.buttons["onboarding.later"], "Später")
        check(waitFast(text(containing: "Dein Coach")), "Coach")

        let keyField = scrollUntilExists(anyElement("claude.key.field"), maxSwipes: 6)
        lift(keyField, above: app.buttons["onboarding.noClaude"])
        type(keyField, "sk-ant-wrong-0000000000000000", "falscher Claude-Key")
        tap(app.buttons["claude.key.save"], "Prüfen & speichern")
        check(waitFast(anyElement("claude.key.error"), timeout: 10), "Fehlertext bei falschem Key")
        check(!anyElement("claude.key.saved").exists, "Falscher Key wird nicht gespeichert")
        check(app.buttons["onboarding.noClaude"].exists, "„Ohne Claude weiter“ bleibt möglich")
        shot("4-falscher-key")
        accessibilityAudit("Onboarding-Falscher-Key")
        check(indicator.label == "Schritt 4 von 5", "Seitenanzeige „Schritt 4 von 5“")

        // Abbruch mitten im Onboarding, dann normaler Start (ohne -uiOnboarding): gleicher Schritt.
        app.terminate()
        log("Terminated app mid-onboarding")
        launch(seed: nil, extra: ["-uiClaudeStub", "YES"])
        route = "onboarding"
        check(waitFast(text(containing: "Dein Coach"), timeout: 8), "Wiederaufnahme beim Schritt „Coach“")
        check(app.otherElements["onboarding.pageIndicator"].label == "Schritt 4 von 5", "Seitenanzeige weiter „Schritt 4 von 5“")
        check(!text(containing: "Willkommen bei IndoorCoach").exists, "Nicht wieder von vorn")
        shot("4-wiederaufnahme")
    }

    // ANCHOR-UITEST-O2 (Feature-Tour & Tipps)

    /// O2: Feature-Tour über `-uiTour YES` (DEBUG-Cover in IndoorCoachApp), danach Tipp „Woche planen“ mit `-uiTips YES`.
    func test31_FeatureTourAndTips() {
        route = "tour"
        launch(extra: ["-uiTour", "YES"])
        let page1 = app.descendants(matching: .any)["tour.page.1"].firstMatch
        check(waitFast(page1, timeout: 10), "Tour öffnet mit Seite 1")
        check(app.staticTexts["Claude plant deine Woche"].waitForExistence(timeout: 4), "Titel Seite 1")
        let indicator = app.descendants(matching: .any)["tour.pageIndicator"].firstMatch
        check(indicator.exists && indicator.label == "Seite 1 von 5", "Seitenanzeige „Seite 1 von 5“")
        check(app.buttons["tour.skip"].exists, "„Überspringen“ vorhanden")
        shot("seite-1")
        accessibilityAudit("Tour Seite 1")
        for n in 2...5 {
            tap(app.buttons["tour.next"], "Weiter zu Seite \(n)")
            check(waitFast(app.descendants(matching: .any)["tour.page.\(n)"].firstMatch), "Seite \(n) sichtbar")
            check(indicator.label == "Seite \(n) von 5", "Seitenanzeige „Seite \(n) von 5“")
            if n == 3 || n == 5 { usleep(3_200_000); shot("seite-\(n)") }
        }
        check(!app.buttons["tour.next"].exists, "Letzte Seite: kein „Weiter“ mehr")
        accessibilityAudit("Tour Seite 5")
        tap(app.buttons["tour.finish"], "Los geht’s")
        check(!app.buttons["tour.finish"].waitForExistence(timeout: 2), "Tour schließt")
        check(app.tabBars.firstMatch.waitForExistence(timeout: 6), "App sichtbar nach der Tour")

        route = "tipps"
        app.terminate()
        launch(extra: ["-uiTab", "plan", "-uiTips", "YES"])
        check(waitFast(app.staticTexts["Woche planen"], timeout: 10), "Tipp „Woche planen“ auf dem Plan-Tab")
        shot("tipp-plan")
    }

    // ANCHOR-UITEST-O3 (Feedback als GitHub-Issue)

    /// O3: Feedback-Formular (Wunsch), Vorschau, Text kopieren, Weiter zu GitHub (Safari), App-Einführung.
    func test32_FeedbackFormAndTour() {
        launch()
        openTab("Profil")
        tap(scrollUntilExists(app.descendants(matching: .any)["profile.help"].firstMatch), "Profil → Hilfe & Feedback")
        let open = scrollUntilExists(app.descendants(matching: .any)["feedback.open"].firstMatch, maxSwipes: 8)
        check(open.exists, "Zeile „Feedback & Wünsche“ auf „Hilfe & Feedback“")
        tap(open, "Feedback & Wünsche")
        route = "feedback"
        settle()
        // A draft from an earlier run survives in UserDefaults (by design); start clean.
        let leftover = app.buttons["feedback.done"]
        if leftover.exists { tap(leftover, "Alten Entwurf mit „Erledigt“ verwerfen") }
        let submit = app.buttons["feedback.submit"]
        check(waitFast(app.descendants(matching: .any)["feedback.kind"].firstMatch), "Art-Auswahl sichtbar")
        shot("feedback-leer")
        accessibilityAudit("Feedback-leer")
        // SE: the lazy form creates the button only once it scrolls into view (audit 3).
        check(scrollUntilExists(submit, maxSwipes: 4).exists && !submit.isEnabled, "„Weiter zu GitHub“ ist ohne Text deaktiviert")
        for _ in 0..<3 where !app.segmentedControls.buttons["Wunsch"].isHittable { app.swipeDown(velocity: .fast) }

        let wish = app.segmentedControls.buttons["Wunsch"]
        if wish.exists { tap(wish, "Art Wunsch") } else { tap(app.buttons["Wunsch"], "Art Wunsch") }
        type(app.textFields["feedback.title"], "Testwunsch bitte ignorieren", "Titel")
        let bodyField = app.textViews["feedback.body"]
        type(bodyField, "Dies ist ein automatischer UI-Test ohne echte Daten.", "Beschreibung")
        if app.keyboards.count > 0 { app.swipeDown() }
        let preview = scrollUntilExists(app.descendants(matching: .any)["feedback.preview"].firstMatch, maxSwipes: 8)
        check(preview.exists, "Vorschau erscheint")
        check(text(containing: "[Wunsch] Testwunsch bitte ignorieren").exists, "Vorschau zeigt Präfix und Titel")
        check(app.switches["feedback.appInfo"].exists, "Schalter „App-Version und Gerät anhängen“")
        shot("feedback-ausgefuellt")
        accessibilityAudit("Feedback-ausgefuellt")

        let copy = scrollUntilExists(app.buttons["feedback.copy"], maxSwipes: 6)
        check(submit.isEnabled, "„Weiter zu GitHub“ ist mit gültigem Text aktiv")
        tap(copy, "Text kopieren")
        check(app.descendants(matching: .any)["feedback.copied"].firstMatch.waitForExistence(timeout: 4),
              "Bestätigung „Kopiert“")

        tap(submit, "Weiter zu GitHub")
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        check(safari.wait(for: .runningForeground, timeout: 15), "Safari kommt in den Vordergrund")
        app.activate()
        check(app.descendants(matching: .any)["feedback.done"].firstMatch.waitForExistence(timeout: 8),
              "Zurück in der App: Bestätigung mit „Erledigt“")
        shot("feedback-bestaetigung")
        tap(app.buttons["feedback.done"], "Erledigt")
        back()

        let tour = scrollUntilExists(app.descendants(matching: .any)["help.tour"].firstMatch, maxSwipes: 8)
        check(tour.exists, "Zeile „App-Einführung ansehen“")
        tap(tour, "App-Einführung ansehen")
        let skip = app.buttons["tour.skip"]
        check(skip.waitForExistence(timeout: 8), "Tour öffnet")
        shot("tour-aus-hilfe")
        tap(skip, "Tour überspringen")
        check(app.navigationBars["Hilfe & Feedback"].waitForExistence(timeout: 6), "Zurück auf „Hilfe & Feedback“")
    }
}

/// Paket „Brücke“ (docs/14): Mac koppeln und Fahrten mit Sekundendaten anreichern. Alle Tests laufen mit
/// `-uiBridgeStub YES` (ein Stub-Mac „Lenas MacBook Air“, Code 482913, die acht neuesten Fahrten ohne Sekundendaten).
final class AuditBridgeTests: AuditCase {
    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Leistung → Karte „Sekundendaten vom Mac“ → Einrichtung (Schritte, Mac suchen).
    private func openBridgeSetup() {
        launch(extra: ["-uiBridgeStub", "YES"])
        openTab("Verlauf")
        tap(anyElement("performance.open"), "Leistung öffnen")
        route = "leistung"
        check(waitFast(app.navigationBars["Leistung"]), "Leistung-Screen öffnet")
        let cta = scrollUntilExists(anyElement("performance.bridgeCTA"), maxSwipes: 6)
        check(cta.exists, "Karte „Volle Leistungskurve für jede Fahrt“ mit [Einrichten]")
        check(text(containing: "0 von 8 Fahrten mit Sekundendaten").exists, "Abdeckung „0 von 8 Fahrten mit Sekundendaten“")
        shot("cta")
        tap(cta, "Einrichten")
        route = "bruecke"
        check(waitFast(app.navigationBars["Mac-Brücke"]), "Einrichtung öffnet")
    }

    private func enterCode(_ code: String) {
        let field = anyElement("bridge.code")
        check(waitFast(field, timeout: 6), "Code-Feld")
        type(field, code, "Code \(code)")
    }

    func test33_MacBridgePairing() {
        openBridgeSetup()
        check(anyElement("bridge.steps").exists, "Drei Schritte sichtbar")
        check(text(containing: "IndoorCoach Brücke auf dem Mac öffnen").exists, "Schritt 1")
        check(text(containing: "MyWhoosh-Ordner freigeben").exists, "Schritt 2")
        check(text(containing: "Code eingeben").exists, "Schritt 3")
        check(button(containing: "FIT-Datei importieren").exists, "Fußzeile „Kein Mac? FIT-Datei importieren“")
        let mac = anyElement("bridge.mac.0")
        check(waitFast(mac, timeout: 10), "Stub-Mac „Lenas MacBook Air“ gefunden")
        check(mac.label.contains("Lenas MacBook Air"), "Mac-Name im Label (\(mac.label))")
        shot("einrichtung")
        accessibilityAudit("Mac-Brücke-Einrichtung")

        tap(mac, "Mac wählen")
        enterCode("111111")
        check(waitFast(anyElement("bridge.error"), timeout: 8), "Fehlertext bei falschem Code")
        check(!anyElement("bridge.paired").exists, "Falscher Code koppelt nicht")
        shot("falscher-code")
        accessibilityAudit("Mac-Brücke-Falscher-Code")

        enterCode("482913")
        check(waitFast(anyElement("bridge.paired"), timeout: 12), "Gekoppelt")
        check(anyElement("bridge.paired").label.contains("Lenas MacBook Air"), "Gekoppelt mit „Lenas MacBook Air“ (\(anyElement("bridge.paired").label))")
        let coverage = anyElement("bridge.coverage")
        check(waitFast(coverage), "Abdeckungstext")
        check(coverage.label.contains("von") && coverage.label.contains("Fahrten mit Sekundendaten"),
              "Abdeckung „X von Y Fahrten mit Sekundendaten“ (\(coverage.label))")
        check(coverage.label.hasPrefix("3 von 10"), "Drei Fahrten angereichert bzw. neu (\(coverage.label))")
        check(anyElement("bridge.syncNow").exists && anyElement("bridge.unpair").exists, "„Jetzt abholen“ und „Kopplung lösen“")
        shot("gekoppelt")
        // The pickup banner fades out after a few seconds; auditing while it disappears hits a vanished element.
        let bannerGone = Date().addingTimeInterval(8)
        while text(containing: "Vom Mac").exists && Date() < bannerGone { usleep(250_000) }
        accessibilityAudit("Mac-Brücke-Gekoppelt")

        tap(anyElement("bridge.unpair"), "Kopplung lösen")
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Kopplung lösen' AND identifier != 'bridge.unpair'")).firstMatch
        tap(confirm, "Kopplung lösen bestätigen")
        check(waitFast(anyElement("bridge.steps"), timeout: 6), "Nach dem Lösen wieder die Einrichtung")
    }

    func test34_BridgeSyncEnrichesRides() {
        openBridgeSetup()
        tap(anyElement("bridge.mac.0"), "Mac wählen", timeout: 10)
        enterCode("482913")
        check(waitFast(anyElement("bridge.paired"), timeout: 12), "Gekoppelt")
        check(waitForBanner(containing: "Vom Mac: 2 neu, 1 ergänzt", timeout: 4), "Banner nach der Kopplung")

        tap(anyElement("bridge.syncNow"), "Jetzt abholen")
        check(waitForBanner(containing: "Neue Fahrt vom Mac: 52 min · NP 214 W", timeout: 10), "Banner „Neue Fahrt vom Mac“")
        shot("banner")
        check(anyElement("bridge.coverage").label.hasPrefix("4 von 11"), "Abdeckung wächst auf 4 von 11 (\(anyElement("bridge.coverage").label))")

        // The banner covers the navigation bar for a few seconds.
        let gone = Date().addingTimeInterval(8)
        while text(containing: "Neue Fahrt vom Mac").exists && Date() < gone { usleep(250_000) }
        back()                                         // Leistung
        check(waitFast(app.navigationBars["Leistung"]), "Zurück in Leistung")
        settle()
        check(!anyElement("performance.bridgeCTA").exists, "Karte verschwindet nach der Kopplung")
        back()
        route = "verlauf"
        check(waitFast(app.navigationBars["Verlauf"]), "Zurück im Verlauf")
        let badged = button(containing: "Sekundendaten")
        check(scrollUntilExists(badged, maxSwipes: 4).exists, "Verlauf: Fahrt mit Abzeichen „Sekundendaten“")
        shot("abzeichen")
        accessibilityAudit("Verlauf-Abzeichen")

        openConnections()
        let row = scrollUntilExists(anyElement("profile.bridge"), maxSwipes: 10)
        check(row.exists, "Dienste & Geräte: Zeile „Sekundendaten vom Mac“")
        check(row.label.contains("Verbunden"), "Zeile zeigt den Status (\(row.label))")
        shot("profil")
    }
}
