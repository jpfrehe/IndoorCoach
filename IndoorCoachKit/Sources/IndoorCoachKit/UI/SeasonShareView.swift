import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// G5 – the image behind "Saisonrückblick teilen": 1080 × 1350 px, Sunset-Jelly, ink on peach/coral/white
/// (≥ 6.9:1). Pure value input (no environment), so `ImageRenderer` can draw it anywhere. Non-lazy.
struct SeasonShareCard: View {
    static let size = CGSize(width: 1080, height: 1350)
    var summary: SeasonSummary

    private var inkSoft: Color { Theme.ink.opacity(0.8) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("MEIN WINTER ARC")
                    .font(.system(size: 36, weight: .heavy)).tracking(4)
                Text(summary.periodText).font(.system(size: 40, weight: .semibold))
                if let name = summary.name {
                    Text(name).font(.system(size: 40, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.top, 88)

            Spacer(minLength: 24)

            VStack(spacing: 20) {
                Image(systemName: summary.levelSymbol)
                    .font(.system(size: 120, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 260, height: 260)
                    .background(Color.white.opacity(0.55), in: Circle())
                Text("Level \(summary.levelNumber)").font(.system(size: 132, weight: .heavy))
                Text(summary.levelName)
                    .font(.system(size: 60, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.ink)

            Spacer(minLength: 24)

            VStack(spacing: 24) {
                HStack(spacing: 24) {
                    stat("Fitness", summary.fitnessText)
                    stat("Serie", summary.streakText)
                }
                HStack(spacing: 24) {
                    stat("Challenges", summary.challengesText)
                    stat("Beste 20 min", summary.best20MinText)
                }
            }
            .padding(.horizontal, 72)

            Text("IndoorCoach")
                .font(.system(size: 36, weight: .bold)).tracking(2)
                .foregroundStyle(Theme.ink)
                .padding(.top, 44).padding(.bottom, 64)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.sunset)
        .environment(\.colorScheme, .light)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(value).font(.system(size: 64, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.system(size: 34, weight: .semibold)).foregroundStyle(inkSoft)
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 44, style: .continuous))
    }
}

/// Renders the share image to a PNG in the temporary directory.
enum SeasonShareRenderer {
    struct Rendered {
        var url: URL
        var preview: Image
    }

    @MainActor
    static func render(_ summary: SeasonSummary) -> Rendered? {
        let renderer = ImageRenderer(content: SeasonShareCard(summary: summary))
        renderer.scale = 1   // 1 pt = 1 px → exactly 1080 × 1350
        guard let image = renderer.cgImage else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IndoorCoach-Saisonrückblick.png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Rendered(url: url, preview: Image(decorative: image, scale: 1))
    }
}

/// The card at `ANCHOR-P3-WINTERARC`: a button that shares the season image.
struct SeasonShareSection: View {
    var summary: SeasonSummary
    @State private var rendered: SeasonShareRenderer.Rendered?

    var body: some View {
        Card(title: "Saisonrückblick", systemImage: "square.and.arrow.up") {
            Text("Dein Winter Arc als Bild: Level, Fitness, Serie, Challenges und deine beste 20-Minuten-Leistung.")
                .font(.subheadline)
            if let rendered {
                ShareLink(item: rendered.url, message: Text(summary.caption),
                          preview: SharePreview("Saisonrückblick", image: rendered.preview)) {
                    Label("Saisonrückblick teilen", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(JellyButtonStyle())
                .accessibilityIdentifier("season.share")
                .accessibilityHint("Öffnet das Teilen-Menü mit deinem Saisonbild")
            } else {
                Button {} label: {
                    HStack(spacing: 8) { ProgressView(); Text("Bild wird erstellt …") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(JellyButtonStyle())
                .disabled(true)
                .accessibilityIdentifier("season.share")
            }
            if summary.name != nil {
                Text("Auf dem Bild steht dein Name aus dem Profil.")
                    .font(.caption).foregroundStyle(Theme.rowSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .task(id: summary) { rendered = SeasonShareRenderer.render(summary) }
    }
}
