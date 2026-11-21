import SwiftUI

/// Blätter über der Einführung: Mac-Brücke und Brustgurt (docs/20 §6.5). Beide führen in die bestehenden Ansichten
/// (`MacBridgeView`, `DevicesView`); „Fertig“ bringt die Nutzerin auf dieselbe Karte zurück.

private struct SheetDoneButton: ToolbarContent {
    var action: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Fertig", action: action)
                .accessibilityIdentifier("onboarding.sheet.done")
        }
    }
}

// MARK: - Mac-Brücke

struct OnboardingBridgeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showPairing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Fahrten im Detail vom Mac").font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("MyWhoosh speichert jede Fahrt sekundengenau auf deinem Mac. Ein kleiner Gratis-Helfer, die IndoorCoach Brücke, schickt sie im WLAN ans iPhone. Nichts verlässt dein Zuhause.")
                        .fixedSize(horizontal: false, vertical: true)
                    Card(title: "Was du brauchst", systemImage: "macbook") {
                        Text("Die Mac-App „IndoorCoach Brücke“. Schick dir den Link auf den Mac und lade sie dort herunter.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = model.bridgeDownloadURL {
                        ShareLink(item: url) {
                            Label("Link an den Mac schicken", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.jelly)
                        .accessibilityIdentifier("onboarding.bridge.share")
                    }
                    Button { showPairing = true } label: {
                        Text("Mac-App läuft schon – jetzt koppeln").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("onboarding.bridge.pair")
                    OnboardingHint("Später geht das auch unter Profil → Dienste & Geräte → Sekundendaten vom Mac.")
                }
                .padding()
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas)
            .navigationTitle("Mac-Brücke")
            .inlineNavigationTitle()
            .toolbar { SheetDoneButton { dismiss() } }
            .navigationDestination(isPresented: $showPairing) {
                MacBridgeView()
                    .toolbar { SheetDoneButton { dismiss() } }
            }
        }
        // Nach erfolgreicher Kopplung schließt das Blatt von selbst, die Karte zeigt dann „Gekoppelt mit …“.
        .task(id: model.isBridgePaired) {
            guard model.isBridgePaired else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            if !Task.isCancelled { dismiss() }
        }
    }
}

// MARK: - Brustgurt

struct OnboardingStrapSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DevicesView()
                .inlineNavigationTitle()
                .toolbar { SheetDoneButton { dismiss() } }
        }
    }
}
