import SwiftUI

/// Profil → "Hilfe & Feedback": feedback form (O3), app tour and the redacted diagnostics export (B05).
struct HelpFeedbackSection: View {
    @Environment(AppModel.self) private var model
    @State private var diagnosticsURL: URL?
    @State private var isExporting = false
    @State private var showTour = false
    @State private var shadowMode = false

    var body: some View {
        Section {
            if let url = diagnosticsURL {
                ShareLink(item: url, preview: SharePreview("IndoorCoach-Diagnose")) {
                    Label("Diagnose teilen", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("diagnostics.share")
                .accessibilityHint("Öffnet das Teilen-Menü mit der Diagnose-Textdatei")
            } else {
                Button {
                    Task { await export() }
                } label: {
                    HStack {
                        Label("Diagnose exportieren", systemImage: "doc.text.magnifyingglass")
                        if isExporting { Spacer(); ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(isExporting)
                .accessibilityIdentifier("diagnostics.export")
            }
            NavigationLink {
                FeedbackView()
            } label: {
                Label("Feedback & Wünsche", systemImage: "bubble.left.and.text.bubble.right")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("feedback.open")
            .accessibilityHint("Öffnet ein Formular für Fehler, Wünsche und Lob")
            Toggle("Trend-Wächter Schattenmodus", isOn: $shadowMode)
                .frame(minHeight: 44)
                .accessibilityIdentifier("help.trendGuardShadow")
                .accessibilityHint("Zählt Treffer nur im Hintergrund, ohne Karte auf Heute")
                .onAppear { shadowMode = model.trendGuardShadowMode }
                .onChange(of: shadowMode) { _, new in model.trendGuardShadowMode = new }
            Button {
                showTour = true
            } label: {
                Label("App-Einführung ansehen", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("help.tour")
            // Presented from the row itself: a presentation modifier on the Section is not reliable inside a Form.
            .helpTourCover(isPresented: $showTour)
        } header: { Text("Hilfe & Feedback") } footer: {
            Text("Feedback wird als öffentliches Issue auf GitHub angelegt (kostenloses Konto nötig, bitte keine persönlichen Daten). Die Diagnose enthält die App-Protokolle der letzten 24 Stunden – ohne Schlüssel, Tokens, Fahrtnamen, Ziel oder Hinweise. Du entscheidest im Teilen-Menü, wohin sie geht.")
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            diagnosticsURL = try await model.diagnosticsFile()
        } catch {
            model.show("Diagnose konnte nicht erstellt werden: \(error.localizedDescription)", error: true)
        }
    }
}

private extension View {
    func helpTourCover(isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            FeatureTourView(context: .help) { isPresented.wrappedValue = false }
        }
        #else
        sheet(isPresented: isPresented) {
            FeatureTourView(context: .help) { isPresented.wrappedValue = false }
        }
        #endif
    }
}
