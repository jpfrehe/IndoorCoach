import SwiftUI

/// Eine Antwortkachel (docs/20 §6.3).
struct ChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var subtitle: String?
    let symbol: String
    /// Vollständiger Bedienungshilfen-Identifier, z. B. `onboarding.ride.myWhoosh`.
    let identifier: String
    /// „Noch keine App“, „Nichts davon“: hebt die anderen Antworten auf (und umgekehrt).
    var isExclusive = false

    var id: Value { value }
}

/// Auswahlregeln der Kacheln, ohne Oberfläche (testbar).
enum ChoiceSelection {
    /// Mehrfachauswahl mit exklusiver Kachel: Wer sie antippt, hebt alle anderen auf, und jede andere hebt sie auf.
    static func toggled<Value: Hashable>(_ selection: Set<Value>, _ value: Value, exclusive: Set<Value>) -> Set<Value> {
        var result = selection
        if result.contains(value) {
            result.remove(value)
        } else if exclusive.contains(value) {
            result = [value]
        } else {
            result.subtract(exclusive)
            result.insert(value)
        }
        return result
    }
}

/// Kachelraster für die Fragen der Einführung. Zwei Spalten, ab den Bedienungshilfe-Schriftgrößen eine.
/// Gewählt wird nie nur über die Farbe: Häkchen-Symbol, `.isSelected` und ein Hinweis für VoiceOver.
struct ChoiceChipGrid<Value: Hashable>: View {
    enum Mode {
        /// „Mehrere Antworten möglich.“
        case multiple
        /// „Eine Antwort.“ (Radio-Verhalten)
        case single
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    var label: String
    var options: [ChoiceOption<Value>]
    var selection: Set<Value>
    var mode: Mode = .multiple
    var onTap: (Value) -> Void

    private var columns: Int { typeSize.isAccessibilitySize ? 1 : 2 }

    var body: some View {
        let rows = stride(from: 0, to: options.count, by: columns).map { Array(options[$0..<min($0 + columns, options.count)]) }
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { option in chip(option) }
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.gridCellUnsizedAxes(.vertical) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func hint(for option: ChoiceOption<Value>) -> String {
        switch mode {
        case .single: "Eine Antwort"
        case .multiple: option.isExclusive ? "Hebt die anderen Antworten auf" : "Mehrfachauswahl"
        }
    }

    private func chip(_ option: ChoiceOption<Value>) -> some View {
        let on = selection.contains(option.value)
        return Button { onTap(option.value) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: option.symbol)
                        .font(.title3)
                        .foregroundStyle(on ? Theme.ink : Theme.accent)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(on ? Theme.ink : Theme.rowSecondary.opacity(0.6))
                        .accessibilityHidden(true)
                }
                Text(option.title)
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = option.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(on ? Theme.ink.opacity(0.85) : Theme.rowSecondary)
                }
            }
            .foregroundStyle(on ? Theme.ink : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                if on {
                    shape.fill(Theme.sunset)
                } else {
                    shape.fill(Theme.card).overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(hint(for: option))
        .accessibilityIdentifier(option.identifier)
    }
}
