import SwiftUI

/// How the first-launch onboarding ended.
public enum OnboardingChoice: Sendable {
    /// "Mit Strava verbinden": close and jump to the Strava section in Profil (OAuth stays there).
    case strava
    /// "Erst mit Demo-Daten ansehen".
    case demo
    /// "Überspringen": defaults (and anything already changed) are kept.
    case skipped
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, profile, data
}

/// First-launch onboarding (B01): Willkommen → Dein Profil → Daten. Edits the profile directly, like ProfileView.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var step: OnboardingStep = .welcome
    var onFinish: (OnboardingChoice) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch step {
                case .welcome: welcome
                case .profile: profile
                case .data: data
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .id(step) // every step starts at the top
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .onChange(of: step) { titleFocused = true }
    }

    // MARK: Bars

    private var topBar: some View {
        HStack {
            if step != .welcome {
                Button {
                    go(to: OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome)
                } label: {
                    Label("Zurück", systemImage: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            // Both choices on the last step end onboarding anyway.
            if step != .data {
                Button { onFinish(.skipped) } label: {
                    Text("Überspringen").frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                }
                .accessibilityHint("Startet die App mit den Standardwerten. Alles lässt sich später im Profil ändern.")
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .background(Theme.canvas)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            switch step {
            case .welcome, .profile:
                Button {
                    go(to: OnboardingStep(rawValue: step.rawValue + 1) ?? .data)
                } label: {
                    Text(step == .welcome ? "Los geht’s" : "Weiter").frame(maxWidth: .infinity)
                }
                .buttonStyle(.jelly)
                .disabled(step == .profile && model.profile.trainingDays.isEmpty)
                .accessibilityIdentifier("onboarding.next")
            case .data:
                Button {
                    onFinish(.strava)
                } label: {
                    Label("Mit Strava verbinden", systemImage: "link").frame(maxWidth: .infinity)
                }
                .buttonStyle(.jelly)
                .accessibilityHint("Öffnet die Strava-Einrichtung im Profil.")
                .accessibilityIdentifier("onboarding.strava")
                Button {
                    onFinish(.demo)
                } label: {
                    Text("Erst mit Demo-Daten ansehen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.soft)
                .accessibilityIdentifier("onboarding.demo")
            }
            PageIndicator(current: step.rawValue, count: OnboardingStep.allCases.count)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private func go(to next: OnboardingStep) {
        withAnimation(.snappy(duration: 0.25)) { step = next }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.largeTitle.weight(.bold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($titleFocused)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: "figure.indoor.cycle")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 88, height: 88)
                    .background(Theme.sunset, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .accessibilityHidden(true)
            }
            title("Willkommen bei IndoorCoach")
            VStack(alignment: .leading, spacing: 14) {
                feature("sparkles", "Claude plant deine Woche – passend zu deinen Strava-Fahrten.")
                feature("snowflake", "Im Winter Arc baust du Fitness auf bis zum Frühjahr.")
                feature("square.and.arrow.up", "Jede Einheit geht als .zwo direkt zu MyWhoosh.")
            }
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
        }
        .font(.body)
    }

    private var profile: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            title("Dein Profil")
            Text("Passt so? Dann einfach weiter. Alles lässt sich später im Profil ändern.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Card(title: "FTP", systemImage: "bolt.fill") {
                Stepper(value: $model.profile.ftp, in: 80...500, step: 5) {
                    Text("\(model.profile.ftp) W").font(.title2.weight(.semibold)).monospacedDigit()
                }
                .accessibilityLabel("FTP")
                .accessibilityValue("\(model.profile.ftp) Watt")
                .accessibilityIdentifier("onboarding.ftp")
                hint("Deine Dauerleistung für eine Stunde. Kein aktueller Wert? 250 W passen für den Start.")
            }

            Card(title: "Trainingstage", systemImage: "calendar") {
                WeekdayPicker(days: $model.profile.trainingDays)
                hint(model.profile.trainingDays.isEmpty
                     ? "Wähle mindestens einen Tag."
                     : "Der Coach plant nur an diesen Tagen.")
            }

            Card(title: "Wochenbudget", systemImage: "clock") {
                Stepper(value: $model.profile.weeklyHours, in: 1...20, step: 0.5) {
                    Text("\(Formatters.decimal(model.profile.weeklyHours, digits: 1)) h pro Woche")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                }
                .accessibilityLabel("Wochenbudget")
                .accessibilityValue("\(Formatters.decimal(model.profile.weeklyHours, digits: 1)) Stunden pro Woche")
                .accessibilityIdentifier("onboarding.weeklyHours")
                hint("So viel Zeit hast du pro Woche für das Training.")
            }
        }
    }

    private var data: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Deine Fahrten")
            Text("Woher sollen die Daten kommen?")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Card(title: "Strava", systemImage: "link") {
                Text("Lädt deine Fahrten der letzten sieben Monate. Du brauchst dafür eine eigene Strava-API-App – im Profil zeigen wir dir, wie.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Card(title: "Demo-Daten", systemImage: "play.circle") {
                Text("Zwölf Wochen Beispielfahrten und ein fertiger Plan. Strava verbindest du später im Profil.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.rowSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Weekday chips like in ProfileView; wraps onto two rows at accessibility text sizes.
struct WeekdayPicker: View {
    @Binding var days: [Int]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: typeSize.isAccessibilitySize ? 3 : 7)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.removeAll { $0 == day } } else { days.append(day); days.sort() }
                } label: {
                    Text(AthleteProfile.weekdayNames[day] ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(on ? Theme.ink : .primary)
                        .background(on ? AnyShapeStyle(Theme.sunset) : AnyShapeStyle(.quaternary),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AthleteProfile.weekdayLongNames[day] ?? "")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Step dots; the current one is a wide accent capsule. Read as one element ("Schritt 2 von 3").
struct PageIndicator: View {
    var current: Int
    var count: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.accent : Theme.rowSecondary)
                    .frame(width: index == current ? 24 : 8, height: 8)
            }
        }
        .frame(minHeight: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schritt \(current + 1) von \(count)")
        .accessibilityIdentifier("onboarding.pageIndicator")
    }
}

// MARK: - Presentation

extension View {
    /// Full-screen onboarding over RootView. It can only end through one of its buttons.
    func onboardingCover(isPresented: Bool, onFinish: @escaping (OnboardingChoice) -> Void) -> some View {
        let binding = Binding(get: { isPresented }, set: { _ in })
        #if os(iOS)
        return fullScreenCover(isPresented: binding) { OnboardingView(onFinish: onFinish) }
        #else
        return sheet(isPresented: binding) { OnboardingView(onFinish: onFinish).interactiveDismissDisabled() }
        #endif
    }

    /// Profil: scrolls to the Strava section when onboarding ended with "Mit Strava verbinden".
    func scrollsToStravaSectionOnRequest() -> some View { modifier(StravaSectionScroller()) }
}

extension ProfileView {
    static let stravaSectionID = "profile.strava"
}

private struct StravaSectionScroller: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.task(id: model.stravaSetupRequested) {
                guard model.stravaSetupRequested else { return }
                // Let the cover dismiss and the tab lay out first.
                guard (try? await Task.sleep(for: .milliseconds(450))) != nil else { return }
                withAnimation { proxy.scrollTo(ProfileView.stravaSectionID, anchor: .top) }
                model.stravaSetupRequested = false
            }
        }
    }
}
