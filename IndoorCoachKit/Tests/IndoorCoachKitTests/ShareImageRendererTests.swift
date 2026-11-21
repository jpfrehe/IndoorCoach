import ImageIO
import SwiftUI
import Testing
@testable import IndoorCoachKit

@MainActor
@Suite("Teilen-Renderer (AP0)")
struct ShareImageRendererTests {
    private func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    @Test func rendersAnyViewAtTheRequestedPixelSize() throws {
        let rendered = try #require(ShareImageRenderer.render(Color.orange, size: CGSize(width: 300, height: 200),
                                                              filename: "ap0-generic.png"))
        #expect(pixelSize(of: rendered.url) == CGSize(width: 300, height: 200))
        #expect(rendered.url.lastPathComponent == "ap0-generic.png")
        try? FileManager.default.removeItem(at: rendered.url)
    }

    @Test func seasonImageStaysTenEightyByThirteenFifty() throws {
        #expect(SeasonShareCard.size == CGSize(width: 1080, height: 1350))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = SeasonSummary(levelNumber: 3, levelName: "Rollen-Routine", levelSymbol: "snowflake", startCTL: 24,
                                    currentCTL: 33, streakWeeks: 5, challengesCompleted: 2, challengesTotal: 4,
                                    best20MinWatts: 231, seasonStart: now, seasonEnd: now.addingTimeInterval(86_400 * 140),
                                    name: nil)
        let rendered = try #require(SeasonShareRenderer.render(summary))
        #expect(pixelSize(of: rendered.url) == CGSize(width: 1080, height: 1350))
        #expect(rendered.url.lastPathComponent == "IndoorCoach-Saisonrückblick.png")
    }
}
