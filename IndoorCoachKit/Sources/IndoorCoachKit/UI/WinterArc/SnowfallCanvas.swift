import SwiftUI

/// Schneefall im Kopf des Winter-Arc-Hubs (docs/22, B3): höchstens 40 Flocken, Dichte = 1 − Fortschritt (bei Level 10 keine).
/// Läuft mit 30 fps nur, solange `animated` gilt (Kopf sichtbar, weder „Bewegung reduzieren“ noch Stromsparmodus);
/// sonst stehen die Flocken still. Dekorativ.
enum SnowField {
    struct Flake: Equatable {
        var x: Double, y: Double, size: Double, speed: Double, sway: Double, phase: Double, opacity: Double
    }

    private static func unit(_ i: Int, _ salt: Double) -> Double {
        let v = sin(Double(i) * 12.9898 + salt * 78.233) * 43_758.5453
        return v - v.rounded(.down)
    }

    static func flake(_ i: Int) -> Flake {
        Flake(x: unit(i, 1), y: unit(i, 2), size: 1.5 + 2.5 * unit(i, 3), speed: 0.02 + 0.04 * unit(i, 4),
              sway: 4 + 8 * unit(i, 5), phase: 6.28 * unit(i, 6), opacity: 0.6 + 0.35 * unit(i, 7))
    }

    /// Position in Punkten zur Zeit `t` (Sekunden); bei t = 0 steht jede Flocke an ihrem Startplatz.
    static func position(_ f: Flake, time t: Double, size: CGSize) -> CGPoint {
        let y = (f.y + t * f.speed).truncatingRemainder(dividingBy: 1)
        return CGPoint(x: f.x * size.width + sin(t * 0.8 + f.phase) * f.sway * (t == 0 ? 0 : 1), y: y * size.height)
    }
}

struct SnowfallCanvas: View {
    var progress: Double
    var animated: Bool

    var body: some View {
        let count = WinterSky.flakeCount(progress: progress)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { timeline in
            let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                for i in 0..<count {
                    let f = SnowField.flake(i)
                    let p = SnowField.position(f, time: t, size: size)
                    context.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: f.size, height: f.size)), with: .color(.white.opacity(f.opacity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
