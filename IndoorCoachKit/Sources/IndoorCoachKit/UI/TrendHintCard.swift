import SwiftUI

/// Ruhige Karte für „Heute“ (docs/17 §6.1 P2/P3, §9.7; B55): erscheint nur, wenn der Trend-Wächter anschlägt und die
/// nächste geplante Einheit hart ist. Neutrale Sprache ohne Diagnose, keine Warnfarbe, kein Push; der Fahrer entscheidet.
/// Die Karte stößt auch den Abgleich der Erholungswerte an (nur mit aktiviertem Health).
struct TrendHintCard: View {
    var rides: [RideSummary]
    @Environment(AppModel.self) private var model
    @State private var refreshed = 0
    @State private var dismissed = false

    var body: some View {
        Group {
            if !CheckInCard.suppressedInUITests, !dismissed, let hint = model.trendHint() {
                card(hint)
            }
        }
        .task {
            await model.refreshWellness()
            refreshed += 1
        }
        .id(refreshed)
    }

    private func card(_ hint: TrendHint) -> some View {
        let original = hint.workout.originalDefinition ?? hint.workout.definition
        return Card(title: TrendGuard.cardTitle, systemImage: "waveform.path.ecg") {
            Text(TrendGuard.cardText)
                .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("trendhint.text")
            ForEach(hint.offers, id: \.raw) { action in
                Button {
                    Task { await model.applyCheckInOffer(action, to: hint.workout, rides: rides) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(action)).font(.body.weight(.semibold))
                        Text(CheckInSheet.detail(action, original: original)).font(.caption).foregroundStyle(Theme.rowSecondary)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(Theme.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("trendhint.offer.\(action.raw.replacingOccurrences(of: ":", with: "."))")
            }
            HStack(spacing: 10) {
                NavigationLink { WellnessTrendsView() } label: { Text("Verlauf ansehen").frame(maxWidth: .infinity) }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("trendhint.trends")
                Button {
                    model.dismissTrendHint()
                    dismissed = true
                } label: { Text("Passt schon").frame(maxWidth: .infinity) }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("trendhint.dismiss")
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear { model.recordTrendHintShown() } // Pilot-Zähler „Karte angezeigt“ (einmal je Tag)
    }

    /// Kurze Titel der Angebote: Tauschen, Leichter, Joker.
    static func title(_ action: CheckIn.Action) -> String {
        switch action {
        case .swapToBase: "Tauschen: locker statt hart"
        case .shorten(let m, _): "Leichter: \(m) min"
        case .easier(let p): "Leichter: −\(p)\u{00A0}% Intensität"
        case .joker: "Joker einsetzen"
        }
    }
}
