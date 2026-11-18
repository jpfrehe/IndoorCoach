import SwiftUI

/// Profil → "Hilfe & Feedback": feedback form (O3), app tour and the redacted diagnostics export (B05).
struct HelpFeedbackSection: View {
    @Environment(AppModel.self) private var model
    @State private var diagnosticsURL: URL?
    @State private var isExporting = false
    @State private var showTour = false

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
            Button {
                showTour = true
            } label: {
                Label("App-Einführung ansehen", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("help.tour")
        } header: { Text("Hilfe & Feedback") } footer: {
            Text("Feedback wird als öffentliches Issue auf GitHub angelegt (kostenloses Konto nötig, bitte keine persönlichen Daten). Die Diagnose enthält die App-Protokolle der letzten 24 Stunden – ohne Schlüssel, Tokens, Fahrtnamen, Ziel oder Hinweise. Du entscheidest im Teilen-Menü, wohin sie geht.")
        }
        .sheet(isPresented: $showTour) {
            FeatureTourView(context: .help) { showTour = false }
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
