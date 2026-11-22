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

    /// Teilen-Bilder tragen feste Namen („IndoorCoach-…png“) im temporären Ordner. Beim nächsten Rendern räumt die App ältere
    /// weg (ein Bild, das gerade geteilt wird, ist jünger als `maxAge`).
    static let filePrefix = "IndoorCoach-"
    static let maxAge: TimeInterval = 15 * 60

    /// Löscht `IndoorCoach-*.png` in `directory`, die älter als `maxAge` sind (außer `keeping`). Gibt die Zahl gelöschter Dateien zurück.
    @discardableResult
    static func removeStale(in directory: URL = FileManager.default.temporaryDirectory, keeping: String? = nil, now: Date = .now,
                            maxAge: TimeInterval = ShareImageRenderer.maxAge) -> Int {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var removed = 0
        for url in files where url.lastPathComponent.hasPrefix(filePrefix) && url.pathExtension == "png" && url.lastPathComponent != keeping {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modified) > maxAge else { continue }
            if (try? manager.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
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
        removeStale(keeping: filename)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Rendered(url: url, preview: Image(decorative: image, scale: 1))
    }
}
