import Testing
@testable import IndoorCoachKit

/// WCAG 2.2 contrast guarantees of the "Sunset Jelly" palette.
@Suite("Sunset Jelly palette")
struct PaletteTests {
    @Test func contrastFormulaMatchesWCAGReference() {
        let black = Palette.RGB(hex: 0x000000), white = Palette.RGB(hex: 0xFFFFFF)
        #expect(abs(black.contrast(with: white) - 21) < 0.01)
        #expect(abs(Palette.RGB(hex: 0x777777).contrast(with: white) - 4.48) < 0.02)
    }

    @Test func inkTextOnEveryJellyFillIsAA() {
        let fills = Palette.zones.map(\.fill) + [Palette.peachFizz, Palette.jellyPink, Palette.warmCoral, Palette.mangoPop]
        for fill in fills {
            #expect(Palette.ink.contrast(with: fill) >= 4.5, "ink on \(fill)")
        }
    }

    @Test func whiteTextOnJellyFillsWouldFail() {
        // Documents why primary buttons use ink labels instead of white.
        let white = Palette.RGB(hex: 0xFFFFFF)
        #expect(Palette.jellyPink.contrast(with: white) < 3)
        #expect(Palette.mangoPop.contrast(with: white) < 3)
    }

    @Test func accentTextIsAAInBothModes() {
        #expect(Palette.accentTextLight.contrast(with: Palette.cardLight) >= 4.5)
        #expect(Palette.accentTextLight.contrast(with: Palette.canvasLight) >= 4.5)
        #expect(Palette.accentTextDark.contrast(with: Palette.canvasDark) >= 4.5)
        #expect(Palette.accentTextDark.contrast(with: Palette.cardDark) >= 4.5)
    }

    @Test func zoneCapsMeetNonTextContrastOnCards() {
        for zone in Palette.zones {
            #expect(zone.cap.contrast(with: Palette.cardLight) >= 3, "\(zone.name) cap on light card")
            #expect(zone.fill.contrast(with: Palette.cardDark) >= 3, "\(zone.name) fill on dark card")
        }
    }

    @Test func neighbouringZonesAreDistinguishable() {
        // Adjacent zones must differ clearly in hue or lightness so intensity stays readable at a glance.
        let fills = Palette.zones.map(\.fill)
        for (a, b) in zip(fills, fills.dropFirst()) {
            let distance = abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
            #expect(distance > 0.35, "\(a) vs \(b)")
        }
    }

    @Test func sevenZonesInConventionalOrder() {
        #expect(Palette.zones.map(\.name) == ["Z1 Lavendel", "Z2 Periwinkle", "Z3 Mint", "Z4 Mango Pop",
                                             "Z5 Warm Coral", "Z6 Hot Jelly", "Z7 Grape"])
    }
}
