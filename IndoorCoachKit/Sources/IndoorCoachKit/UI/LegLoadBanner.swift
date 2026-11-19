import SwiftUI

/// Banner „Schwere Beine – tauschen?“ in der Detailansicht einer geplanten Schlüsseleinheit (W3-C, B49).
/// Nur ein Vorschlag (O16): nichts ändert sich ohne Tipp.
struct LegLoadBanner: View {
    var workout: StoredWorkout
    @Environment(AppModel.self) private var model
    /// Der Hinweis liegt in UserDefaults (nicht beobachtet): ein Zähler löst das Neuzeichnen nach „Behalten“ aus.
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        if let hint = model.legLoadHint(for: workout) {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(hint.message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(Theme.rowSecondary)
                }
                .accessibilityIdentifier("legload.message")
                HStack(spacing: 8) {
                    if let base = hint.base {
                        Button { Task { await model.swapForLegLoad(workout, with: base); refresh += 1 } } label: {
                            Text("Tauschen").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.jellySmall)
                        .accessibilityIdentifier("legload.swap")
                    }
                    Button { Task { await model.lightenForLegLoad(workout); refresh += 1 } } label: {
                        Text("Leichter machen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("legload.lighten")
                    Button { model.keepLegLoad(workout); refresh += 1 } label: {
                        Text("Behalten").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("legload.keep")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.softFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }
}
