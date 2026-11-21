import SwiftUI

/// Z – "Zeit in Zonen": minutes per power or heart-rate zone of one ride, from its stored 1 Hz data.
struct RideZonesCard: View {
    var ride: RideSummary
    @Environment(AppModel.self) private var model
    @State private var mode = Mode.power

    enum Mode: String, CaseIterable, Identifiable {
        case power = "Leistung", heart = "Puls"
        var id: String { rawValue }
    }

    private struct Row: Identifiable {
        var id: Int
        var title: String
        var seconds: Int
        var color: Color
    }

    var body: some View {
        if let zones = model.zoneTimes(for: ride) {
            let hasHeart = zones.heart != nil && zones.heartTotal > 0
            // ANCHOR-REC: pulse-only rides (iPhone recording) show pulse zones only, not an empty power view.
            let pulseOnly = hasHeart && !zones.hasPower
            let active = ((mode == .heart || pulseOnly) && hasHeart) ? Mode.heart : Mode.power
            let rows = rows(zones, mode: active)
            let total = max(1, rows.map(\.seconds).reduce(0, +))
            let longest = max(1, rows.map(\.seconds).max() ?? 1)
            Card(title: "Zeit in Zonen", systemImage: "chart.bar.xaxis") {
                if hasHeart, !pulseOnly {
                    Picker("Zonen", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("ride.zones.mode")
                }
                if rows.allSatisfy({ $0.seconds == 0 }) {
                    Text(active == .power ? "Keine Leistung in den Sekundendaten." : "Kein Puls in den Sekundendaten.")
                        .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.title).font(.subheadline)
                                    Spacer(minLength: 8)
                                    Text(Self.minutes(row.seconds)).font(.subheadline.weight(row.seconds > 0 ? .semibold : .regular)).monospacedDigit()
                                        .foregroundStyle(row.seconds > 0 ? Color.primary : Theme.rowSecondary)
                                }
                                // Track (primary 6 %) with the bar on top; an empty zone shows only the track.
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(ChartPalette.band)
                                        if row.seconds > 0 {
                                            Capsule().fill(row.color)
                                                .frame(width: max(8, proxy.size.width * Double(row.seconds) / Double(longest)))
                                        }
                                    }
                                }
                                .frame(height: 8)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(row.title): \(Self.spokenMinutes(row.seconds))")
                        }
                    }
                    .accessibilityIdentifier(active == .power ? "ride.zones.power" : "ride.zones.heart")
                    Text(footnote(active, total: total))
                        .font(.footnote).foregroundStyle(Theme.rowSecondary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ride.zones")
        } else {
            Label("Für Zonen braucht es Sekundendaten (Mac-Brücke oder FIT-Import)", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("ride.zones.hint")
        }
    }

    private func rows(_ zones: ZoneTime.Result, mode: Mode) -> [Row] {
        switch mode {
        case .power:
            PowerZone.allCases.map {
                Row(id: $0.rawValue, title: "Zone \($0.rawValue) \($0.name)", seconds: zones.power[$0.rawValue - 1], color: ChartPalette.zone($0))
            }
        case .heart:
            (0..<5).map {
                Row(id: $0 + 1, title: "Zone \($0 + 1) \(HeartRateZones.names[$0])", seconds: zones.heart?[$0] ?? 0,
                    color: ChartPalette.zone(PowerZone.allCases[$0 == 4 ? 5 : $0]))
            }
        }
    }

    private func footnote(_ mode: Mode, total: Int) -> String {
        switch mode {
        case .power:
            "Zonen nach FTP \(model.profile.ftp) W (Coggan). Pausen ohne Leistung zählen nicht, gemessen: \(Self.minutes(total))."
        case .heart:
            model.profile.thresholdHeartRate != nil
                ? "Pulszonen nach Schwellenpuls \(model.profile.thresholdHeartRate ?? 0) bpm (81/89/94/100 %). Sekunden ohne Puls zählen nicht."
                : "Pulszonen nach Max-HF \(model.profile.heartRateProfile.max) bpm (60/70/80/90 %). Sekunden ohne Puls zählen nicht."
        }
    }

    static func minutes(_ seconds: Int) -> String { "\((Double(seconds) / 60).rounded().formatted(.number.precision(.fractionLength(0)))) min" }

    static func spokenMinutes(_ seconds: Int) -> String {
        let m = Int((Double(seconds) / 60).rounded())
        return m == 1 ? "1 Minute" : "\(m) Minuten"
    }
}
