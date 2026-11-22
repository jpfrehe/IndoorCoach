import SwiftUI

/// G4 "Winter-Reise": the Winter Arc as a stylised mountain-stage route (no map). Purely presentational.
struct WinterJourneyCard: View {
    var level: Int
    var levelProgress: Double
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let position = WinterJourney.position(level: level, levelProgress: levelProgress)
        let card = Card(title: "Winter-Reise · \(WinterJourney.title)", systemImage: "mountain.2") {
            JourneyRoute(position: position)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 96 : 84)
                .accessibilityHidden(true)
            HStack {
                Text(WinterJourney.stages.first?.place ?? "").lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(WinterJourney.stages.last?.place ?? "").lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.caption).foregroundStyle(Theme.rowSecondary)
            .accessibilityHidden(true)
            Text("Etappe \(position.stage.number) von \(position.count): \(position.stage.place)").font(.headline)
            if let next = position.next {
                Text("\(position.percent) % geschafft · als Nächstes \(next.place)")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            } else {
                Text("Geschafft: Du bist am Gardasee.").font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position.accessibilityLabel)
        .accessibilityIdentifier("journey.card")
        // ANCHOR-B2-JOURNEY: Link „Postkarten“ zum Album – Agent B
        VStack(alignment: .leading, spacing: 8) {
            card
            NavigationLink { PostcardAlbumScreen() } label: {
                Label("Postkarten ansehen", systemImage: "envelope").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .accessibilityIdentifier("journey.postcards")
        }
    }
}

/// Elevation profile through the ten stage points; the rider sits on the line at the current position.
private struct JourneyRoute: View {
    var position: WinterJourney.Position

    private static let inset: CGFloat = 12

    private func points(in size: CGSize) -> [CGPoint] {
        let elevations = WinterJourney.stages.map(\.elevation)
        let lo = Double(elevations.min() ?? 0), hi = Double(elevations.max() ?? 1)
        let w = size.width - 2 * Self.inset, h = size.height - 2 * Self.inset
        return elevations.enumerated().map { i, e in
            CGPoint(x: Self.inset + w * CGFloat(i) / CGFloat(max(1, elevations.count - 1)),
                    y: Self.inset + h * (1 - CGFloat((Double(e) - lo) / max(1, hi - lo))))
        }
    }

    private func rider(_ pts: [CGPoint]) -> CGPoint {
        let i = min(pts.count - 2, position.stage.number - 1)
        guard i >= 0, position.stage.number < pts.count else { return pts[pts.count - 1] }
        let a = pts[i], b = pts[i + 1], t = CGFloat(position.progress)
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            let me = rider(pts)
            ZStack {
                Path { p in p.addLines(pts) }
                    .stroke(Theme.rowSecondary.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [1, 6]))
                // Travelled part: along the legs up to the rider.
                Path { p in
                    p.addLines(Array(pts.prefix(position.stage.number)) + [me])
                }
                .stroke(Theme.fitnessLine, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                ForEach(Array(pts.enumerated()), id: \.offset) { i, pt in
                    let reached = i < position.stage.number
                    Circle()
                        .fill(reached ? Theme.fitness : Theme.card)
                        .overlay(Circle().stroke(reached ? Theme.fitnessLine : Theme.rowSecondary, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .position(pt)
                }
                Circle().fill(Theme.accent).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 3))
                    .position(me)
            }
        }
    }
}
