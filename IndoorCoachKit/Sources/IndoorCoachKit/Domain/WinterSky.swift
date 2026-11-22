import Foundation

/// Der Himmel des Winter Arc (docs/22, B3): Verlauf von der Winterdämmerung (Indigo) über den Sonnenuntergang
/// (`Theme.sunset`) zum Frühlingsmorgen (Mango). Drei Schlüsselbilder, dazwischen in OKLab interpoliert, damit der
/// Himmel gleichmäßig heller wird und nirgends grau durchläuft. Rein rechnerisch, ohne Daten und Verbindung.
public enum WinterSky {
    /// Höchstens so viele Flocken fallen im Kopf des Winter-Arc-Hubs (Level 1); mit dem Fortschritt werden es weniger.
    public static let maxFlakes = 40

    /// Drei Stopps je Schlüsselbild: oben, Mitte, Horizont. Die Anzahl hängt nie vom Fortschritt ab.
    private static let keyframes: [[Palette.RGB]] = [
        // Winterdämmerung: Indigo oben, Violett in der Mitte, Koralle am Horizont.
        [Palette.RGB(hex: 0x5152C1), Palette.RGB(hex: 0xA85DA0), Palette.warmCoral],
        // Sonnenuntergang: Beeren-Pink (etwas tiefer als Jelly-Pink), Koralle, Pfirsich.
        [Palette.RGB(hex: 0xF0699F), Palette.warmCoral, Palette.peachFizz],
        // Frühlingsmorgen: Mango oben, warmes Gelb-Pfirsich, Pfirsich am Horizont.
        [Palette.mangoPop, Palette.RGB(hex: 0xFFBA6B), Palette.peachFizz],
    ]

    /// Farbstopps des Himmels von oben nach unten für den Saisonfortschritt 0…1 (außerhalb wird begrenzt, NaN zählt als 0).
    /// Die Endpunkte und die Mitte sind genau die Schlüsselbilder.
    public static func stops(progress: Double) -> [Palette.RGB] {
        let t = clamped(progress)
        let scaled = t * Double(keyframes.count - 1)
        let index = min(keyframes.count - 2, Int(scaled))
        let local = scaled - Double(index)
        let from = keyframes[index], to = keyframes[index + 1]
        if local <= 0 { return from }
        if local >= 1 { return to }
        return zip(from, to).map { mix($0, $1, local) }
    }

    /// 1 im tiefen Winter, 0 im Frühling (Level 10): so dicht schneit es im Kopf des Hubs.
    public static func snowDensity(progress: Double) -> Double { 1 - clamped(progress) }

    /// Anzahl der Flocken (0…40) für den Fortschritt.
    public static func flakeCount(progress: Double) -> Int {
        Int((snowDensity(progress: progress) * Double(maxFlakes)).rounded())
    }

    /// Name der Stimmung, für Beschriftungen und Tests.
    public static func mood(progress: Double) -> String {
        switch clamped(progress) {
        case ..<0.25: "Winterdämmerung"
        case ..<0.75: "Sonnenuntergang"
        default: "Frühlingsmorgen"
        }
    }

    private static func clamped(_ progress: Double) -> Double {
        progress.isNaN ? 0 : min(1, max(0, progress))
    }

    // MARK: OKLab

    private static func mix(_ a: Palette.RGB, _ b: Palette.RGB, _ t: Double) -> Palette.RGB {
        let p = a.oklab, q = b.oklab
        return fromOKLab(l: p.l + (q.l - p.l) * t, a: p.a + (q.a - p.a) * t, b: p.b + (q.b - p.b) * t)
    }

    /// OKLab → sRGB (Björn Ottosson), auf den darstellbaren Bereich begrenzt.
    private static func fromOKLab(l: Double, a: Double, b: Double) -> Palette.RGB {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let (l3, m3, s3) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_)
        let r = +4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let bl = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        func encode(_ c: Double) -> Double { Palette.RGB.gamma(min(1, max(0, c))) }
        return Palette.RGB(r: encode(r), g: encode(g), b: encode(bl))
    }
}
