import SwiftUI

/// Profil → "Hilfe & Feedback" (B05): redacted diagnostics export and a feedback mail.
struct HelpFeedbackSection: View {
    @Environment(AppModel.self) private var model
    @State private var diagnosticsURL: URL?
    @State private var isExporting = false
    @State private var showFeedbackInfo = false

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
            if let mail = feedbackURL {
                Link(destination: mail) {
                    Label("Feedback senden", systemImage: "envelope")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("feedback.send")
            } else {
                Button {
                    showFeedbackInfo = true
                } label: {
                    Label("Feedback senden", systemImage: "envelope")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("feedback.send")
                .alert("Feedback-Adresse folgt", isPresented: $showFeedbackInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Die Adresse für Feedback wird vor dem Pilot eingetragen. Bis dahin: Diagnose exportieren und direkt an den Entwickler schicken.")
                }
            }
        } header: { Text("Hilfe & Feedback") } footer: {
            Text("Die Diagnose enthält die App-Protokolle der letzten 24 Stunden – ohne Schlüssel, Tokens, Fahrtnamen, Ziel oder Hinweise. Du entscheidest im Teilen-Menü, wohin sie geht.")
        }
    }

    private var feedbackURL: URL? {
        AppConfig.feedbackMailURL(
            subject: "IndoorCoach Feedback \(AppConfig.versionString)",
            body: "\n\n—\nApp \(AppConfig.versionString) · \(AppConfig.osVersionString) · \(AppConfig.deviceModel)")
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
