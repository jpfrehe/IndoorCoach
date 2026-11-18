import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Profil → Hilfe → "Feedback & Wünsche" (O3): builds a prefilled GitHub issue-form link. No token, no backend.
struct FeedbackView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    // The draft lives in UserDefaults so it survives the trip to Safari (and a killed app).
    @AppStorage("feedback.draft.kind") private var kindRaw = FeedbackKind.bug.rawValue
    @AppStorage("feedback.draft.title") private var title = ""
    @AppStorage("feedback.draft.body") private var body_ = ""
    @AppStorage("feedback.draft.appInfo") private var includeAppInfo = true
    @AppStorage("feedback.draft.awaitingGitHub") private var awaitingGitHub = false

    @State private var copied = false
    @FocusState private var focus: Field?
    private enum Field { case title, body }

    private let appInfo = FeedbackDraft.AppInfo.current

    private var kind: FeedbackKind {
        get { FeedbackKind(rawValue: kindRaw) ?? .bug }
        nonmutating set { kindRaw = newValue.rawValue }
    }
    private var draft: FeedbackDraft { FeedbackDraft(kind: kind, title: title, body: body_) }
    private var preview: String { draft.plainText(appInfo: appInfo, includeAppInfo: includeAppInfo) }

    var body: some View {
        Form {
            if awaitingGitHub { confirmationSection }
            kindSection
            textSection
            appInfoSection
            if draft.isValid { previewSection }
            actionSection
            linkSection
        }
        .navigationTitle("Feedback & Wünsche")
        .navigationBarTitleDisplayModeInline()
    }

    // MARK: Sections

    private var confirmationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("GitHub ist geöffnet", systemImage: "arrow.up.forward.app")
                    .font(.headline)
                Text("Letzter Schritt: Auf GitHub unten auf ‚Create‘ tippen. Erst dann ist dein Feedback abgeschickt.")
                    .font(.subheadline)
                Button("Erledigt") { clearDraft() }
                    .buttonStyle(.jelly)
                    .accessibilityIdentifier("feedback.done")
                Text("Du hast nichts abgeschickt? Dein Text bleibt unten erhalten.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var kindSection: some View {
        Section {
            kindPicker
                .frame(minHeight: 44)
                .accessibilityIdentifier("feedback.kind")
        } header: { Text("Worum geht’s?") }
    }

    @ViewBuilder private var kindPicker: some View {
        let picker = Picker("Art", selection: Binding(get: { kind }, set: { kind = $0 })) {
            ForEach(FeedbackKind.allCases) { k in
                Label(k.title, systemImage: k.symbol).tag(k)
            }
        }
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var textSection: some View {
        Section {
            TextField("Titel", text: $title)
                .focused($focus, equals: .title)
                .submitLabel(.next)
                .onSubmit { focus = .body }
                .frame(minHeight: 44)
                .accessibilityIdentifier("feedback.title")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $body_)
                    .focused($focus, equals: .body)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier("feedback.body")
                    .accessibilityLabel("Beschreibung")
                    .accessibilityHint(kind.prompt)
                if body_.isEmpty {
                    Text(kind.prompt)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        } header: { Text("Dein Text") } footer: {
            Text("Mindestens 5 Zeichen im Titel und 10 in der Beschreibung. Wird öffentlich auf GitHub veröffentlicht. Du brauchst ein kostenloses GitHub-Konto. Bitte keine persönlichen Daten.")
        }
    }

    private var appInfoSection: some View {
        Section {
            Toggle("App-Version und Gerät anhängen", isOn: $includeAppInfo)
                .frame(minHeight: 44)
                .accessibilityIdentifier("feedback.appInfo")
            if includeAppInfo {
                Text(appInfo.text)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("feedback.appInfo.text")
            }
        }
    }

    private var previewSection: some View {
        Section {
            Text(preview)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("feedback.preview")
        } header: { Text("Vorschau") } footer: {
            Text("So erscheint es auf GitHub. E-Mail-Adressen und Schlüssel werden automatisch geschwärzt.")
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                focus = nil
                awaitingGitHub = true
                openURL(draft.issueURL(appInfo: appInfo, includeAppInfo: includeAppInfo))
            } label: {
                Label("Weiter zu GitHub", systemImage: "arrow.up.forward.square")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.jelly)
            .disabled(!draft.isValid)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("feedback.submit")

            Button {
                copy(preview)
            } label: {
                Label("Text kopieren", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.soft)
            .disabled(!draft.isValid)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("feedback.copy")

            if copied {
                Label("Kopiert. Du kannst den Text überall einfügen.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("feedback.copied")
            }

            if let mail = AppConfig.feedbackMailURL(subject: "IndoorCoach \(kind.title): \(Redactor.scrub(title))", body: preview) {
                Link(destination: mail) {
                    Label("Per E-Mail senden", systemImage: "envelope")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(!draft.isValid)
                .accessibilityIdentifier("feedback.mail")
            }
        } footer: {
            Text("Ohne GitHub-Konto: Text kopieren und anders schicken.")
        }
    }

    private var linkSection: some View {
        Section {
            Link(destination: FeedbackDraft.existingWishesURL) {
                Label("Bestehende Wünsche ansehen", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("feedback.wishes")
            .accessibilityHint("Öffnet GitHub im Browser")
        }
    }

    // MARK: Actions

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            copied = false
        }
    }

    private func clearDraft() {
        title = ""
        body_ = ""
        awaitingGitHub = false
        copied = false
    }
}

private extension View {
    @ViewBuilder func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
