import Foundation

/// Content of the feature tour: pure data so it can be unit-tested (docs/12, O2).
enum TourPage: Int, CaseIterable, Identifiable, Sendable {
    case plan, myWhoosh, winterArc, consistency, progress

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .plan: "Claude plant deine Woche"
        case .myWhoosh: "Direkt in MyWhoosh"
        case .winterArc: "Dein Winter Arc"
        case .consistency: "Konstanz statt Streaks"
        case .progress: "Fortschritt sehen"
        }
    }

    var body: String {
        switch self {
        case .plan: "Sag, wie viel Zeit du hast. Claude verteilt passende Einheiten auf deine Trainingstage."
        case .myWhoosh: "Mit einem Tipp landet die Einheit in deinem MyWhoosh-Kalender. Abtippen musst du nichts."
        case .winterArc: "Jede Fahrt bringt dich im Level weiter, bis im Frühling die Sonne wieder scheint."
        case .consistency: "Es zählen Wochen, nicht Tage. Verpasst du mal eine, fängt dein Joker sie auf."
        case .progress: "Deine Leistungskurve zeigt, was du je Dauer schaffst. Neue Bestleistungen bekommen ein PR-Abzeichen."
        }
    }

    /// One VoiceOver description per illustration.
    var illustrationLabel: String {
        switch self {
        case .plan: "Illustration: Eine Wochenübersicht, in der nacheinander Balken für geplante Einheiten erscheinen."
        case .myWhoosh: "Illustration: Eine Einheit wandert in einen Kalender, danach erscheint ein Häkchen."
        case .winterArc: "Illustration: Ein Level-Ring füllt sich, eine Schneeflocke wird zur Sonne, die Level-Zahl steigt."
        case .consistency: "Illustration: Acht Wochenpunkte füllen sich, ein Joker-Schild fängt eine verpasste Woche ab."
        case .progress: "Illustration: Eine Leistungskurve zeichnet sich, ein PR-Abzeichen erscheint."
        }
    }

    static func isLast(index: Int) -> Bool { index >= allCases.count - 1 }

    static func primaryTitle(index: Int, context: FeatureTourContext) -> String {
        guard isLast(index: index) else { return "Weiter" }
        return context == .onboarding ? "Los geht’s" : "Fertig"
    }

    static func indicatorLabel(index: Int) -> String { "Seite \(index + 1) von \(allCases.count)" }
}

/// Small easing helpers for the time-driven illustrations.
enum TourMath {
    /// 0…1 progress of `t` inside the window `from…to`.
    static func segment(_ t: Double, from: Double, to: Double) -> Double {
        guard to > from else { return t >= to ? 1 : 0 }
        return min(1, max(0, (t - from) / (to - from)))
    }

    static func easeInOut(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }

    static func easeOut(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return 1 - (1 - c) * (1 - c) * (1 - c)
    }

    /// Damped spring from 0 to 1 with a small overshoot.
    static func pop(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        if c == 0 { return 0 }
        return 1 - exp(-6 * c) * cos(11 * c)
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}
