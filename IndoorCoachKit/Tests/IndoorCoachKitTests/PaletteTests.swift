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

/// Chart palette (concept 21 §3.2): zone marks per mode, derived neutrals, contrast and colour-vision separation.
@Suite("Chart palette")
struct ChartPaletteTests {
    typealias RGB = Palette.RGB
    static let zones = PowerZone.allCases

    /// Vorwochen-Balken: heller als `reference`, aber weiterhin ≥ 3:1 auf der Karte (WCAG 1.4.11), hell und dunkel.
    @Test(arguments: [false, true]) func pastBarIsLighterThanReferenceButStillReadable(dark: Bool) {
        let card = Palette.card(dark: dark)
        #expect(Palette.pastBar(dark: dark).contrast(with: card) >= 3.0)
        #expect(Palette.pastBar(dark: dark).contrast(with: card) < Palette.reference(dark: dark).contrast(with: card))
    }

    @Test func zoneMarksMeetNonTextContrastOnCards() {
        for zone in Self.zones {
            let light = Palette.mark(zone, dark: false), dark = Palette.mark(zone, dark: true)
            #expect(light.contrast(with: Palette.cardLight) >= 3.0, "\(zone) light on card")
            #expect(dark.contrast(with: Palette.cardDark) >= 3.0, "\(zone) dark on card")
            #expect(dark.contrast(with: Palette.canvasDark) >= 3.0, "\(zone) dark on canvas")
        }
    }

    @Test func zoneMarksAreOnlyForCards() {
        // Documented limitation: Z2 and Z4 stay below 3:1 on the warm light canvas, so marks live on cards only.
        for zone in [PowerZone.z2, .z4] {
            let c = Palette.mark(zone, dark: false).contrast(with: Palette.canvasLight)
            #expect(c < 3.0 && c > 2.5, "\(zone) on canvas \(c)")
        }
        #expect(Palette.mark(.z1, dark: false).contrast(with: Palette.canvasLight) >= 3.0)
    }

    @Test func zoneMarksMatchConceptTable() {
        let light = [0x5152C1, 0x4998DD, 0x048E5C, 0xB68E0A, 0xC74007, 0xE34992, 0x7F36BC]
        let dark = [0x5863DA, 0x1BA0D5, 0x19925D, 0xB29000, 0xD13D1A, 0xE658A0, 0x9A43CE]
        for (i, zone) in Self.zones.enumerated() {
            #expect(Palette.mark(zone, dark: false) == RGB(hex: UInt32(light[i])))
            #expect(Palette.mark(zone, dark: true) == RGB(hex: UInt32(dark[i])))
            #expect(Palette.zones[i].mark == RGB(hex: UInt32(light[i])))
            #expect(Palette.zones[i].markDark == RGB(hex: UInt32(dark[i])))
        }
    }

    @Test func adjacentZoneMarksSeparateForNormalVision() {
        for dark in [false, true] {
            for (a, b) in zip(Self.zones, Self.zones.dropFirst()) {
                let d = Palette.mark(a, dark: dark).deltaE(to: Palette.mark(b, dark: dark))
                #expect(d >= 15, "\(a)/\(b) dark=\(dark) ΔE \(d)")
            }
        }
    }

    @Test func adjacentZoneMarksSeparateUnderCVD() {
        // Second coding (height, gaps, legend, VoiceOver) is always present: light ≥ 8, dark ≥ 6 (measured 7.6).
        for cvd in [Palette.ColorVision.protanopia, .deuteranopia] {
            for dark in [false, true] {
                for (a, b) in zip(Self.zones, Self.zones.dropFirst()) {
                    let d = Palette.mark(a, dark: dark).simulating(cvd).deltaE(to: Palette.mark(b, dark: dark).simulating(cvd))
                    #expect(d >= (dark ? 6 : 8), "\(a)/\(b) \(cvd) dark=\(dark) ΔE \(d)")
                }
            }
        }
    }

    @Test func fitnessAndFatigueSeparateAllPairs() {
        for dark in [false, true] {
            let pair = [Palette.fitness(dark: dark), Palette.fatigue(dark: dark)]
            #expect(pair[0].deltaE(to: pair[1]) >= 15)
            for cvd in [Palette.ColorVision.protanopia, .deuteranopia] {
                #expect(pair[0].simulating(cvd).deltaE(to: pair[1].simulating(cvd)) >= 8, "\(cvd) dark=\(dark)")
            }
        }
        #expect(Palette.fitness(dark: false) == Palette.mark(.z2, dark: false))
        #expect(Palette.fatigue(dark: true) == Palette.mark(.z6, dark: true))
    }

    @Test func accentMutedMeetsThreeToOne() {
        #expect(Palette.accentMuted(dark: false) == RGB(hex: 0xD3749C))
        #expect(Palette.accentMuted(dark: true) == RGB(hex: 0xA44E74))
        #expect(Palette.accentMuted(dark: false).contrast(with: Palette.cardLight) >= 3.0)
        #expect(Palette.accentMuted(dark: true).contrast(with: Palette.cardDark) >= 3.0)
    }

    @Test func referenceLineMeetsThreeToOne() {
        // primary at 55 % composited on the card: 4.7:1 light / 6.0:1 dark.
        let light = Palette.reference(dark: false).contrast(with: Palette.cardLight)
        let dark = Palette.reference(dark: true).contrast(with: Palette.cardDark)
        #expect(light >= 4.5 && light < 5.0, "\(light)")
        #expect(dark >= 5.5 && dark < 6.5, "\(dark)")
    }

    @Test func gridIsRecessive() {
        let light = Palette.grid(dark: false).contrast(with: Palette.cardLight)
        let dark = Palette.grid(dark: true).contrast(with: Palette.cardDark)
        #expect((1.15...1.6).contains(light), "\(light)")
        #expect((1.15...1.6).contains(dark), "\(dark)")
        #expect(Palette.baseline(dark: false).contrast(with: Palette.cardLight) > light)
        #expect(Palette.band(dark: false).contrast(with: Palette.cardLight) < light)
    }

    @Test func labelOnTallSegmentPicksReadableInk() {
        // Concept asks for ≥ 4.5:1; Z3 reaches at most 4.24 (light) / 4.48 (dark) with the fixed mark colours.
        for dark in [false, true] {
            for zone in Self.zones {
                let mark = Palette.mark(zone, dark: dark)
                let ink = Palette.labelInk(on: zone, dark: dark)
                #expect(ink.contrast(with: mark) >= 4.2, "\(zone) dark=\(dark) \(ink.contrast(with: mark))")
                let white = RGB(hex: 0xFFFFFF)
                #expect(ink.contrast(with: mark) >= max(white.contrast(with: mark), Palette.ink.contrast(with: mark)) - 1e-9)
            }
        }
        #expect(Palette.labelInk(on: .z1, dark: false) == RGB(hex: 0xFFFFFF))
        #expect(Palette.labelInk(on: .z2, dark: false) == Palette.ink)
    }

    @Test func oklabMatchesReference() {
        #expect(abs(RGB(hex: 0xFFFFFF).oklab.l - 1.0) < 0.001)
        #expect(abs(RGB(hex: 0x000000).oklab.l) < 0.001)
        #expect(abs(RGB(hex: 0x5152C1).oklab.l - 0.50) < 0.01)
        #expect(abs(RGB(hex: 0x4998DD).oklab.l - 0.66) < 0.01)
        #expect(RGB(hex: 0x5152C1).deltaE(to: RGB(hex: 0x5152C1)) == 0)
    }
}
