import SwiftUI

/// Hinweiszeile in der Einführung (kleine, zurückhaltende Schrift).
struct OnboardingHint: View {
    var text: String
    var symbol: String?
    init(_ text: String, symbol: String? = nil) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        Group {
            if let symbol {
                Label {
                    Text(text).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol)
                }
            } else {
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.rowSecondary)
    }
}

// MARK: - Schritt 2 · Womit fährst du drinnen?

/// Frage 1 (Mehrfachauswahl) mit der Folgefrage „Worauf läuft MyWhoosh bei dir?“, die nur bei `asksDevice` erscheint,
/// dem Tipp bei „Noch keine App“ und dem Link „Alle Dienste zeigen“ (docs/20 §6.3).
struct OnboardingRidesStep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var questionFocused: Bool
    /// Scrollt die umgebende Ansicht zu einer Kennung.
    var scrollTo: (String) -> Void
    var onShowAll: () -> Void

    static let deviceQuestionID = "onboarding.deviceQuestion"

    private static let apps: [ChoiceOption<RideApp>] = [
        ChoiceOption(value: .myWhoosh, title: "MyWhoosh", symbol: "figure.indoor.cycle", identifier: "onboarding.ride.myWhoosh"),
        ChoiceOption(value: .zwift, title: "Zwift", symbol: "figure.indoor.cycle", identifier: "onboarding.ride.zwift"),
        ChoiceOption(value: .rouvy, title: "Rouvy", symbol: "figure.indoor.cycle", identifier: "onboarding.ride.rouvy"),
        ChoiceOption(value: .other, title: "Andere App", subtitle: "z. B. TrainerRoad", symbol: "app.badge",
                     identifier: "onboarding.ride.other"),
        ChoiceOption(value: .none, title: "Noch keine App", subtitle: "nur Rolle oder weiß nicht", symbol: "questionmark.circle",
                     identifier: "onboarding.ride.none", isExclusive: true)
    ]

    private static let devices: [ChoiceOption<RideDevice>] = [
        ChoiceOption(value: .mac, title: "Mac", symbol: "laptopcomputer", identifier: "onboarding.device.mac"),
        ChoiceOption(value: .windows, title: "Windows-PC", symbol: "pc", identifier: "onboarding.device.windows"),
        ChoiceOption(value: .tablet, title: "iPad oder Tablet", symbol: "ipad", identifier: "onboarding.device.tablet"),
        ChoiceOption(value: .appleTV, title: "Apple TV", symbol: "appletv", identifier: "onboarding.device.appleTV"),
        ChoiceOption(value: .phone, title: "Handy", symbol: "iphone", identifier: "onboarding.device.phone"),
        ChoiceOption(value: .unknown, title: "Weiß ich nicht", symbol: "questionmark.circle", identifier: "onboarding.device.unknown")
    ]

    private var answers: ServiceAnswers { model.onboardingServices.answers }
    private var asksDevice: Bool { ServiceRecommender.asksDevice(answers, model.serviceAvailability) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ChoiceChipGrid(label: "Womit fährst du drinnen? Mehrere Antworten möglich",
                           options: Self.apps, selection: answers.rideApps) { value in
                var state = model.onboardingServices
                state.answers.rideApps = ChoiceSelection.toggled(state.answers.rideApps, value, exclusive: [.none])
                if !state.answers.rideApps.contains(.myWhoosh) { state.answers.myWhooshDevice = nil }
                model.onboardingServices = state
            }

            if asksDevice { deviceQuestion }

            if answers.rideApps.contains(.none) {
                OnboardingHint("Kein Problem. IndoorCoach plant deine Woche auch so. Tipp: Mit einer kostenlosen App wie MyWhoosh stellt sich deine Rolle selbst auf die richtigen Watt ein, falls sie das kann.",
                               symbol: "lightbulb")
                    .accessibilityIdentifier("onboarding.ride.noneTip")
            }

            Button(action: onShowAll) {
                Text("Ich kenne mich aus – alle Dienste zeigen")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .foregroundStyle(Theme.accent)
            .accessibilityHint("Springt zu allen Diensten, ohne weitere Fragen.")
            .accessibilityIdentifier("onboarding.showAll")
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: asksDevice)
        .onChange(of: asksDevice) { _, shown in
            guard shown else { return }
            AccessibilityNotification.Announcement("Neue Frage").post()
            questionFocused = true
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation { scrollTo(Self.deviceQuestionID) }
            }
        }
    }

    private var deviceQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Worauf läuft MyWhoosh bei dir?")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($questionFocused)
            ChoiceChipGrid(label: "Worauf läuft MyWhoosh bei dir? Eine Antwort", options: Self.devices,
                           selection: answers.myWhooshDevice.map { [$0] } ?? [], mode: .single) { value in
                model.onboardingServices.answers.myWhooshDevice = value
            }
            if answers.myWhooshDevice == .mac {
                OnboardingHint("Gut: Dann kann ein kleiner Helfer auf dem Mac jede Fahrt im Detail ans iPhone schicken. Mehr dazu gleich.",
                               symbol: "checkmark.circle")
                    .accessibilityIdentifier("onboarding.device.macHint")
            }
        }
        .id(Self.deviceQuestionID)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Schritt 3 · Was hast du sonst noch?

struct OnboardingExtrasStep: View {
    @Environment(AppModel.self) private var model

    private static let extras: [ChoiceOption<ExtraGear>] = [
        ChoiceOption(value: .appleWatch, title: "Apple Watch", symbol: "applewatch", identifier: "onboarding.extra.appleWatch"),
        ChoiceOption(value: .garminWahoo, title: "Garmin oder Wahoo", subtitle: "Uhr oder Radcomputer", symbol: "watch.analog",
                     identifier: "onboarding.extra.garminWahoo"),
        ChoiceOption(value: .heartStrap, title: "Brustgurt", subtitle: "misst den Puls", symbol: "heart.circle",
                     identifier: "onboarding.extra.heartStrap"),
        ChoiceOption(value: .strava, title: "Strava", symbol: "figure.outdoor.cycle", identifier: "onboarding.extra.strava"),
        ChoiceOption(value: .none, title: "Nichts davon", symbol: "minus.circle", identifier: "onboarding.extra.none", isExclusive: true)
    ]

    var body: some View {
        ChoiceChipGrid(label: "Was hast du sonst noch? Mehrere Antworten möglich",
                       options: Self.extras, selection: model.onboardingServices.answers.extras) { value in
            var state = model.onboardingServices
            state.answers.extras = ChoiceSelection.toggled(state.answers.extras, value, exclusive: [.none])
            model.onboardingServices = state
        }
    }
}
