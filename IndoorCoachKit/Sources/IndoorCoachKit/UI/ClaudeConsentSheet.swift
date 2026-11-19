import SwiftUI

/// Einwilligung: Erholungskontext an Claude (Anthropic). Klar, was geht, wozu, was nicht, mit echter Vorschau.
struct ClaudeConsentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Nach der Entscheidung (Erlauben oder Nicht senden); die Planung läuft danach in beiden Fällen weiter.
    var onDecision: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ClaudeConsentExplainer()
                    ClaudeConsentPreview()
                }
                .padding()
            }
            .background(Theme.canvas)
            .navigationTitle("Erholung an Claude?")
            .inlineNavigationTitle()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        model.grantClaudeConsent()
                        dismiss(); onDecision()
                    } label: { Text("Erlauben").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("consent.allow")
                    Button {
                        model.declineClaudeConsent()
                        dismiss(); onDecision()
                    } label: { Text("Nicht senden").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("consent.decline")
                }
                .padding()
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()
    }
}

/// Was geht an Claude, wozu, was nicht.
struct ClaudeConsentExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Damit dein Plan zu deiner Erholung passt, kann IndoorCoach eine kurze, relative Zusammenfassung der letzten 14 Tage mit an Claude senden. Claude wird von Anthropic betrieben.")
            block("Das geht an Claude", [
                "Schlaf und Ruhepuls als Abweichung von deiner eigenen Basis, gerundet",
                "HRV als Trend (unter, im oder über deiner Basis)",
                "Zusammenfassung deiner Check-ins, zum Beispiel „2× Beine schwer“",
                "Trend des Aufwärm-Checks und ob der Trend-Wächter aktiv ist"
            ])
            block("Das geht nicht an Claude", [
                "keine Rohwerte, keine Zeitreihen, keine Gerätenamen",
                "keine Notizen, keine Diagnosen, keine Namen oder Orte"
            ])
            block("Wozu", [
                "Bei schlechterer Erholung plant Claude vorsichtiger: weniger Intensität oder Umfang, keine gestrichenen Einheiten"
            ])
            Text("Die Übertragung läuft direkt von deinem Gerät mit deinem eigenen API-Key. Du kannst jederzeit unter Profil → Datenschutz widerrufen. Ohne Einwilligung plant Claude wie bisher ohne diese Angaben.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func block(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            ForEach(items, id: \.self) { item in
                Label { Text(item) } icon: { Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 5) }
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}

/// „Das geht an Claude“: der echte Abschnitt aus den lokalen Daten.
struct ClaudeConsentPreview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Vorschau: Das geht an Claude").font(.headline)
            Text(model.recoveryPreviewText())
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .textSelection(.enabled)
                .accessibilityIdentifier("consent.preview")
        }
    }
}

/// Profil → Datenschutz: Schalter, Vorschau, Widerruf.
struct ClaudePrivacySection: View {
    @Environment(AppModel.self) private var model
    @State private var consent: ClaudeConsent?
    @State private var showPreview = false

    var body: some View {
        Section {
            Toggle("Erholung an Claude senden", isOn: Binding(
                get: { consent != nil },
                set: { on in
                    if on { model.grantClaudeConsent() } else { model.revokeClaudeConsent() }
                    consent = model.claudeConsent
                }))
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy.recoveryToggle")
            if let consent {
                Text("Erlaubt am \(consent.grantedAt.formatted(.dateTime.day().month(.twoDigits).year().locale(Locale(identifier: "de_DE"))))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Vorschau: Das geht an Claude") { showPreview = true }
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy.preview")
        } header: { Text("Datenschutz") } footer: {
            Text("Nur eine relative Zusammenfassung der letzten 14 Tage, nie Rohwerte oder Gerätenamen. Widerruf wirkt sofort.")
        }
        .onAppear { consent = model.claudeConsent }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ClaudeConsentExplainer()
                        ClaudeConsentPreview()
                    }.padding()
                }
                .background(Theme.canvas)
                .navigationTitle("Vorschau")
                .inlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showPreview = false } } }
            }
        }
    }
}
