import SwiftUI

/// „Dein Warum“ (docs/22, B4) im Winter-Arc-Hub: ein eigener Satz, höchstens 140 Zeichen, jederzeit änderbar. Bleibt auf dem
/// iPhone und geht nie an Claude.
struct WhyCard: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        Card(title: "Dein Warum", systemImage: "heart") {
            Text(WhyNote.question).font(.headline)
            TextField("Dein Satz für diesen Winter", text: $draft, axis: .vertical)
                .lineLimit(2...4)
                .focused($focused)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
                .onChange(of: draft) { _, new in
                    if new.count > WhyNote.maxLength { draft = String(new.prefix(WhyNote.maxLength)) }
                }
                .accessibilityIdentifier("why.field")
            Text("\(draft.count) von \(WhyNote.maxLength) Zeichen").font(.caption).foregroundStyle(Theme.rowSecondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(WhyNote.suggestions) { suggestion in
                    Button {
                        draft = suggestion.text
                        focused = suggestion.needsCompletion
                    } label: {
                        Text(suggestion.label).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.soft)
                }
            }
            Button {
                focused = false
                model.saveWhy(draft)
                draft = model.whyNote ?? ""
            } label: {
                Text("Speichern").frame(maxWidth: .infinity)
            }
            .buttonStyle(.jelly)
            .disabled(!WhyNote.isComplete(draft) && !(draft.isEmpty && model.whyNote != nil))
            .accessibilityIdentifier("why.save")
            Text(WhyNote.privacyNote).font(.caption).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("why.card")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = model.whyNote ?? ""
        }
    }
}

/// Einmalige Frage im Highlight-Slot nach der ersten Fahrt der Saison („Magst du deinem Winter einen Satz geben?“).
struct WhyPromptCard: View {
    @AppStorage(WhyNote.promptDismissedKey) private var dismissed = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Card(title: "Dein Warum", systemImage: "heart") {
            Text(WhyNote.promptTitle).font(.headline)
            Text("Ein Satz, den die App dir zur richtigen Zeit zurückgibt. Bleibt auf deinem iPhone.")
                .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                NavigationLink { WinterArcView() } label: { Text("Satz schreiben").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.jelly)
                    .simultaneousGesture(TapGesture().onEnded { dismissed = true })
                    .accessibilityIdentifier("why.prompt.write")
                Button { dismissed = true } label: { Text("Später").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("why.prompt.later")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
