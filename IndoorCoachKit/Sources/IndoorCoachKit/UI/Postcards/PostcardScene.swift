import SwiftUI

/// Die eigene Vektor-Illustration einer Postkarte (docs/22, B2): Himmel aus `WinterSky`, Bergsilhouette aus dem Höhenprofil der
/// Etappe, Schneekappen, die mit dem Saisonfortschritt schmelzen, und eine Sonne, die von Etappe zu Etappe höher steht.
/// Alles gezeichnet, keine Fotos, keine Marken, keine Werte. Die Geometrie ist rein und testbar; gezeichnet wird im `Canvas`.
enum PostcardScene {
    /// Stützpunkte je Bergkamm.
    static let ridgePoints = 28
    /// Höchste Etappe der Reise (Stilfser Joch) als Maßstab.
    private static let highestElevation = Double(WinterJourney.stages.map(\.elevation).max() ?? 2757)

    /// Kleines Motiv, das die Karte erzählt (Kirchturm im See, 48 Kehren, Zitronenbaum …).
    enum Motif: Equatable {
        case none, village, lake, churchTowerInLake, serpentineRoad, spa, sunrays, thaw, loneRoad, lakeReflection, lemonTree
    }

    struct Geometry: Equatable {
        /// 0…1: wie weit der Schnee die Gipfel bedeckt (nimmt mit dem Fortschritt ab, am Ende 0).
        var snowCoverage: Double
        /// 0…1: Höhe der Sonne über dem Horizont (steigt mit dem Fortschritt).
        var sunHeight: Double
        /// 0…1: Höhe des höchsten Gipfels, folgt der Höhe der Etappe.
        var peakHeight: Double
        /// Hinterer und vorderer Kamm, je `ridgePoints` Werte 0…1 von links nach rechts.
        var ridgeBack: [Double]
        var ridgeFront: [Double]
    }

    /// Wo die Karte auf der Reise liegt: Etappe 1 = 0 (tiefer Winter), Etappe 10 = 1 (Frühling).
    static func seasonProgress(stage: Int) -> Double {
        let last = Double(WinterJourney.stages.count - 1)
        return min(1, max(0, Double(clampedStage(stage) - 1) / last))
    }

    static func clampedStage(_ stage: Int) -> Int { min(WinterJourney.stages.count, max(1, stage)) }

    static func geometry(stage rawStage: Int, seasonProgress rawProgress: Double) -> Geometry {
        let stage = clampedStage(rawStage)
        let p = rawProgress.isNaN ? 0 : min(1, max(0, rawProgress))
        let elevation = Double(WinterJourney.stages[stage - 1].elevation) / highestElevation
        let peak = 0.36 + 0.6 * elevation
        let snow = (1 - p) * (0.55 + 0.45 * elevation)
        let sun = 0.2 + 0.65 * p
        return Geometry(snowCoverage: min(1, max(0, snow)), sunHeight: min(1, max(0, sun)), peakHeight: min(1, max(0, peak)),
                        ridgeBack: ridge(stage: stage, layer: 0, peak: peak * 0.78),
                        ridgeFront: ridge(stage: stage, layer: 1, peak: peak))
    }

    static func motif(for stage: Int) -> Motif {
        switch clampedStage(stage) {
        case 1: .village
        case 2: .lake
        case 3: .churchTowerInLake
        case 4: .serpentineRoad
        case 5: .spa
        case 6: .sunrays
        case 7: .thaw
        case 8: .loneRoad
        case 9: .lakeReflection
        default: .lemonTree
        }
    }

    // MARK: Bergkamm (deterministisch je Etappe)

    private struct Seeded {
        var state: UInt64
        init(_ seed: Int) { state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678 }
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }

    /// Ein Hauptgipfel, ein bis zwei Nebengipfel und etwas Zacken; Höhe skaliert mit `peak`.
    private static func ridge(stage: Int, layer: Int, peak: Double) -> [Double] {
        var rng = Seeded(stage * 131 + layer * 7_919)
        let mainAt = 0.2 + 0.6 * rng.next()
        let sideAt = (mainAt + 0.35 + 0.2 * rng.next()).truncatingRemainder(dividingBy: 1)
        let sideHeight = 0.45 + 0.3 * rng.next()
        let width = 0.16 + 0.08 * rng.next()
        return (0..<ridgePoints).map { i in
            let x = Double(i) / Double(ridgePoints - 1)
            func bump(_ at: Double, _ height: Double) -> Double { height * exp(-pow((x - at) / width, 2)) }
            let base = 0.12 + max(bump(mainAt, 1), bump(sideAt, sideHeight), bump(sideAt - 0.5, sideHeight * 0.7))
            let jag = (rng.next() - 0.5) * 0.12
            return min(1, max(0, (base + jag) * peak))
        }
    }

    // MARK: Zeichnen

    private static func color(_ hex: UInt32) -> Color { Color(Palette.RGB(hex: hex)) }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        let x = Palette.RGB(hex: a), y = Palette.RGB(hex: b), t = min(1, max(0, t))
        return Color(red: x.r + (y.r - x.r) * t, green: x.g + (y.g - x.g) * t, blue: x.b + (y.b - x.b) * t)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, stage rawStage: Int, progress p: Double, geometry g: Geometry) {
        let stage = clampedStage(rawStage)
        let w = size.width, h = size.height
        let horizon = h * 0.66
        let peakPx = h * 0.56

        // Himmel
        let sky = WinterSky.stops(progress: p).map { Color($0) }
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

        // Sonne (steigt von Etappe zu Etappe)
        let sunR = w * 0.055
        let sun = CGPoint(x: w * 0.76, y: min(horizon - sunR * 0.4, horizon - g.sunHeight * h * 0.52))
        let sunColor = mix(0xFFE9A8, 0xFFF3C4, p)
        let glow = sunR * 3.4
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - glow, y: sun.y - glow, width: glow * 2, height: glow * 2)),
                 with: .radialGradient(Gradient(colors: [sunColor.opacity(0.55), sunColor.opacity(0)]), center: sun,
                                       startRadius: 0, endRadius: glow))
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - sunR, y: sun.y - sunR, width: sunR * 2, height: sunR * 2)), with: .color(sunColor))
        if stage == 6 { rays(&ctx, center: sun, radius: sunR, color: sunColor) }

        // Weiche Wolken
        let cloud = Color.white.opacity(0.22 + 0.1 * p)
        for (cx, cy, s) in [(0.18, 0.2, 1.0), (0.46, 0.13, 0.7), (0.9, 0.3, 0.8)] {
            let r = w * 0.07 * s
            ctx.fill(Path(roundedRect: CGRect(x: w * cx - r * 1.4, y: h * cy, width: r * 2.8, height: r * 0.7), cornerRadius: r * 0.35), with: .color(cloud))
            ctx.fill(Path(ellipseIn: CGRect(x: w * cx - r * 0.5, y: h * cy - r * 0.4, width: r * 1.1, height: r * 0.9)), with: .color(cloud))
        }

        // Kämme mit Schnee
        let backBase = horizon - h * 0.015, frontBase = horizon + h * 0.05
        let back = ridgePath(g.ridgeBack, base: backBase, scale: peakPx * 0.95, size: size)
        let front = ridgePath(g.ridgeFront, base: frontBase, scale: peakPx, size: size)
        ctx.fill(back, with: .color(mix(0x8D88CC, 0xD39BAE, p)))
        snow(&ctx, ridge: back, coverage: g.snowCoverage * 0.9, base: backBase, scale: peakPx * 0.95, width: w, tint: 0xEDE9FF)
        ctx.fill(front, with: .color(mix(0x4A4D9A, 0x6C9468, p)))
        snow(&ctx, ridge: front, coverage: g.snowCoverage, base: frontBase, scale: peakPx, width: w, tint: 0xFFFFFF)

        // Vordergrund: Schneefeld im Winter, Wiese im Frühling
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: h * 0.84))
        ground.addQuadCurve(to: CGPoint(x: w, y: h * 0.80), control: CGPoint(x: w * 0.5, y: h * 0.74))
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.addLine(to: CGPoint(x: 0, y: h))
        ground.closeSubpath()
        ctx.fill(ground, with: .color(mix(0xE9EEFB, 0x86B86B, p)))

        // Wenige Flocken, solange noch Winter ist
        var rng = Seeded(stage * 977)
        for _ in 0..<(WinterSky.flakeCount(progress: p) / 3) {
            let r = w * (0.003 + 0.004 * rng.next())
            ctx.fill(Path(ellipseIn: CGRect(x: w * rng.next(), y: h * 0.8 * rng.next(), width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(0.8)))
        }

        motif(&ctx, stage: stage, size: size, progress: p, geometry: g, front: front)
    }

    private static func ridgePath(_ values: [Double], base: CGFloat, scale: CGFloat, size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, v) in values.enumerated() {
            path.addLine(to: CGPoint(x: size.width * CGFloat(i) / CGFloat(max(1, values.count - 1)), y: base - CGFloat(v) * scale))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    /// Schnee oberhalb einer unregelmäßigen Schneegrenze; ohne Schnee (Frühling) wird nichts gezeichnet.
    private static func snow(_ ctx: inout GraphicsContext, ridge: Path, coverage: Double, base: CGFloat, scale: CGFloat,
                             width: CGFloat, tint: UInt32) {
        guard coverage > 0.02 else { return }
        let line = base - CGFloat(1 - coverage * 0.85) * scale
        var cap = Path()
        cap.move(to: CGPoint(x: 0, y: 0))
        cap.addLine(to: CGPoint(x: 0, y: line))
        let steps = 14
        for i in 1...steps {
            let x = width * CGFloat(i) / CGFloat(steps)
            cap.addLine(to: CGPoint(x: x, y: line + (i % 2 == 0 ? -1 : 1) * scale * 0.035))
        }
        cap.addLine(to: CGPoint(x: width, y: 0))
        cap.closeSubpath()
        var layer = ctx
        layer.clip(to: cap)
        layer.fill(ridge, with: .color(color(tint).opacity(0.96)))
    }

    // MARK: Motive

    private static func motif(_ ctx: inout GraphicsContext, stage: Int, size: CGSize, progress p: Double, geometry g: Geometry,
                              front: Path) {
        let w = size.width, h = size.height
        let ice = mix(0xB8DCEB, 0x6FC3C9, p)
        switch motif(for: stage) {
        case .village:
            house(&ctx, x: w * 0.10, base: h * 0.9, width: w * 0.10, wall: 0xF2DDC7, roof: 0x8F4F4A, snowy: true)
            house(&ctx, x: w * 0.23, base: h * 0.86, width: w * 0.08, wall: 0xEBCFB6, roof: 0x7B4640, snowy: true)
            house(&ctx, x: w * 0.34, base: h * 0.91, width: w * 0.09, wall: 0xF5E6D3, roof: 0x8F4F4A, snowy: true)
            pine(&ctx, x: w * 0.47, base: h * 0.9, height: h * 0.14, snowy: true)
        case .lake:
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.1, y: h * 0.8, width: w * 0.5, height: h * 0.1)), with: .color(ice))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.18, y: h * 0.83, width: w * 0.2, height: h * 0.02)), with: .color(.white.opacity(0.5)))
            pine(&ctx, x: w * 0.68, base: h * 0.9, height: h * 0.16, snowy: true)
            pine(&ctx, x: w * 0.76, base: h * 0.92, height: h * 0.12, snowy: true)
        case .churchTowerInLake:
            let lake = CGRect(x: w * 0.22, y: h * 0.79, width: w * 0.62, height: h * 0.13)
            ctx.fill(Path(ellipseIn: lake), with: .color(mix(0xE4F1F8, 0x8CCBD6, p)))
            ctx.fill(Path(ellipseIn: lake.insetBy(dx: w * 0.05, dy: h * 0.03)), with: .color(.white.opacity(0.35)))
            ctx.fill(Path(CGRect(x: w * 0.52, y: h * 0.69, width: w * 0.022, height: h * 0.15)), with: .color(color(0xF2E6D8)))
            var spire = Path()
            spire.move(to: CGPoint(x: w * 0.516, y: h * 0.69))
            spire.addLine(to: CGPoint(x: w * 0.531, y: h * 0.60))
            spire.addLine(to: CGPoint(x: w * 0.546, y: h * 0.69))
            spire.closeSubpath()
            ctx.fill(spire, with: .color(color(0xC8553D)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.524, y: h * 0.72, width: w * 0.014, height: h * 0.02)), with: .color(color(0x7B5A44)))
        case .serpentineRoad:
            let peakIndex = g.ridgeFront.firstIndex(of: g.ridgeFront.max() ?? 0) ?? 0
            let px = w * CGFloat(peakIndex) / CGFloat(PostcardScene.ridgePoints - 1)
            let top = h * 0.66 + h * 0.05 - CGFloat(g.ridgeFront[peakIndex]) * h * 0.56 + h * 0.07
            var road = Path()
            road.move(to: CGPoint(x: px, y: top))
            for i in 1...9 {
                let t = CGFloat(i) / 9
                road.addLine(to: CGPoint(x: px + (i % 2 == 0 ? -1 : 1) * w * 0.05 * (0.35 + 0.65 * t), y: top + (h * 0.8 - top) * t))
            }
            ctx.stroke(road, with: .color(color(0xF4E3C8)), style: StrokeStyle(lineWidth: max(1.5, w * 0.009), lineCap: .round, lineJoin: .round))
        case .spa:
            house(&ctx, x: w * 0.14, base: h * 0.9, width: w * 0.12, wall: 0xEFD9C2, roof: 0x9A5C4F, snowy: p < 0.6)
            house(&ctx, x: w * 0.30, base: h * 0.88, width: w * 0.09, wall: 0xF5E6D3, roof: 0x8F4F4A, snowy: p < 0.6)
            for (i, dx) in [0.16, 0.2, 0.24].enumerated() {
                var steam = Path()
                let x0 = w * dx, y0 = h * 0.75
                steam.move(to: CGPoint(x: x0, y: y0))
                steam.addCurve(to: CGPoint(x: x0 + w * 0.01, y: y0 - h * 0.17), control1: CGPoint(x: x0 - w * 0.03, y: y0 - h * 0.06),
                               control2: CGPoint(x: x0 + w * 0.04, y: y0 - h * 0.1))
                ctx.stroke(steam, with: .color(.white.opacity(0.7 - Double(i) * 0.1)), style: StrokeStyle(lineWidth: max(1.5, w * 0.007), lineCap: .round))
            }
        case .sunrays:
            pine(&ctx, x: w * 0.12, base: h * 0.92, height: h * 0.2, snowy: p < 0.5)
            pine(&ctx, x: w * 0.2, base: h * 0.9, height: h * 0.15, snowy: p < 0.5)
            pine(&ctx, x: w * 0.3, base: h * 0.93, height: h * 0.22, snowy: p < 0.5)
        case .thaw:
            house(&ctx, x: w * 0.12, base: h * 0.9, width: w * 0.12, wall: 0xF2DDC7, roof: 0x8F4F4A, snowy: false)
            house(&ctx, x: w * 0.30, base: h * 0.88, width: w * 0.1, wall: 0xEBCFB6, roof: 0x7B4640, snowy: false)
            for dx in [0.14, 0.2, 0.32, 0.37] {
                let x = w * dx
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: h * 0.8, width: w * 0.008, height: w * 0.014)), with: .color(color(0x6FB7E6)))
                var icicle = Path()
                icicle.move(to: CGPoint(x: x - w * 0.006, y: h * 0.74))
                icicle.addLine(to: CGPoint(x: x + w * 0.006, y: h * 0.74))
                icicle.addLine(to: CGPoint(x: x, y: h * 0.78))
                icicle.closeSubpath()
                ctx.fill(icicle, with: .color(.white.opacity(0.85)))
            }
        case .loneRoad:
            var road = Path()
            road.move(to: CGPoint(x: w * 0.42, y: h * 0.97))
            road.addCurve(to: CGPoint(x: w * 0.6, y: h * 0.55), control1: CGPoint(x: w * 0.7, y: h * 0.86), control2: CGPoint(x: w * 0.36, y: h * 0.7))
            ctx.stroke(road, with: .color(color(0xF0DDC0)), style: StrokeStyle(lineWidth: max(2, w * 0.012), lineCap: .round))
            for (i, r) in [0.016, 0.012, 0.008].enumerated() {
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.6 - w * r, y: h * 0.55 - w * 0.012 * CGFloat(i + 1) - w * r * 0.6, width: w * r * 2, height: w * r * 1.2)),
                         with: .color(color(0x8C8A93)))
            }
        case .lakeReflection:
            let lake = CGRect(x: w * 0.08, y: h * 0.79, width: w * 0.84, height: h * 0.15)
            let water = Path(ellipseIn: lake)
            ctx.fill(water, with: .color(mix(0xCFE6F2, 0x7FBFD0, p)))
            var mirrored = ctx
            mirrored.clip(to: water)
            mirrored.translateBy(x: 0, y: h * 0.86)
            mirrored.scaleBy(x: 1, y: -0.4)
            mirrored.translateBy(x: 0, y: -h * 0.66)
            mirrored.fill(front, with: .color(mix(0x4A4D9A, 0x6C9468, p).opacity(0.55)))
        case .lemonTree:
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.3, y: h * 0.8, width: w * 0.7, height: h * 0.16)), with: .color(color(0x58B7D6)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.46, y: h * 0.84, width: w * 0.26, height: h * 0.03)), with: .color(.white.opacity(0.5)))
            ctx.fill(Path(CGRect(x: w * 0.135, y: h * 0.72, width: w * 0.016, height: h * 0.2)), with: .color(color(0x7A5A3E)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.06, y: h * 0.52, width: w * 0.17, height: h * 0.26)), with: .color(color(0x4F9A55)))
            for (dx, dy) in [(0.09, 0.62), (0.15, 0.58), (0.19, 0.68), (0.12, 0.71), (0.08, 0.7)] {
                ctx.fill(Path(ellipseIn: CGRect(x: w * dx, y: h * dy, width: w * 0.022, height: w * 0.022)), with: .color(color(0xFFD43B)))
            }
            var sail = Path()
            sail.move(to: CGPoint(x: w * 0.62, y: h * 0.86))
            sail.addLine(to: CGPoint(x: w * 0.62, y: h * 0.74))
            sail.addLine(to: CGPoint(x: w * 0.7, y: h * 0.86))
            sail.closeSubpath()
            ctx.fill(sail, with: .color(.white))
        case .none:
            break
        }
    }

    private static func rays(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        for i in 0..<14 {
            let a = Double(i) / 14 * 2 * .pi
            var ray = Path()
            ray.move(to: CGPoint(x: center.x + cos(a) * radius * 1.7, y: center.y + sin(a) * radius * 1.7))
            ray.addLine(to: CGPoint(x: center.x + cos(a) * radius * 3.1, y: center.y + sin(a) * radius * 3.1))
            ctx.stroke(ray, with: .color(color.opacity(0.55)), style: StrokeStyle(lineWidth: max(1.5, radius * 0.2), lineCap: .round))
        }
    }

    private static func house(_ ctx: inout GraphicsContext, x: CGFloat, base: CGFloat, width: CGFloat, wall: UInt32, roof: UInt32, snowy: Bool) {
        let height = width * 0.7
        ctx.fill(Path(CGRect(x: x, y: base - height, width: width, height: height)), with: .color(color(wall)))
        var roofPath = Path()
        roofPath.move(to: CGPoint(x: x - width * 0.08, y: base - height))
        roofPath.addLine(to: CGPoint(x: x + width / 2, y: base - height - width * 0.4))
        roofPath.addLine(to: CGPoint(x: x + width * 1.08, y: base - height))
        roofPath.closeSubpath()
        ctx.fill(roofPath, with: .color(snowy ? .white : color(roof)))
        ctx.fill(Path(CGRect(x: x + width * 0.2, y: base - height * 0.7, width: width * 0.2, height: height * 0.3)), with: .color(color(0xFFD27A)))
        ctx.fill(Path(CGRect(x: x + width * 0.6, y: base - height * 0.7, width: width * 0.2, height: height * 0.3)), with: .color(color(0xFFD27A)))
    }

    private static func pine(_ ctx: inout GraphicsContext, x: CGFloat, base: CGFloat, height: CGFloat, snowy: Bool) {
        ctx.fill(Path(CGRect(x: x - height * 0.03, y: base - height * 0.12, width: height * 0.06, height: height * 0.12)), with: .color(color(0x6B4A36)))
        for i in 0..<3 {
            let t = CGFloat(i)
            let top = base - height * (0.95 - t * 0.0) + t * height * 0.22
            let half = height * (0.2 + t * 0.07)
            var tier = Path()
            tier.move(to: CGPoint(x: x, y: top))
            tier.addLine(to: CGPoint(x: x - half, y: top + height * 0.34))
            tier.addLine(to: CGPoint(x: x + half, y: top + height * 0.34))
            tier.closeSubpath()
            ctx.fill(tier, with: .color(color(0x3F7F52)))
            if snowy {
                var cap = Path()
                cap.move(to: CGPoint(x: x, y: top))
                cap.addLine(to: CGPoint(x: x - half * 0.55, y: top + height * 0.19))
                cap.addLine(to: CGPoint(x: x + half * 0.55, y: top + height * 0.19))
                cap.closeSubpath()
                ctx.fill(cap, with: .color(.white.opacity(0.92)))
            }
        }
    }
}

/// Die Illustration als View: dekorativ, VoiceOver überspringt sie (die Karte spricht für sich).
struct PostcardIllustration: View {
    var stage: Int
    /// Fortschritt für Himmel, Schnee und Sonne; Standard ist die Lage der Etappe auf der Reise.
    var seasonProgress: Double?

    var body: some View {
        let progress = seasonProgress ?? PostcardScene.seasonProgress(stage: stage)
        let geometry = PostcardScene.geometry(stage: stage, seasonProgress: progress)
        Canvas { context, size in
            PostcardScene.draw(&context, size: size, stage: stage, progress: progress, geometry: geometry)
        }
        .accessibilityHidden(true)
    }
}
