import SwiftUI

/// Where the feature tour is shown. Onboarding ends on "Los geht’s", Help on "Fertig".
public enum FeatureTourContext: Sendable {
    case onboarding
    case help
}

/// Animated introduction to the app's main features (package O2, docs/12).
/// STUB: the API is fixed so O1 (onboarding) and O3 (help section) can present it; O2 replaces the body.
struct FeatureTourView: View {
    var context: FeatureTourContext
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("So funktioniert IndoorCoach").font(.largeTitle.weight(.bold))
            Button(context == .onboarding ? "Los geht’s" : "Fertig", action: onFinish)
                .buttonStyle(.jelly)
                .accessibilityIdentifier("tour.finish")
        }
        .padding(16)
    }
}
