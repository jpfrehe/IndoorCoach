import XCTest

/// Shared helpers for the UX-audit walkthroughs.
///
/// Every interaction is logged as a `MANIFEST|time|test|route|action|selector` line on stdout so the
/// Interaction Manifest can be rebuilt from the xcodebuild log. Screenshots are kept as attachments
/// (`xcresulttool export attachments`). Soft checks print `CHECK|PASS|…` / `CHECK|FAIL|…` and do not stop
/// the walkthrough, so one finding does not hide the next.
@MainActor
class AuditCase: XCTestCase {
    var app = XCUIApplication()
    var route = "start"

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // MARK: Launch

    func launch(seed: String? = "demo", extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        var args = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        if let seed { args += ["-uiSeed", seed] }
        app.launchArguments = args + extra
        let start = Date()
        app.launch()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 15)
        log("Launched app seed=\(seed ?? "none") \(extra.joined(separator: " "))",
            "launch→tabBar \(ms(since: start)) ms")
    }

    // MARK: Logging

    func log(_ action: String, _ selector: String = "") {
        let name = String(describing: self.name).replacingOccurrences(of: "|", with: "/")
        print("MANIFEST|\(Self.clock.string(from: .now))|\(name)|\(route)|\(action)|\(selector)")
    }

    func check(_ condition: Bool, _ message: String) {
        print("CHECK|\(condition ? "PASS" : "FAIL")|\(route)|\(message)")
    }

    func timing(_ label: String, _ milliseconds: Int) {
        print("TIMING|\(route)|\(label)|\(milliseconds)")
    }

    func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }

    func shot(_ label: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        let name = "\(self.shortName)-\(route)-\(label)"
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        log("Screenshot", name)
    }

    var shortName: String {
        String(describing: name).components(separatedBy: " ").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? "test"
    }

    // MARK: Interaction

    @discardableResult
    func tap(_ element: XCUIElement, _ description: String, timeout: TimeInterval = 6) -> Bool {
        // Träge Listen/Formulare halten Zeilen außerhalb des Bildschirms nicht bereit: erst kurz warten, dann bis dahin scrollen.
        if !element.waitForExistence(timeout: min(timeout, 3)) { _ = scrollFinding(element) }
        guard element.exists else {
            check(false, "Element nicht gefunden: \(description)")
            return false
        }
        if !element.isHittable { scrollTo(element) }
        clearOfTabBar(element)
        let target = selector(element) // read before the tap; the element may disappear
        element.tap()
        log("Tapped \(description)", target)
        return true
    }

    func type(_ element: XCUIElement, _ text: String, _ description: String) {
        guard element.waitForExistence(timeout: 6) else {
            check(false, "Eingabefeld nicht gefunden: \(description)")
            return
        }
        // Audit 3: a field under the open keyboard (or its "Fertig" bar) still counts as hittable; the tap would land
        // on the keyboard. Close it first, as a user would, then bring the field into view.
        // Drag the list in the area above the keyboard until the field is clear (like a user scrolling).
        let keyboard = app.keyboards.firstMatch
        var lifts = 0
        while keyboard.exists, element.exists, !element.frame.isEmpty, element.frame.maxY > keyboard.frame.minY - 52, lifts < 5 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
            from.press(forDuration: 0.05, thenDragTo: to)
            lifts += 1
        }
        if !element.isHittable { scrollTo(element) }
        clearOfTabBar(element)   // audit 3, iPhone SE: the key field can sit behind the floating tab bar
        let target = selector(element)
        element.tap()
        // Audit 3 (iPhone SE): while the keyboard slides in, the list moves the field; a tap during that animation
        // can miss. Wait for focus and tap once more instead of typing into nothing.
        if !waitForKeyboardFocus(element) {
            if !element.isHittable { scrollTo(element) }
            element.tap()
            _ = waitForKeyboardFocus(element)
        }
        element.typeText(text)
        log("Typed \"\(text)\" into \(description)", target)
    }

    /// iPhone SE: an element under a fixed bottom bar (onboarding "Weiter") still counts as hittable. Swipe it clear.
    func lift(_ element: XCUIElement, above bar: XCUIElement, maxSwipes: Int = 4) {
        var n = 0
        while element.exists, bar.exists, element.frame.maxY > bar.frame.minY - 8, n < maxSwipes {
            app.swipeUp(velocity: .slow); n += 1
        }
    }

    func waitForKeyboardFocus(_ element: XCUIElement, timeout: TimeInterval = 2) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element)
        return XCTWaiter.wait(for: [focused], timeout: timeout) == .completed
    }

    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var n = 0
        while !element.isHittable && n < maxSwipes {
            let existed = element.exists
            app.swipeUp(velocity: .slow)
            n += 1
            // Overshot: the lazy Form dropped the row above the visible area – come back once and stop.
            if existed && !element.exists { app.swipeDown(velocity: .slow); break }
        }
    }

    /// The floating tab bar lies over the scroll content: an element can be "hittable" while its centre sits under
    /// the bar, and the tap then lands on a tab. Scroll in small steps until the centre is clear of the bar.
    func clearOfTabBar(_ element: XCUIElement) {
        let bar = app.tabBars.firstMatch
        // Not under a sheet (bar not hittable) and not for the tab buttons themselves.
        guard bar.exists, bar.isHittable, element.exists, !bar.frame.contains(element.frame) else { return }
        var n = 0
        while element.exists, element.frame.midY > bar.frame.minY - 12, n < 4 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            from.press(forDuration: 0.05, thenDragTo: to)
            n += 1
        }
    }

    func selector(_ element: XCUIElement) -> String {
        let id = element.identifier.isEmpty ? "" : "#\(element.identifier) "
        return "\(id)\(element.elementType.name)[label=\"\(element.label)\"]"
    }

    func openTab(_ title: String) {
        let tabButton = app.tabBars.buttons[title]
        _ = tabButton.waitForExistence(timeout: 6)
        let start = Date()
        tap(tabButton, "Tab \(title)")
        _ = waitFast(app.navigationBars[title], timeout: 6)
        route = title.lowercased()
        timing("Tab \(title) → NavBar", ms(since: start))
    }

    /// Profil → Dienste & Geräte (docs/18): Strava, MyWhoosh, Mac-Brücke, Apple Health und Brustgurt liegen dort.
    func openConnections() {
        openTab("Profil")
        let row = app.descendants(matching: .any).matching(identifier: "profile.connections").firstMatch
        tap(scrollUntilExists(row, maxSwipes: 10), "Profil → Dienste & Geräte")
        _ = waitFast(app.navigationBars["Dienste & Geräte"], timeout: 6)
    }

    /// Dienste & Geräte → eine Detailseite (`profile.strava`, `profile.mywhoosh`, `profile.bridge`, …).
    func openService(_ identifier: String) {
        openConnections()
        let row = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        tap(scrollUntilExists(row, maxSwipes: 6), "Dienste & Geräte → \(identifier)")
    }

    func back() {
        tap(app.navigationBars.buttons["BackButton"], "Zurück-Button")
    }

    /// Workout / ride rows: SwiftUI exposes each list row as a button whose label contains "TSS".
    /// Workout/ride rows carry "… TSS …" in their label; the metric picker's "TSS" segment alone is not a row.
    func row(_ index: Int) -> XCUIElement {
        app.collectionViews.buttons.matching(NSPredicate(format: "label CONTAINS 'TSS' AND label != 'TSS'")).element(boundBy: index)
    }

    var rowCount: Int {
        app.collectionViews.buttons.matching(NSPredicate(format: "label CONTAINS 'TSS' AND label != 'TSS'")).count
    }

    func scrollUntilExists(_ element: XCUIElement, maxSwipes: Int = 8) -> XCUIElement {
        var n = 0
        while !element.exists && n < maxSwipes {
            app.swipeUp(velocity: .slow)
            n += 1
        }
        return element
    }

    /// Wie `scrollUntilExists`, aber in kleinen Schritten (ca. ein Drittel Bildschirm): Eine volle Wischgeste überspringt
    /// kleine Zeilen träger Listen, die nur im Baum stehen, solange sie sichtbar sind.
    @discardableResult
    func scrollFinding(_ element: XCUIElement, maxSteps: Int = 16) -> XCUIElement {
        var n = 0
        while !element.exists && n < maxSteps {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            from.press(forDuration: 0.05, thenDragTo: to)
            n += 1
        }
        return element
    }

    /// Polls every ~100 ms (waitForExistence polls once per second, which distorts timings).
    func waitFast(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if element.exists { return true }
            usleep(100_000)
        }
        return false
    }

    /// Wählt eine Übung im Katalog-Sheet über die Suche (die lange, träge Liste hält Zeilen außerhalb des Bildschirms
    /// nicht bereit – ohne Suchbegriff wäre der Treffer sonst abhängig von der Scrollposition).
    func pickExercise(id: String, name: String) {
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 4) {
            search.tap()
            search.typeText(name)
            log("Searched exercise", name)
        } else {
            check(false, "Suchfeld im Übungskatalog nicht gefunden")
        }
        tap(app.descendants(matching: .any).matching(identifier: "strength.pick.\(id)").firstMatch, name)
    }

    /// Sichtbarer Knopf mit genau diesem Titel (derselbe Titel kann auch auf einem verdeckten Bildschirm im Baum stehen).
    func visibleButton(_ label: String) -> XCUIElement {
        let all = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return all.first { $0.isHittable } ?? app.buttons[label].firstMatch
    }

    func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    func text(containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Text input regardless of whether SwiftUI backs it with a text field or a text view.
    func input(placeholder: String, timeout: TimeInterval = 6) -> XCUIElement {
        let predicate = NSPredicate(format: "placeholderValue CONTAINS[c] %@ OR label CONTAINS[c] %@ OR value BEGINSWITH[c] %@",
                                    placeholder, placeholder, placeholder)
        let candidates = [app.textFields.matching(predicate).firstMatch,
                          app.textViews.matching(predicate).firstMatch,
                          app.secureTextFields.matching(predicate).firstMatch]
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if let hit = candidates.first(where: { $0.exists }) { return hit }
            usleep(150_000)
        } while Date() < end
        return candidates[0]
    }

    func waitForBanner(containing text: String, timeout: TimeInterval = 6) -> Bool {
        let banner = self.text(containing: text)
        let found = banner.waitForExistence(timeout: timeout)
        log("Waited for banner \"\(text)\"", found ? selector(banner) : "nicht erschienen")
        return found
    }

    // MARK: Accessibility (axe-core equivalent)

    final class IssueBox: @unchecked Sendable { var count = 0; var occluded = 0 }

    /// Waits until a push/scroll has come to rest (audit 2): screenshots and contrast/clipping checks taken
    /// mid-transition measured half-visible text against the previous screen.
    func settle(_ seconds: TimeInterval = 1.2) {
        _ = app.navigationBars.buttons["BackButton"].waitForExistence(timeout: 3)
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Runs Apple's accessibility audit. Issues on elements that sit (partly) under the translucent tab bar or
    /// navigation bar are logged as `A11Y-OCCLUDED`: their contrast is measured against the bar material,
    /// not against the card the user sees once the content is scrolled into view.
    func accessibilityAudit(_ screen: String) {
        let box = IssueBox()
        let chrome = (app.tabBars.allElementsBoundByIndex + app.navigationBars.allElementsBoundByIndex
                      + app.keyboards.allElementsBoundByIndex)
            .map(\.frame).filter { !$0.isEmpty }
        let screenBounds = app.windows.firstMatch.frame
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                let frame = issue.element?.frame ?? .zero
                let element = issue.element.map { "\($0.elementType.name)[label=\"\($0.label)\" id=\"\($0.identifier)\"]" } ?? "-"
                let occluded = !frame.isEmpty && (chrome.contains { $0.intersects(frame) } || !screenBounds.contains(frame))
                // Position (audit 2): y range of the element and of the window, to tell edge effects from real issues.
                let position = frame.isEmpty ? "-" : "y=\(Int(frame.minY))…\(Int(frame.maxY))/\(Int(screenBounds.height))"
                print("\(occluded ? "A11Y-OCCLUDED" : "A11Y")|\(screen)|\(issue.auditType.name)|\(issue.compactDescription)|\(element)|\(position)")
                if issue.element == nil {
                    print("A11Y-DETAIL|\(screen)|\(issue.detailedDescription.replacingOccurrences(of: "\n", with: " "))")
                }
                if occluded { box.occluded += 1 } else { box.count += 1 }
                return true // record, keep walking
            }
        } catch {
            print("A11Y|\(screen)|error|\(error.localizedDescription)|-")
        }
        log("Accessibility audit \(screen): \(box.count) issues (+\(box.occluded) under system bars/keyboard)")
    }
}

extension XCUIElement.ElementType {
    var name: String {
        switch self {
        case .button: "button"
        case .staticText: "text"
        case .textField: "textField"
        case .secureTextField: "secureField"
        case .textView: "textView"
        case .switch: "switch"
        case .cell: "cell"
        case .image: "image"
        case .navigationBar: "navBar"
        case .stepper: "stepper"
        case .slider: "slider"
        case .other: "other"
        case .segmentedControl: "segmented"
        case .datePicker: "datePicker"
        case .link: "link"
        default: "type\(rawValue)"
        }
    }
}

extension XCUIAccessibilityAuditType {
    var name: String {
        switch self {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "sufficientElementDescription"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "other(\(rawValue))"
        }
    }
}
