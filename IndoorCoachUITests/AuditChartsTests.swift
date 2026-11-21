import XCTest

/// Diagramm-Galerie (nur DEBUG, `-uiChartGallery YES`): alle Varianten des Workout-Profils und die Segmentbalken
/// hell, dunkel und in großer Schrift. Screenshots je Bildschirmseite plus Accessibility-Audit (docs/21, AP7).
@MainActor
final class AuditChartsTests: AuditCase {
    func testChartGallery() {
        let combos: [(size: String, tag: String, dark: Bool)] = [
            ("UICTContentSizeCategoryL", "L-hell", false),
            ("UICTContentSizeCategoryL", "L-dunkel", true),
            ("UICTContentSizeCategoryAccessibilityXXXL", "AX5", false)
        ]
        for combo in combos {
            XCUIDevice.shared.appearance = combo.dark ? .dark : .light
            app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-uiChartGallery", "YES",
                                   "-UIPreferredContentSizeCategoryName", combo.size]
            app.launch()
            route = "galerie"
            check(waitFast(text(containing: "Diagramm-Galerie"), timeout: 10), "Galerie geöffnet @\(combo.tag)")
            check(app.descendants(matching: .any).matching(identifier: "profile.mini").firstMatch.waitForExistence(timeout: 4),
                  "Mini-Profil auffindbar (profile.mini) @\(combo.tag)")
            for page in 0..<16 {
                settle()
                shot("\(combo.tag)-\(String(format: "%02d", page))")
                if page == 0 || page == 8 { accessibilityAudit("Galerie-\(page)@\(combo.tag)") }
                app.swipeUp(velocity: .slow)
            }
            app.terminate()
        }
        XCUIDevice.shared.appearance = .light
    }
}
