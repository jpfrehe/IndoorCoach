import SwiftUI

/// Claude-key and MyWhoosh sign-in forms, shared by the onboarding and Profil so both behave the same.
/// Both are plain stacks: they sit in an onboarding card or in one row of a Profil section.

// MARK: - Field chrome

private struct ConnectionFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension View {
    func connectionField() -> some View { modifier(ConnectionFieldStyle()) }
}

private struct FieldLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }
}

private struct FormError: View {
    var message: String
    var identifier: String
    var body: some View {
        Label {
            Text(message).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.subheadline)
        .foregroundStyle(.red)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Claude

struct ClaudeKeyForm: View {
    @Environment(AppModel.self) private var model
    /// Profil offers "API-Key entfernen"; onboarding does not.
    var showsRemove = false
    var onSaved: () -> Void = {}

    private enum Phase: Equatable {
        case idle, checking
        case failed(String)
        /// Could not be checked – the user may still save the key.
        case unreachable
    }

    @State private var input = ""
    @State private var phase: Phase = .idle
    /// Closed on submit, so the result (and the onboarding's bottom bar) is visible right away.
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasClaudeKey {
                saved
            } else {
                entry
            }
        }
    }

    private var saved: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("API-Key gespeichert")
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.done)
            }
            .accessibilityIdentifier("claude.key.saved")
            if showsRemove {
                Button("API-Key entfernen", role: .destructive) { model.setClaudeAPIKey("") }
                    .frame(minHeight: 44, alignment: .leading)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
            }
        }
    }

    private var canCheck: Bool { input.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 && phase != .checking }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel("API-Key")
            SecureField("Claude-API-Key", text: $input, prompt: Text("sk-ant-…"))
                .plainTextInput()
                .credentialInput()
                .connectionField()
                .accessibilityIdentifier("claude.key.field")
                .focused($fieldFocused)
                .onChange(of: input) { if phase != .checking { phase = .idle } }
                .onSubmit { check() }
            #if os(iOS)
            PasteButton(payloadType: String.self) { strings in
                if let pasted = strings.first { input = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .buttonBorderShape(.capsule)
            .tint(Theme.accent)
            .accessibilityIdentifier("claude.key.paste")
            #endif

            switch phase {
            case let .failed(message):
                FormError(message: message, identifier: "claude.key.error")
            case .unreachable:
                FormError(message: "Konnte den Key gerade nicht prüfen. Hast du Internet? Du kannst ihn auch ungeprüft speichern.",
                          identifier: "claude.key.error")
            case .idle, .checking:
                EmptyView()
            }

            Button(action: check) {
                HStack(spacing: 8) {
                    if phase == .checking { ProgressView() }
                    Text(phase == .checking ? "Prüfe …" : "Prüfen & speichern")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.jelly)
            .disabled(!canCheck)
            .accessibilityIdentifier("claude.key.save")

            if phase == .unreachable {
                Button {
                    model.setClaudeAPIKey(input.trimmingCharacters(in: .whitespacesAndNewlines))
                    input = ""
                    onSaved()
                } label: {
                    Text("Trotzdem speichern").frame(maxWidth: .infinity)
                }
                .buttonStyle(.soft)
                .accessibilityIdentifier("claude.key.saveAnyway")
            }
        }
    }

    private func check() {
        guard canCheck else { return }
        fieldFocused = false
        phase = .checking
        let key = input
        Task {
            let result = await model.validateAndStoreClaudeKey(key)
            switch result {
            case .valid:
                input = ""
                phase = .idle
                onSaved()
            case .invalid:
                phase = .failed("Dieser Key wurde abgelehnt. Prüfe, ob du ihn komplett kopiert hast.")
            case .forbidden:
                phase = .failed(ClaudeError.permissionDenied.localizedDescription)
            case .unreachable:
                phase = .unreachable
            }
        }
    }
}

// MARK: - MyWhoosh

struct MyWhooshLoginForm: View {
    @Environment(AppModel.self) private var model
    /// True from the tap until sign-in and the first ride import are done. The parent owns it, because the form
    /// itself disappears once the account is connected.
    @Binding var busy: Bool
    var onConnected: () -> Void = {}

    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    private enum Field { case email, password }
    @FocusState private var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel("E-Mail")
            TextField("E-Mail", text: $email, prompt: Text("MyWhoosh-Konto"))
                .textContentType(.username)
                .plainTextInput()
                #if os(iOS)
                .keyboardType(.emailAddress)
                #endif
                .connectionField()
                .accessibilityIdentifier("whoosh.email")
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .password }
            FieldLabel("Passwort")
            SecureField("Passwort", text: $password, prompt: Text("wird nicht gespeichert"))
                .textContentType(.password)
                .connectionField()
                .accessibilityIdentifier("whoosh.password")
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { connect() }
            if let error {
                FormError(message: error, identifier: "whoosh.error")
            }
            Button(action: connect) {
                HStack(spacing: 8) {
                    if busy { ProgressView() }
                    Text(busy ? "Verbinde und lade Fahrten …" : "Bei MyWhoosh anmelden")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.jelly)
            .disabled(busy || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            .accessibilityIdentifier("whoosh.login")
        }
    }

    private func connect() {
        guard !busy, !email.isEmpty, !password.isEmpty else { return }
        focus = nil
        busy = true
        error = nil
        Task {
            let ok = await model.connectMyWhoosh(username: email, password: password)
            password = "" // never kept
            if ok { onConnected() } else { error = model.lastMyWhooshError ?? "Anmeldung fehlgeschlagen." }
            busy = false
        }
    }
}
