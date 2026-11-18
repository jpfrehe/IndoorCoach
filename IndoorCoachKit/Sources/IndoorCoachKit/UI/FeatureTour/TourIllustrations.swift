import SwiftUI

/// Drives an illustration with a time value `t` in 0…1. The animation restarts whenever `active` turns true.
/// With "Bewegung reduzieren" the final state (t = 1) is shown without any motion.
struct TourStage<Content: View>: View {
    var active: Bool
    var duration: Double = 2.8
    @ViewBuilder var content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || start == nil || finished)) { context in
            content(progress(at: context.date))
        }
        .onChange(of: active, initial: true) { _, isActive in
            finished = false
            start = isActive ? .now : nil
        }
        .task(id: start) {
            guard start != nil, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(duration + 0.1))
            finished = true
        }
    }

    private func progress(at date: Date) -> Double {
        if reduceMotion { return 1 }
        guard let start else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }
}

/// Rounded card behind every illustration; one VoiceOver element with the page's label.
struct IllustrationFrame<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.softFill, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("tour.illustration")
    }
}

@MainActor extension TourPage {
    /// The animated illustration for this page.
    @ViewBuilder func illustration(active: Bool) -> some View {
        IllustrationFrame(label: illustrationLabel) {
            switch self {
            case .plan: TourStage(active: active) { WeekPlanArt(t: $0) }
            case .myWhoosh: TourStage(active: active) { MyWhooshArt(t: $0) }
            case .winterArc: TourStage(active: active) { WinterArcArt(t: $0) }
            case .consistency: TourStage(active: active) { ConsistencyArt(t: $0) }
            case .progress: TourStage(active: active) { PowerCurveArt(t: $0) }
            }
        }
    }
}

// MARK: 1 · Week plan

private struct WeekPlanArt: View {
    var t: Double
    private let days = ["M", "D", "M", "D", "F", "S", "S"]
    private let heights: [Double] = [0.55, 0, 0.8, 0.4, 0, 1, 0.65]
    private let zones: [PowerZone] = [.z2, .z2, .z4, .z3, .z2, .z2, .z3]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").symbolEffect(.pulse, options: .repeating)
                Text("Deine Woche").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.softFill)
                            if heights[i] > 0 {
                                let order = Double(heights[..<i].filter { $0 > 0 }.count)
                                let grow = TourMath.easeOut(TourMath.segment(t, from: 0.08 + 0.1 * order, to: 0.34 + 0.1 * order))
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.fill(zones[i]))
                                    .frame(height: 120 * heights[i] * grow)
                            }
                        }
                        .frame(height: 120)
                        Text(days[i]).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.rowSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: 2 · Workout flies into the MyWhoosh calendar

private struct MyWhooshArt: View {
    var t: Double

    var body: some View {
        GeometryReader { g in
            let calW = min(g.size.width * 0.5, 190.0), calH = 150.0
            let cx = g.size.width * 0.70, cy = g.size.height * 0.5
            let gridW = calW - 20, gridH = calH - 26 - 20
            let cellW = (gridW - 18) / 4, cellH = (gridH - 12) / 3
            let target = CGPoint(x: cx - calW / 2 + 10 + 2 * (cellW + 6) + cellW / 2,
                                 y: cy - calH / 2 + 36 + (cellH + 6) + cellH / 2)
            let start = CGPoint(x: g.size.width * 0.22, y: g.size.height * 0.5)
            let move = TourMath.easeInOut(TourMath.segment(t, from: 0.2, to: 0.7))
            let tick = TourMath.pop(TourMath.segment(t, from: 0.72, to: 1))

            ZStack {
                // Calendar
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.canvas)
                    .frame(width: calW, height: calH)
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14)
                            .fill(Theme.accent).frame(height: 26)
                            .overlay(Text("MyWhoosh").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.canvas))
                    }
                    .overlay {
                        VStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { _ in
                                HStack(spacing: 6) {
                                    ForEach(0..<4, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 4).fill(Theme.softFill)
                                    }
                                }
                            }
                        }
                        .padding(EdgeInsets(top: 36, leading: 10, bottom: 10, trailing: 10))
                    }
                    .position(x: cx, y: cy)

                // Workout card
                workoutCard
                    .scaleEffect(TourMath.lerp(1, Double(cellW / 96), move), anchor: .center)
                    .position(x: TourMath.lerp(start.x, target.x, move), y: TourMath.lerp(start.y, target.y, move))

                // Check mark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.ink, Theme.done)
                    .scaleEffect(tick)
                    .opacity(tick > 0 ? 1 : 0)
                    .position(x: cx + calW / 2 - 6, y: cy - calH / 2 + 4)
            }
        }
    }

    private var workoutCard: some View {
        VStack(spacing: 4) {
            Image(systemName: "bolt.fill").font(.system(size: 16, weight: .bold))
            HStack(alignment: .bottom, spacing: 3) {
                ForEach([10.0, 18, 14, 22], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2).fill(Theme.ink.opacity(0.75)).frame(width: 8, height: h)
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(width: 96, height: 64)
        .background(Theme.sunset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: 3 · Winter Arc level ring

private struct WinterArcArt: View {
    var t: Double

    var body: some View {
        let fill = TourMath.easeInOut(TourMath.segment(t, from: 0, to: 0.8))
        let swap = TourMath.easeInOut(TourMath.segment(t, from: 0.35, to: 0.65))
        let level = 1 + Int((3 * TourMath.easeOut(TourMath.segment(t, from: 0.1, to: 0.8))).rounded(.down))
        ZStack {
            Circle().stroke(Theme.softFill, lineWidth: 16)
            Circle()
                .trim(from: 0, to: 0.78 * fill)
                .stroke(Theme.sunsetAngular, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                ZStack {
                    Image(systemName: "snowflake")
                        .foregroundStyle(Theme.fitnessLine)
                        .opacity(1 - swap)
                        .rotationEffect(.degrees(90 * swap))
                        .scaleEffect(1 - 0.4 * swap)
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(Theme.sunset)
                        .opacity(swap)
                        .rotationEffect(.degrees(-60 + 60 * swap + 40 * t))
                        .scaleEffect(0.6 + 0.4 * swap)
                }
                .font(.system(size: 40))
                .frame(height: 46)
                Text("Level \(level)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: 168, height: 168)
    }
}

// MARK: 4 · Consistency dots and joker shield

private struct ConsistencyArt: View {
    var t: Double
    private let missed = 4

    var body: some View {
        GeometryReader { g in
            let size = min(30.0, (g.size.width - 32 - 7 * 6) / 8)
            let shield = TourMath.pop(TourMath.segment(t, from: 0.72, to: 0.95))
            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { i in
                    let p = TourMath.pop(TourMath.segment(t, from: 0.04 + 0.075 * Double(i), to: 0.18 + 0.075 * Double(i)))
                    ZStack {
                        Circle().stroke(Theme.softFill, lineWidth: 2.5)
                        if i == missed {
                            Circle().stroke(Theme.rowSecondary, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                                .opacity(TourMath.segment(t, from: 0.3, to: 0.4) * (1 - shield))
                            Circle().fill(Theme.done.opacity(0.45)).scaleEffect(shield)
                        } else {
                            Circle().fill(Theme.done).scaleEffect(p)
                        }
                    }
                    .frame(width: size, height: size)
                    .overlay {
                        if i == missed {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: size * 1.05, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .offset(y: -34 * (1 - min(1, shield)))
                                .scaleEffect(0.2 + 0.8 * shield)
                                .opacity(shield > 0 ? 1 : 0)
                        }
                    }
                }
            }
            .position(x: g.size.width / 2, y: g.size.height / 2 + 6)
            Text("Joker")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .opacity(shield)
                .position(x: g.size.width / 2, y: g.size.height / 2 + 6 + size / 2 + 22)
        }
    }
}

// MARK: 5 · Power curve with PR badge

private struct PowerCurveArt: View {
    var t: Double

    /// Normalised curve: x in 0…1 (duration), y in 0…1 (power, 1 = high).
    private func y(_ x: Double) -> Double { 0.22 + 0.7 * exp(-3.4 * x) }

    var body: some View {
        GeometryReader { g in
            let rect = CGRect(x: 24, y: 24, width: g.size.width - 48, height: g.size.height - 56)
            let draw = TourMath.easeInOut(TourMath.segment(t, from: 0, to: 0.65))
            let badge = TourMath.pop(TourMath.segment(t, from: 0.72, to: 1))
            let point = { (x: Double) in CGPoint(x: rect.minX + x * rect.width, y: rect.maxY - y(x) * rect.height) }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                    p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                }
                .stroke(Theme.rowSecondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                Path { p in
                    p.move(to: point(0))
                    for i in 1...60 { p.addLine(to: point(Double(i) / 60)) }
                }
                .trim(from: 0, to: draw)
                .stroke(Theme.sunset, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

                Circle().fill(Theme.accent).frame(width: 10, height: 10)
                    .position(point(draw))
                    .opacity(draw > 0 && badge == 0 ? 1 : 0)

                HStack(spacing: 4) {
                    Image(systemName: "star.fill").symbolEffect(.bounce, value: badge > 0.5)
                    Text("PR").fontWeight(.heavy)
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.sunset, in: Capsule())
                .scaleEffect(badge)
                .opacity(badge > 0 ? 1 : 0)
                .position(x: point(0.3).x + 34, y: point(0.3).y - 26)
            }
        }
    }
}
