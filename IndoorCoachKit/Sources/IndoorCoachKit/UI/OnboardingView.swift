import SwiftUI
#if os(iOS)
import UIKit
#endif

/// How the first-launch onboarding ended.
public enum OnboardingChoice: Sendable {
    /// "Strava oder FIT-Dateien? Unter Dienste & Geräte einrichten": close and open Profil → Dienste & Geräte → Strava (OAuth stays there).
    case strava
    /// "Kurze Tour ansehen": close, then RootView shows the feature tour full screen.
    case tour
    /// "Direkt starten": straight to Heute.
    case start
    /// "Überspringen": defaults (and anything already changed) are kept.
    case skipped
}

/// Sieben Schritte (docs/20 §4.1). `rides` zeigt vorläufig noch die MyWhoosh-Anmeldung, `extras` und `services` sind Platzhalter
/// bis zu den Paketen AP3/AP4.
enum OnboardingStep: Int, CaseIterable {
    case welcome, training, rides, extras, services, coach, done
}

/// First-launch onboarding: Willkommen → Dein Training → Trainings-App → Coach → Fertig.
/// Edits the profile directly, like ProfileView. The current step lives in `AppModel.onboardingStep`, so a relaunch resumes there.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var whooshEditing = 0
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var whooshBusy = false
    /// While typing, the bottom bar ("Später", "Ohne Claude weiter") would sit right above the keyboard and cover the
    /// form's own button ("Bei MyWhoosh anmelden", "Prüfen & speichern"); it steps aside until the keyboard is gone.
    @State private var keyboardVisible = false
    @ScaledMetric(relativeTo: .subheadline) private var guideBadge: CGFloat = 26
    var onFinish: (OnboardingChoice) -> Void

    private var step: OnboardingStep { OnboardingStep(rawValue: model.onboardingStep) ?? .welcome }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch step {
                case .welcome: welcome
                case .training: training
                case .rides: trainingApp
                case .extras: placeholder("Was hast du sonst noch?")
                case .services: placeholder("Für dich passt")
                case .coach: coach
                case .done: done
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .id(step) // every step starts at the top
        // iPhone SE: with the e-mail keyboard up, password and "Anmelden" sat half under it (audit 3). Keep the
        // button in view once the keyboard has moved in.
        .onChange(of: whooshEditing) {
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation { proxy.scrollTo(MyWhooshLoginForm.loginButtonID, anchor: .bottom) }
            }
        }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible { bottomBar }
        }
        .onChange(of: step) { titleFocused = true }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        #endif
    }

    // MARK: Bars

    private var topBar: some View {
        HStack {
            if step != .welcome {
                Button { go(to: step.rawValue - 1) } label: {
                    // At accessibility sizes "Zurück" and "Überspringen" no longer fit side by side ("Zu-rück"):
                    // the chevron alone carries the back action (VoiceOver still reads "Zurück").
                    // Branch on the view, not a type-erased style: calling a LabelStyle's makeBody directly reads
                    // its environment outside a view (SwiftUI runtime warning, audit 3).
                    Group {
                        if typeSize.isAccessibilitySize {
                            Label("Zurück", systemImage: "chevron.left").labelStyle(.iconOnly)
                        } else {
                            Label("Zurück", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                .disabled(whooshBusy)
                .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            // The last step has its own two ways out.
            if step != .done {
                Button { onFinish(.skipped) } label: {
                    Text("Überspringen")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                }
                .disabled(whooshBusy)
                .accessibilityHint("Startet die App mit den Standardwerten. Alles lässt sich später im Profil ändern.")
                .accessibilityIdentifier("onboarding.skip")
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Theme.accent)
        // Like a navigation bar: grows with Dynamic Type, but stops at AX2 so the content keeps its room.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .background(Theme.canvas)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            switch step {
            case .welcome:
                next("Los geht’s", style: .jelly)
            case .training:
                next("Weiter", style: .jelly).disabled(model.profile.trainingDays.isEmpty)
            case .rides:
                if model.isMyWhooshConnected && !whooshBusy {
                    next("Weiter", style: .jelly)
                } else {
                    next("Später", style: .soft, id: "onboarding.later").disabled(whooshBusy)
                }
            case .extras, .services:
                next("Weiter", style: .jelly)
            case .coach:
                if model.hasClaudeKey {
                    next("Weiter", style: .jelly)
                } else {
                    next("Ohne Claude weiter", style: .soft, id: "onboarding.noClaude")
                }
            case .done:
                Button { onFinish(.tour) } label: {
                    Label("Kurze Tour ansehen", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.jelly)
                .accessibilityIdentifier("onboarding.tour")
                Button { onFinish(.start) } label: {
                    Text("Direkt starten").frame(maxWidth: .infinity)
                }
                .buttonStyle(.soft)
                .accessibilityIdentifier("onboarding.start")
            }
            PageIndicator(current: step.rawValue, count: OnboardingStep.allCases.count)
        }
        .multilineTextAlignment(.center)
        // Buttons stay large but stop at AX3; at AX5 two of them filled half of an iPhone SE.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private func next(_ title: String, style: some ButtonStyle, id: String = "onboarding.next") -> some View {
        Button { go(to: step.rawValue + 1) } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(style)
        .accessibilityIdentifier(id)
    }

    private func go(to index: Int) {
        withAnimation(.snappy(duration: 0.25)) { model.onboardingStep = index }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.largeTitle.weight(.bold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($titleFocused)
    }

    private func lead(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 1 · Willkommen

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !typeSize.isAccessibilitySize {
                OnboardingHero().frame(maxWidth: .infinity)
            }
            title("Willkommen bei IndoorCoach")
            VStack(alignment: .leading, spacing: 14) {
                feature("sparkles", "Claude plant deine Woche – passend zu deinen Fahrten.")
                feature("snowflake", "Im Winter Arc baust du Fitness auf bis zum Frühjahr.")
                feature("square.and.arrow.up", "Jede Einheit geht direkt zu MyWhoosh.")
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

    // MARK: 2 · Dein Training

    private var training: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            title("Dein Training")
            lead("Passt so? Dann einfach weiter. Alles lässt sich später im Profil ändern.")

            Card(title: "FTP", systemImage: "bolt.fill") {
                Stepper(value: $model.profile.ftp, in: 80...500, step: 5) {
                    Text("\(model.profile.ftp) W").font(.title2.weight(.semibold)).monospacedDigit()
                }
                .accessibilityLabel("FTP")
                .accessibilityValue("\(model.profile.ftp) Watt")
                .accessibilityIdentifier("onboarding.ftp")
                Button {
                    withAnimation { model.estimateFTP() }
                } label: {
                    Text("Weiß ich nicht").frame(maxWidth: .infinity)
                }
                .buttonStyle(.soft)
                .accessibilityHint("Schätzt deinen FTP mit 2,5 Watt pro Kilogramm: \(AppModel.estimatedFTP(weightKg: model.profile.weightKg)) Watt.")
                .accessibilityIdentifier("onboarding.ftpUnknown")
                hint("Deine Dauerleistung für eine Stunde. „Weiß ich nicht“ schätzt 2,5 W/kg × Gewicht = \(AppModel.estimatedFTP(weightKg: model.profile.weightKg)) W.")
            }

            Card(title: "Gewicht", systemImage: "scalemass") {
                Stepper(value: $model.profile.weightKg, in: 40...150, step: 0.5) {
                    Text("\(Formatters.decimal(model.profile.weightKg, digits: 1)) kg")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                }
                .accessibilityLabel("Gewicht")
                .accessibilityValue("\(Formatters.decimal(model.profile.weightKg, digits: 1)) Kilogramm")
                .accessibilityIdentifier("onboarding.weight")
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

    /// Vorläufig, bis die Fragen- und Empfehlungsschritte gestaltet sind (AP3/AP4).
    private func placeholder(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title(text)
        }
    }

    // MARK: 3 · Trainings-App

    private var trainingApp: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Deine Trainings-App")
            lead("Mit MyWhoosh sieht der Coach deine Fahrten und schickt dir die Einheiten direkt dorthin.")

            if model.isMyWhooshConnected && !whooshBusy {
                Card(title: "MyWhoosh", systemImage: "figure.indoor.cycle") {
                    let count = model.importedRideCount
                    Label {
                        Text(count > 0 ? "Verbunden · \(count) \(count == 1 ? "Fahrt" : "Fahrten") geladen"
                                       : "Verbunden · noch keine Fahrten gefunden")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.done)
                    }
                    .accessibilityIdentifier("onboarding.myWhooshStatus")
                    if let user = model.myWhooshUser { hint(user) }
                }
            } else {
                Card(title: "MyWhoosh", systemImage: "figure.indoor.cycle") {
                    MyWhooshLoginForm(busy: $whooshBusy, onEditing: { whooshEditing += 1 })
                    hint("Dein Passwort wird nur zur Anmeldung gesendet und nicht gespeichert.")
                }
            }

            Button { onFinish(.strava) } label: {
                Text("Strava oder FIT-Dateien? Unter Dienste & Geräte einrichten")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .foregroundStyle(Theme.accent)
            .disabled(whooshBusy)
            .accessibilityHint("Beendet die Einführung und öffnet die Strava-Einrichtung unter Profil, Dienste und Geräte.")
            .accessibilityIdentifier("onboarding.strava")
        }
    }

    // MARK: 4 · Coach

    private var coach: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Dein Coach")
            lead("Claude erstellt deinen Wochenplan. Dafür brauchst du einen eigenen API-Key – das dauert zwei Minuten.")

            Card(title: "So kommst du an den Key", systemImage: "list.number") {
                guideStep(1, "Öffne die Claude Console und melde dich an.")
                guideStep(2, "Wähle „API Keys“ und dann „Create Key“.")
                guideStep(3, "Kopiere den Key und füge ihn unten ein.")
                Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                    Label("console.anthropic.com öffnen", systemImage: "arrow.up.right.square")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("onboarding.consoleLink")
            }

            Card(title: "API-Key", systemImage: "key.fill") {
                ClaudeKeyForm()
                hint("Ein Plan kostet etwa 0,10 $. Der Key bleibt im Schlüsselbund dieses iPhones.")
            }
        }
    }

    private func guideStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
                // Grows with the text; a fixed 26 pt circle slid under the first word at AX sizes.
                .frame(width: guideBadge, height: guideBadge)
                .background(Theme.sunset, in: Circle())
                .accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schritt \(number): \(text)")
    }

    // MARK: 5 · Fertig

    private var done: some View {
        let summary = model.onboardingSummary
        return VStack(alignment: .leading, spacing: 16) {
            title("Alles bereit")
            lead("Das hast du eingerichtet. Fehlendes holst du jederzeit im Profil nach.")
            Card {
                ForEach(summary.items) { item in
                    statusRow(item, detail: visualDetail(item, summary: summary))
                }
            }
            if !summary.coachReady {
                hint("Ohne Claude-Key bekommst du einen Demo-Plan.")
            }
        }
    }

    private func visualDetail(_ item: OnboardingSummary.Item, summary: OnboardingSummary) -> String {
        switch item.title {
        case "Profil":
            return summary.profileReady
                ? "FTP \(model.profile.ftp) W · \(model.profile.trainingDays.count) Trainingstage" : "Trainingstag fehlt"
        case "MyWhoosh":
            guard summary.myWhooshConnected else { return "Später unter Dienste & Geräte" }
            return summary.rideCount > 0 ? "\(summary.rideCount) Fahrten geladen" : "Verbunden"
        default:
            return summary.coachReady ? "Claude-Key gespeichert" : "Später unter Profil → Coach · Claude"
        }
    }

    private func statusRow(_ item: OnboardingSummary.Item, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.isDone ? "checkmark.circle.fill" : "minus.circle")
                .font(.title3)
                .foregroundStyle(item.isDone ? Theme.done : Theme.rowSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier("onboarding.status.\(item.title.lowercased())")
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.rowSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Hero

/// Welcome motif: the app icon tile with pulsing rings and three bobbing badges. Still when "Bewegung reduzieren" is on.
struct OnboardingHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                HeroArt(phase: false)
            } else {
                PhaseAnimator([false, true]) { phase in
                    HeroArt(phase: phase)
                } animation: { _ in .easeInOut(duration: 2.2) }
            }
        }
        .frame(height: 190)
        .accessibilityHidden(true)
    }

    private struct HeroArt: View {
        var phase: Bool

        var body: some View {
            ZStack {
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .strokeBorder(Theme.softFill, lineWidth: 4)
                        .frame(width: 120 + CGFloat(ring) * 52, height: 120 + CGFloat(ring) * 52)
                        .scaleEffect(phase ? 1.05 : 0.95)
                        .opacity(phase ? 0.45 : 1)
                }
                Image(systemName: "figure.indoor.cycle")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 92, height: 92)
                    .background(Theme.sunset, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .rotationEffect(.degrees(phase ? 3 : -3))
                badge("sparkles", x: -96, y: -44, bob: phase ? -7 : 5)
                badge("snowflake", x: 98, y: -28, bob: phase ? 6 : -6)
                badge("bolt.fill", x: 70, y: 64, bob: phase ? -5 : 7)
            }
        }

        private func badge(_ symbol: String, x: CGFloat, y: CGFloat, bob: CGFloat) -> some View {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.card, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                .offset(x: x, y: y + bob)
        }
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
}
