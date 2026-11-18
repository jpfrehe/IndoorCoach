import XCTest

/// Package S: planned vs. actual per interval. Needs the main session's integration
/// (`IntervalComplianceCard(workout:)` in WorkoutDetailView, `model.applyComplianceSeed()` in RootView's DEBUG startup).
final class AuditComplianceTests: AuditCase {

    func test37_IntervalCompliance() {
        launch(seed: "demo", extra: ["-uiComplianceSeed", "YES"])
        openTab("Plan")
        route = "plan"

        let past = button(containing: "Vergangene Einheiten")
        tap(past, "Vergangene Einheiten")
        let workoutRow = button(containing: "Sweet Spot 2×20")
        check(scrollUntilExists(workoutRow, maxSwipes: 4).exists, "Plan: erledigte Einheit „Sweet Spot 2×20“")
        tap(workoutRow, "Einheit Sweet Spot 2×20")

        route = "einheit"
        let card = anyElement("compliance.card")
        check(scrollUntilExists(card, maxSwipes: 8).exists, "Karte „Soll/Ist“ sichtbar")
        let summary = anyElement("compliance.summary")
        check(summary.exists && summary.label.contains("2 von 2 Intervallen getroffen"), "Zusammenfassung (\(summary.label))")
        let row1 = anyElement("compliance.row.1")
        let row2 = anyElement("compliance.row.2")
        check(row1.exists && row1.label.contains("Soll 225 Watt") && row1.label.contains("getroffen"), "Zeile 1 (\(row1.label))")
        check(row2.exists && row2.label.contains("getroffen"), "Zeile 2 (\(row2.label))")
        check(anyElement("compliance.chart").exists, "Diagramm vorhanden")
        settle()
        shot("karte")
        accessibilityAudit("Soll/Ist")
    }

    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
