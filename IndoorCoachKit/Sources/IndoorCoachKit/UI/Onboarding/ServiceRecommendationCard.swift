import SwiftUI

/// Zustand einer Dienstkarte in der Einführung (docs/20 §6.5).
enum ServiceCardState: Equatable {
    /// Noch nichts getan.
    case open
    /// Eine Verbindung läuft (alle anderen Aktionen sind gesperrt).
    case busy
    /// Verbunden, mit Detail („Verbunden · 23 Fahrten geladen“).
    case connected(String)
    /// Das letzte Verbinden ist fehlgeschlagen; der Text steht in `error`, bei MyWhoosh im Formular selbst.
    case failed
    /// „Später“ getippt.
    case later

    var isConnected: Bool { if case .connected = self { true } else { false } }
}

/// Karte eines Dienstes in „Für dich passt“: Name, Zustand, ein Satz Nutzen, Dienst-Inhalt und Aktionen.
/// Der Dienst-Inhalt (`content`) liefert Erklärtexte, Formulare und Folge-Hinweise; die Karte kümmert sich um Zustände,
/// Auf- und Zuklappen, „Später“ und die Bedienungshilfen.
struct ServiceRecommendationCard<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var statusFocused: Bool

    var recommendation: ServiceRecommendation
    var name: String
    var symbol: String
    var state: ServiceCardState
    /// Fehlertext im Intro (`….error`); nil, wenn das Formular ihn selbst zeigt.
    var error: String?
    /// Kompakt mit „Ansehen“ (Stufe „Auch möglich“ und „Alle Dienste“) oder aufgeklappt.
    var isExpanded: Bool
    /// Titel des Hauptknopfs; nil: kein Hauptknopf (Strava, oder das Formular führt selbst).
    var connectTitle: String?
    var connectIcon: String?
    /// Sperrt Knöpfe, solange irgendwo eine Verbindung läuft.
    var isLocked: Bool
    /// Karte darf „Später“ anbieten (nicht bei Strava, dort entscheidet der Schalter).
    var offersLater = true
    /// Zeile unter „Später“ (Mac-Brücke: wo die Erinnerung zu finden ist).
    var laterNote: String?
    var onConnect: () -> Void = {}
    var onLater: () -> Void = {}
    var onResume: () -> Void = {}
    var onToggleExpanded: () -> Void = {}
    /// Wie die Statuszeile für Tests heißt, wenn sie zusätzlich eine eigene Kennung braucht (MyWhoosh).
    var extraStatusID: String?
    @ViewBuilder var content: Content

    private var id: String { "onboarding.service.\(recommendation.id.rawValue)" }
    private var isProminent: Bool { recommendation.tier == .recommended }
    private var showsBody: Bool { isExpanded || state.isConnected || state == .busy || state == .failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusLine
            if state == .later {
                if let laterNote { OnboardingHint(laterNote) }
                resumeButton
            } else if showsBody {
                content
                if let error {
                    Label {
                        Text(error).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("\(id).error")
                }
                actions
            } else {
                Button(action: onToggleExpanded) {
                    Text("Ansehen").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("\(name) ansehen")
                .accessibilityIdentifier("\(id).expand")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
        .onChange(of: state) { old, new in
            guard old != new else { return }
            if case .connected = new {
                AccessibilityNotification.Announcement("\(name) verbunden").post()
                statusFocused = true
            } else if new == .failed {
                statusFocused = true
            }
        }
    }

    // MARK: Kopf

    private var tierPrefix: String {
        switch recommendation.tier {
        case .recommended: "Empfohlen: "
        case .optional: "Auch möglich: "
        case .advanced: "Für Fortgeschrittene: "
        case .more: ""
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(name).font(.headline).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).foregroundStyle(Theme.accent)
            }
            Text(recommendation.benefit)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let note = recommendation.note {
                OnboardingHint(note, symbol: "info.circle")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(tierPrefix)\(name). \(recommendation.benefit)\(recommendation.note.map { " \($0)" } ?? "")")
    }

    // MARK: Status

    @ViewBuilder
    private var statusLine: some View {
        let line = Group {
            switch state {
            case .open:
                Label("Nicht verbunden", systemImage: "circle.dashed").foregroundStyle(Theme.rowSecondary)
            case .busy:
                HStack(spacing: 8) { ProgressView(); Text("Verbinde …") }.foregroundStyle(Theme.rowSecondary)
            case .connected(let detail):
                Label {
                    Text(detail).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.done)
                }
                .font(.subheadline.weight(.semibold))
            case .failed:
                Label {
                    Text("Verbinden hat nicht geklappt").foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            case .later:
                Label("Später", systemImage: "clock").foregroundStyle(Theme.rowSecondary)
            }
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        if let extraStatusID {
            // Das Kästchen bekommt die Kennung des Dienstes, die Zeile darin die zusätzliche (MyWhoosh: test29).
            line
                .accessibilityIdentifier(extraStatusID)
                .accessibilityFocused($statusFocused)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("\(id).status")
        } else {
            line
                .accessibilityElement(children: .combine)
                .accessibilityFocused($statusFocused)
                .accessibilityIdentifier("\(id).status")
        }
    }

    // MARK: Aktionen

    @ViewBuilder
    private var actions: some View {
        if state.isConnected {
            EmptyView()
        } else {
            VStack(spacing: 4) {
                if let connectTitle {
                    Button(action: onConnect) {
                        HStack(spacing: 8) {
                            if state == .busy { ProgressView() }
                            if let connectIcon, state != .busy { Image(systemName: connectIcon) }
                            Text(state == .busy ? "Verbinde …" : connectTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(isProminent ? AnyButtonStyle(.jelly) : AnyButtonStyle(.soft))
                    .disabled(isLocked || state == .busy)
                    .accessibilityIdentifier("\(id).connect")
                }
                if offersLater {
                    Button(action: onLater) {
                        Text("Später").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .foregroundStyle(Theme.accent)
                    .disabled(isLocked || state == .busy)
                    .accessibilityHint("Du kannst \(name) jederzeit unter Profil, Dienste und Geräte einrichten.")
                    .accessibilityIdentifier("\(id).later")
                }
            }
        }
    }

    private var resumeButton: some View {
        Button(action: onResume) {
            Text("Doch jetzt").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .foregroundStyle(Theme.accent)
        .disabled(isLocked)
        .accessibilityIdentifier("\(id).resume")
    }
}
