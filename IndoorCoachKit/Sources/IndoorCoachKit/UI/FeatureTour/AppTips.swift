import Foundation
import SwiftUI
import TipKit

/// Contextual tips (docs/12, O2): at most four, shown only after onboarding is complete.
public enum AppTips {
    /// Same key as `AppModel.Keys.onboardingCompleted`.
    static let onboardingCompletedKey = "onboarding.completed.v1"

    enum TestingMode: Equatable { case hide, show, normal }

    /// DEBUG launch arguments: UI-test launches (`-uiSeed`, `-uiOnboarding`) hide all tips unless `-uiTips YES`.
    static func testingMode(uiSeed: String?, uiOnboarding: String?, uiTips: String?) -> TestingMode {
        if uiTips == "YES" { return .show }
        if uiSeed != nil || uiOnboarding != nil { return .hide }
        return .normal
    }

    /// Texts of the four tips (kept in one place for tests).
    static let copy: [(title: String, message: String)] = [
        ("Woche planen", "Tippe auf „Planen“ – Claude baut dir eine Woche passend zu Form und Zielen."),
        ("Tippe für Level, Serie und Reise", "Hier findest du dein Level, deine Konstanz und die Winter-Reise."),
        ("An MyWhoosh senden", "Schickt die Einheit in deinen MyWhoosh-Kalender."),
        ("Deine Leistung", "Leistungskurve, Bestleistungen und VO₂max auf einen Blick.")
    ]

    /// Set to true once onboarding is done; every tip's rule waits for it.
    @Parameter static var onboardingComplete: Bool = false

    /// Call once at app start. Safe to call again.
    @MainActor public static func configure() {
        #if DEBUG
        let args = UserDefaults.standard
        switch testingMode(uiSeed: args.string(forKey: "uiSeed"), uiOnboarding: args.string(forKey: "uiOnboarding"),
                           uiTips: args.string(forKey: "uiTips")) {
        case .hide: Tips.hideAllTipsForTesting()
        case .show: Tips.showAllTipsForTesting()
        case .normal: break
        }
        #endif
        // Without a stored flag (fresh install) onboarding is still pending; the app updates this via `setOnboardingComplete`.
        if let stored = UserDefaults.standard.object(forKey: onboardingCompletedKey) as? Bool { onboardingComplete = stored }
        try? Tips.configure([.displayFrequency(.hourly)])
    }

    /// Called by the app whenever `AppModel.needsOnboarding` changes.
    @MainActor public static func setOnboardingComplete(_ done: Bool) { onboardingComplete = done }
}

struct PlanTip: Tip {
    var title: Text { Text(AppTips.copy[0].title) }
    var message: Text? { Text(AppTips.copy[0].message) }
    var image: Image? { Image(systemName: "sparkles") }
    var rules: [Rule] { [#Rule(AppTips.$onboardingComplete) { $0 }] }
}

struct WinterArcTip: Tip {
    var title: Text { Text(AppTips.copy[1].title) }
    var message: Text? { Text(AppTips.copy[1].message) }
    var image: Image? { Image(systemName: "snowflake") }
    var rules: [Rule] { [#Rule(AppTips.$onboardingComplete) { $0 }] }
}

struct SendToMyWhooshTip: Tip {
    var title: Text { Text(AppTips.copy[2].title) }
    var message: Text? { Text(AppTips.copy[2].message) }
    var image: Image? { Image(systemName: "paperplane.fill") }
    var rules: [Rule] { [#Rule(AppTips.$onboardingComplete) { $0 }] }
}

struct PerformanceTip: Tip {
    var title: Text { Text(AppTips.copy[3].title) }
    var message: Text? { Text(AppTips.copy[3].message) }
    var image: Image? { Image(systemName: "bolt.fill") }
    var rules: [Rule] { [#Rule(AppTips.$onboardingComplete) { $0 }] }
}
