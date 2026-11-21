import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Gemeinsamer Renderer für alle Teilen-Bilder (Saisonrückblick, Gipfelmoment, Postkarte): zeichnet eine reine
/// Wert-View mit `ImageRenderer` pixelgenau (1 pt = 1 px) in eine PNG-Datei im temporären Ordner. Teilen läuft nur
/// über das System-Teilen-Menü nach einem Tipp.
enum ShareImageRenderer {
    struct Rendered {
        var url: URL
        var preview: Image
    }

    /// - Parameters:
    ///   - view: das Bild; es soll keine Umgebung brauchen (`@Environment`), weil es außerhalb der Hierarchie gezeichnet wird.
    ///   - size: Größe in Pixeln (z. B. 1080 × 1350, 1080 × 1920, 1500 × 1000).
    ///   - filename: Dateiname im temporären Ordner, z. B. `IndoorCoach-Saisonrückblick.png`.
    @MainActor
    static func render<V: View>(_ view: V, size: CGSize, filename: String) -> Rendered? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Rendered(url: url, preview: Image(decorative: image, scale: 1))
    }
}
