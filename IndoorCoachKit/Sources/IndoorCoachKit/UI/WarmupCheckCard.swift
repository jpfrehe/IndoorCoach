import SwiftUI

/// "Aufwärm-Check": pulse at the same easy power in every warm-up – a falling pulse at equal watts is progress.
/// Used in the ride detail (`ride` set: this ride's value plus the trend) and in "Leistung" (trend only).
struct WarmupCheckCard: View {
    var ride: RideSummary?
    var rides: [RideSummary]?
    @Environment(AppModel.self) private var model
    @State private var confirmNewBase = false

    init(ride: RideSummary? = nil, rides: [RideSummary]? = nil) {
        self.ride = ride
        self.rides = rides
    }

    var body: some View {
        let measured = model.warmupTrend(rides: rides)
        // Angenommene Werte (ERG, nur Puls) bleiben ein eigener Trend: sie fließen nie in den gemessenen ein.
        let assumed = model.warmupTrend(rides: rides, source: .assumedERG)
        let trend = measured.count == 0 && assumed.count > 0 ? assumed : measured
        let check = ride.flatMap { model.warmupCheck(for: $0) }
        if check != nil || trend.count > 0 {
            Card(title: "Aufwärm-Check", systemImage: "heart.text.square") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Self.headline(trend))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("warmup.headline")
                    if trend.direction == .notEnough {
                        Text("Ein Trend braucht mindestens \(WarmupCheck.minChecksForTrend) gültige Messungen bei \(trend.refWatts) W.")
                            .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                    }
                    if let check { rideLine(check) }
                    if measured.count > 0, assumed.count > 0 {
                        Text("Getrennt davon, mit angenommener Leistung (ERG): \(Self.headline(assumed))")
                            .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("warmup.assumed")
                    }
                    Text(Self.sourceLabel(trend, check: check))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .accessibilityIdentifier("warmup.source")
                    Text("Sechs Minuten locker bei immer gleicher Leistung am Anfang der Einheit. Sinkt der Puls bei gleicher Leistung, "
                         + "spricht das für eine bessere Grundlage. Allein sagt der Wert nichts über Erholung oder Ermüdung: "
                         + "Schlaf, Hitze, Kaffee und Stress verschieben ihn auch.")
                        .font(.footnote).foregroundStyle(Theme.rowSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Neue Basis ab heute") { confirmNewBase = true }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("warmup.newBase")
                        .accessibilityHint("Setzt die Referenzleistung aus der aktuellen FTP neu. Frühere Messungen zählen dann nicht mehr.")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("warmup.card")
            .confirmationDialog("Neue Basis ab heute?", isPresented: $confirmNewBase, titleVisibility: .visible) {
                Button("Neue Basis setzen") { model.startNewWarmupBase() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die Referenzleistung wird \(WarmupCheck.defaultWatts(ftp: model.profile.ftp)) W (55 % der aktuellen FTP). Frühere Messungen zählen nicht mehr zum Trend.")
            }
        }
    }

    @ViewBuilder
    private func rideLine(_ check: WarmupCheck) -> some View {
        if check.valid, let hr = check.hrMean {
            Label("Diese Fahrt: \(Int(hr.rounded())) bpm bei \(check.refWatts) W", systemImage: "checkmark.circle")
                .font(.subheadline)
                .accessibilityIdentifier("warmup.ride")
        } else {
            Label("Diese Fahrt zählt nicht: \(check.reason ?? "nicht auswertbar")", systemImage: "minus.circle")
                .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("warmup.ride")
        }
    }

    static func headline(_ trend: WarmupCheck.Trend) -> String {
        guard let hr = trend.medianHR else { return "Noch keine gültige Messung" }
        let base = "Puls bei \(trend.refWatts) W: \(Int(hr.rounded()))"
        let measurements = trend.count == 1 ? "1 Messung" : "\(trend.count) Messungen"
        switch trend.direction {
        case .notEnough: return "\(base) · \(measurements)"
        case .falling: return "\(base) · sinkend (\(measurements))"
        case .stable: return "\(base) · stabil (\(measurements))"
        case .rising: return "\(base) · höher als zuvor (\(measurements))"
        }
    }

    static func sourceLabel(_ trend: WarmupCheck.Trend, check: WarmupCheck?) -> String {
        let measured = check.map { $0.source == .measured } ?? trend.allMeasured
        return measured ? "gemessen" : "angenommen (ERG)"
    }
}
