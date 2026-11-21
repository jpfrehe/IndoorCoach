import SwiftUI

extension View {
    /// DEBUG only: `-uiChartGallery YES` shows the chart gallery instead of the app (no bootstrap, no network).
    @ViewBuilder func chartGalleryOverlay() -> some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "uiChartGallery") { ChartGalleryView() } else { self }
        #else
        self
        #endif
    }
}

#if DEBUG
/// Typical workouts for the gallery: the cases the profile geometry has to get right.
enum ChartGallerySamples {
    struct Sample: Identifiable {
        var id: String
        var definition: WorkoutDefinition
        var skipped = false
    }

    static let ftp = 250

    private static func make(_ title: String, _ type: WorkoutType, _ segments: [Segment]) -> WorkoutDefinition {
        WorkoutDefinition(title: title, type: type, summary: "Beispiel für die Diagramm-Galerie.", segments: segments)
    }

    static let sweetSpot = make("Sweet Spot 3×12", .sweetSpot, [
        .warmup(10, from: 0.5, to: 0.75), .intervals(3, on: 720, at: 0.92, off: 240, at: 0.5), .cooldown(8, from: 0.65, to: 0.4),
    ])

    static let all: [Sample] = [
        Sample(id: "grundlage", definition: make("Grundlage 90", .endurance, [
            .warmup(10, from: 0.45, to: 0.65), .steady(70, at: 0.65), .cooldown(10, from: 0.65, to: 0.4),
        ])),
        Sample(id: "sweetspot", definition: sweetSpot),
        Sample(id: "vo2max", definition: make("VO₂max 5×4", .vo2max, [
            .warmup(15, from: 0.5, to: 0.75), .intervals(5, on: 240, at: 1.15, off: 240, at: 0.5), .cooldown(10, from: 0.6, to: 0.4),
        ])),
        Sample(id: "dreissig", definition: make("30/30 · 2×10", .vo2max, [
            .warmup(10, from: 0.5, to: 0.75), .intervals(10, on: 30, at: 1.3, off: 30, at: 0.5), .steady(5, at: 0.5),
            .intervals(10, on: 30, at: 1.3, off: 30, at: 0.5), .cooldown(8, from: 0.6, to: 0.4),
        ])),
        Sample(id: "tabata", definition: make("Tabata mit Sprint (Z7 über 160 %)", .anaerobic, [
            .warmup(15, from: 0.5, to: 0.8), .intervals(8, on: 20, at: 1.7, off: 10, at: 0.4), .steady(5, at: 0.5),
            .intervals(8, on: 20, at: 1.7, off: 10, at: 0.4), .cooldown(10, from: 0.6, to: 0.4),
        ])),
        Sample(id: "rampe", definition: make("Rampen-Aufwärmen über drei Zonen", .test, [
            .warmup(20, from: 0.4, to: 1.0), .steady(5, at: 0.5), .ramp(10, from: 0.6, to: 1.15), .cooldown(10, from: 0.65, to: 0.4),
        ])),
        Sample(id: "lang", definition: make("Lange Einheit 3 h", .mixed, [
            .warmup(15, from: 0.45, to: 0.7), .steady(50, at: 0.65), .intervals(3, on: 1200, at: 0.9, off: 300, at: 0.55),
            .steady(45, at: 0.65), .cooldown(10, from: 0.6, to: 0.4),
        ])),
        Sample(id: "ausgelassen", definition: sweetSpot, skipped: true),
    ]
}

/// Chart gallery for visual review (concept 21 §6). Every profile variant for typical workouts, light or dark as the
/// system says; zone marks stand on card surfaces only.
struct ChartGalleryView: View {
    private let ftp = ChartGallerySamples.ftp

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Diagramm-Galerie").font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                ForEach(ChartGallerySamples.all) { sample in sampleCard(sample) }
                zoneBars
            }
            .padding()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .accessibilityIdentifier("chart.gallery")
    }

    private func sampleCard(_ sample: ChartGallerySamples.Sample) -> some View {
        let d = sample.definition
        return Card(title: sample.skipped ? "\(d.title) – ausgelassen" : d.title, systemImage: "chart.bar") {
            caption("Zeile 72 × 34")
            WorkoutProfileView(definition: d, ftp: ftp, variant: .row, skipped: sample.skipped).equatable().frame(width: 72)
            caption("Karte 64")
            WorkoutProfileView(definition: d, ftp: ftp, variant: .card, height: 64, skipped: sample.skipped).equatable()
            caption("Vorschau 110 mit FTP-Linie")
            WorkoutProfileView(definition: d, ftp: ftp, variant: .preview, skipped: sample.skipped).equatable()
            caption("Barrierefreie Zeile 28")
            WorkoutProfileView(definition: d, ftp: ftp, variant: .accessibilityRow, skipped: sample.skipped).equatable()
            if !sample.skipped {
                caption("Detail 210")
                WorkoutProfileChart(definition: d, ftp: ftp)
            }
        }
    }

    private var zoneBars: some View {
        Card(title: "Segmentbalken", systemImage: "square.stack.3d.up") {
            ForEach([ChartGallerySamples.sweetSpot, ChartGallerySamples.all[2].definition], id: \.title) { d in
                ZoneDistributionBar(definition: d)
            }
            caption("hoch, mit Anteil")
            SegmentedBar(items: PowerZone.allCases.map {
                SegmentedBar.Item(id: $0.rawValue, value: Double(8 - $0.rawValue), color: ChartPalette.zone($0),
                                  label: "\(Int((Double(8 - $0.rawValue) / 28 * 100).rounded())) %", labelColor: ChartPalette.label(on: $0))
            }, variant: .tall)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(Theme.rowSecondary)
    }
}
#endif
