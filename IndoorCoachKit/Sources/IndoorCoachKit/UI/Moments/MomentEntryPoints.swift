import SwiftUI

// Die Stellen, an denen ein Gipfelmoment später wieder auftaucht: Fahrt-Detail, Trophäenschrank, Profil → Winter Arc.

/// Fahrt-Detail (`ANCHOR-B1-RIDE`): „Gipfelmoment dieser Fahrt ansehen“, wenn zur Fahrt ein Moment gehört. Zeigt die
/// Feier erneut, ohne etwas als gesehen zu vermerken.
struct MomentRideRow: View {
    var ride: RideSummary
    @Environment(AppModel.self) private var model
    @State private var batch: MomentBatch?
    @State private var shown: PresentedMoment?

    var body: some View {
        Group {
            if let batch {
                Button { shown = PresentedMoment(presentation: model.momentPresentation(for: batch)) } label: {
                    Label("Gipfelmoment dieser Fahrt ansehen", systemImage: "mountain.2").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.soft)
                .accessibilityIdentifier("ride.moment")
                .accessibilityHint("Zeigt die Feier zu dieser Fahrt noch einmal")
            }
        }
        .task(id: ride.id) { batch = model.momentBatch(forRide: ride) }
        .momentCover(item: $shown) { MomentSheet(presentation: $0.presentation) }
    }
}

/// Trophäenschrank (`ANCHOR-B1-TROPHY`): kleiner Punkt „neu“ für Trophäen der letzten 7 Tage.
struct NewTrophyDot: View {
    var trophy: Trophy

    static let days = 7

    /// Erreicht innerhalb der letzten 7 Tage (nie in der Zukunft).
    static func isNew(_ trophy: Trophy, now: Date = AppModel.today) -> Bool {
        guard let on = trophy.earnedOn, on <= now else { return false }
        return now.timeIntervalSince(on) <= Double(days) * 86_400
    }

    var body: some View {
        if Self.isNew(trophy) {
            Circle()
                .fill(Theme.sunset)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Theme.ink.opacity(0.35), lineWidth: 0.5))
                .accessibilityHidden(true) // „neu“ steht im Label der Zeile
        }
    }
}

/// Profil → Winter Arc (`ANCHOR-B1-SETTING`): der Schalter „Feiern nach der Fahrt“.
struct MomentSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle("Feiern nach der Fahrt", isOn: $model.momentsEnabled)
                .accessibilityIdentifier("moments.toggle")
        } footer: {
            Text("Nach einer Fahrt mit etwas Besonderem – neues Level, Bestleistung, geschaffte Woche – erscheint einmal eine ruhige Feier mit einem Satz deines Coaches. Sie bleibt, bis du sie schließt. Trophäen und Level zählen auch bei ausgeschalteter Feier.")
        }
    }
}
