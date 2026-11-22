import SwiftUI

/// Die Partikel der Feier („Schnee zu Funken“, docs/22 §B1): 40 Flocken fallen etwa 1,2 s und werden dabei zu goldenen
/// Funken, danach steht das Bild still – keine Schleife. Die Mathematik ist rein (deterministisch, ohne Zufall), damit
/// sie ohne Oberfläche getestet werden kann; gezeichnet wird sie im `Canvas`.
enum CelebrationParticles {
    static let count = 40
    static let duration = 1.2

    struct Particle: Equatable {
        /// Waagerechter Start und Ruheplatz (0…1 der Breite).
        var x: Double
        /// Höhe, auf der der Funke zur Ruhe kommt (0…1 der Höhe).
        var rest: Double
        /// Verzögerung in Sekunden (0…0,4), damit nicht alle gleichzeitig fallen.
        var delay: Double
        /// Radius in Punkt am Anfang.
        var size: Double
        var sway: Double
        var phase: Double
    }

    struct Frame: Equatable {
        var x: Double
        var y: Double
        var radius: Double
        /// 0 = weiße Flocke, 1 = goldener Funke.
        var progress: Double
        var opacity: Double
    }

    /// Immer dieselben Teilchen (fester Startwert), damit Bilder und Tests stabil bleiben.
    static func make(count: Int = count) -> [Particle] {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((seed >> 33) & 0xFF_FFFF) / Double(0x100_0000)
        }
        return (0..<count).map { _ in
            Particle(x: 0.04 + next() * 0.92, rest: 0.12 + next() * 0.8, delay: next() * 0.4, size: 3 + next() * 5,
                     sway: 0.01 + next() * 0.03, phase: next() * 2 * .pi)
        }
    }

    /// Zustand eines Teilchens nach `t` Sekunden; ab `duration` ändert sich nichts mehr.
    static func frame(of p: Particle, at t: Double) -> Frame {
        let raw = min(1, max(0, (t - p.delay) / (duration - p.delay)))
        let eased = 1 - pow(1 - raw, 3)
        return Frame(x: p.x + sin(p.phase + raw * 2 * .pi) * p.sway * (1 - raw), y: -0.05 + (p.rest + 0.05) * eased,
                     radius: p.size * (1 - 0.45 * eased), progress: eased, opacity: raw == 0 ? 0 : 0.9 - 0.25 * eased)
    }

    /// Weiß → Mango (`Palette.mangoPop`).
    static func color(progress: Double) -> Color {
        let m = Palette.mangoPop
        return Color(red: 1 + (m.r - 1) * progress, green: 1 + (m.g - 1) * progress, blue: 1 + (m.b - 1) * progress)
    }

    static func draw(_ context: GraphicsContext, size: CGSize, at t: Double, particles: [Particle]) {
        for particle in particles {
            let f = frame(of: particle, at: t)
            guard f.opacity > 0 else { continue }
            let center = CGPoint(x: f.x * size.width, y: f.y * size.height)
            let color = color(progress: f.progress).opacity(f.opacity)
            context.fill(Path(ellipseIn: CGRect(x: center.x - f.radius, y: center.y - f.radius, width: f.radius * 2, height: f.radius * 2)),
                         with: .color(color))
            if f.progress > 0.6 { // Funke: kleines Kreuz
                let arm = f.radius * 2.6, thin = max(1, f.radius * 0.35)
                context.fill(Path(CGRect(x: center.x - arm, y: center.y - thin / 2, width: arm * 2, height: thin)), with: .color(color))
                context.fill(Path(CGRect(x: center.x - thin / 2, y: center.y - arm, width: thin, height: arm * 2)), with: .color(color))
            }
        }
    }
}

/// Hintergrund der Feier: der Himmel zum Stand der Saison (`WinterSky`), darüber `Theme.sunset` mit 85 % Deckkraft, darauf
/// die Partikel. Mit `animated == false` (Bewegung reduzieren, Stromsparmodus) steht gleich das fertige Bild.
struct CelebrationBackdrop: View {
    var skyProgress: Double
    var animated: Bool

    @State private var start = Date()
    @State private var finished = false
    private let particles = CelebrationParticles.make()

    var body: some View {
        ZStack {
            LinearGradient(colors: WinterSky.stops(progress: skyProgress).map { Color($0) }, startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Theme.sunset).opacity(0.85)
            if animated && !finished {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        CelebrationParticles.draw(context, size: size, at: timeline.date.timeIntervalSince(start), particles: particles)
                    }
                }
            } else {
                Canvas { context, size in
                    CelebrationParticles.draw(context, size: size, at: CelebrationParticles.duration, particles: particles)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard animated else { return }
            start = Date()
            try? await Task.sleep(for: .seconds(CelebrationParticles.duration + 0.2))
            finished = true
        }
    }
}
