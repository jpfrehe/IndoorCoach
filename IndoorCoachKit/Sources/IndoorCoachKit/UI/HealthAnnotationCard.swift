import SwiftUI

/// Karte für „Heute“: ein Kraft-, Kletter- oder Misch-Workout aus Apple Health wartet auf Härte und Beine (W3-B, B47).
/// Erscheint nur mit aktiviertem Health und offenem Kandidat, immer nur der neueste; „Ignorieren“ blendet ihn dauerhaft aus.
struct HealthAnnotationCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.healthEnabled, let candidate = model.healthCandidates.first {
            HealthAnnotationContent(candidate: candidate)
                .id(candidate.uuid)   // neuer Kandidat = frische Eingaben
        }
    }
}

private struct HealthAnnotationContent: View {
    let candidate: HealthLedgerEntry
    @Environment(AppModel.self) private var model
    @State private var hardness: Int?
    @State private var legs: LegInvolvement?

    private var defaultLegs: LegInvolvement { SportClassification.defaultLegShare(for: candidate.activityTypeName) ?? .none }

    var body: some View {
        Card(title: "Aus Apple Health erkannt", systemImage: "heart.text.square") {
            Text("\(candidate.title) von \(candidate.sourceName) (\(candidate.durationMinutes) min) erkannt – wie hart? Beine?")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("health.annotation.text")
            ExertionPicker(value: $hardness, idPrefix: "health.annotation.exertion")
            VStack(alignment: .leading, spacing: 6) {
                Text("Beine").font(.subheadline).foregroundStyle(Theme.rowSecondary)
                LegInvolvementPicker(value: Binding(get: { legs ?? defaultLegs }, set: { legs = $0 }),
                                     idPrefix: "health.annotation.legs")
            }
            HStack(spacing: 10) {
                Button {
                    model.annotateHealthCandidate(candidate.uuid, hardness: hardness, legs: legs ?? defaultLegs)
                } label: { Text("Speichern").frame(maxWidth: .infinity) }
                    .buttonStyle(.jelly)
                    .accessibilityIdentifier("health.annotation.save")
                Button { model.dismissHealthCandidate(candidate.uuid) } label: { Text("Ignorieren").frame(maxWidth: .infinity) }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("health.annotation.dismiss")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("health.annotation.card")
    }
}
