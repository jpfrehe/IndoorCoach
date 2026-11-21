import AuthenticationServices
import SwiftUI

/// Gemeinsame Texte zu intervals.icu (Dienstseite und Einführung nutzen dieselbe Quelle).
enum IntervalsTexts {
    /// Hinweis zur Weiterleitung an Zwift, Garmin, Wahoo oder Rouvy.
    static let forward = "Damit Einheiten in Zwift, Garmin, Wahoo oder Rouvy erscheinen, schalte in intervals.icu unter Einstellungen → Connections die Übertragung geplanter Workouts ein."
    static let settingsURL = URL(string: "https://intervals.icu/settings")!
}

/// „Mit intervals.icu verbinden“: öffnet die Web-Anmeldung (OAuth mit PKCE) und meldet das Ergebnis zurück.
/// Abbruch durch die Nutzerin ist kein Fehler (`connectIntervals` liefert dann `false` ohne Fehlertext).
/// Ein Fehler steht in `model.lastIntervalsError`, die aufrufende Ansicht zeigt ihn.
struct IntervalsOAuthButton: View {
    enum Style {
        /// Zeile in einer Liste (Dienstseite).
        case row
        /// Große Hauptaktion (Einführung).
        case prominent
        /// Zweitaktion in derselben Größe (Einführung, Stufe „Auch möglich“).
        case soft
    }

    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuth
    @Binding var busy: Bool
    var title = "Mit intervals.icu verbinden"
    var style: Style = .row
    var identifier = "intervals.connect"
    /// Sperrt den Knopf von außen (in der Einführung läuft gerade eine andere Verbindung).
    var isLocked = false
    var onStart: () -> Void = {}
    /// `true`, wenn verbunden.
    var onFinished: (Bool) -> Void = { _ in }

    var body: some View {
        switch style {
        case .row:
            Button(action: start) {
                HStack {
                    Label(title, systemImage: "link").font(.headline)
                    if busy { Spacer(); ProgressView() }
                }
            }
            .disabled(busy)
            .accessibilityIdentifier(identifier)
        case .prominent, .soft:
            Button(action: start) {
                HStack(spacing: 8) {
                    if busy { ProgressView() }
                    Text(busy ? "Verbinde …" : title)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(style == .prominent ? AnyButtonStyle(.jelly) : AnyButtonStyle(.soft))
            .disabled(busy || isLocked)
            .accessibilityIdentifier(identifier)
        }
    }

    private func start() {
        guard !busy else { return }
        onStart()
        busy = true
        let session = webAuth
        Task {
            let connected = await model.connectIntervals { url in
                try await session.authenticate(using: url, callbackURLScheme: IntervalsConfig.callbackScheme,
                                               preferredBrowserSession: .shared)
            }
            busy = false
            onFinished(connected)
        }
    }
}
