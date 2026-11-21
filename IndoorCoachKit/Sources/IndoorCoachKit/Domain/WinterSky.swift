import Foundation

/// Der Himmel des Winter Arc (docs/22, B3): Verlauf von der Winterdämmerung (Indigo) zum Frühlingsmorgen (Mango).
/// AP0: fester Vertrag mit linearem Platzhalter. Agent B ersetzt die Berechnung durch OKLab-Schlüsselbilder
/// (Indigo → Koralle, Sunset, Mango → Pfirsich), die Signatur bleibt.
public enum WinterSky {
    /// Farbstopps des Himmels von oben nach unten für den Saisonfortschritt 0…1 (außerhalb wird begrenzt).
    /// Die Anzahl der Stopps hängt nicht vom Fortschritt ab.
    public static func stops(progress: Double) -> [Palette.RGB] {
        let t = min(1, max(0, progress))
        return [mix(0x5152C1, 0xFFC247, t), mix(0xFF866E, 0xFFB38A, t)]
    }

    private static func mix(_ from: UInt32, _ to: UInt32, _ t: Double) -> Palette.RGB {
        if t <= 0 { return Palette.RGB(hex: from) }
        if t >= 1 { return Palette.RGB(hex: to) }
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Double((from >> shift) & 0xFF), b = Double((to >> shift) & 0xFF)
            return UInt32((a + (b - a) * t).rounded())
        }
        return Palette.RGB(hex: channel(16) << 16 | channel(8) << 8 | channel(0))
    }
}
