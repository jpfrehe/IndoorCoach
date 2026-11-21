import Foundation

/// "Sunset Jelly" colour tokens as plain data, so contrast rules can be unit-tested without SwiftUI.
///
/// Rules (WCAG 2.2):
/// - Text on a jelly fill is always `ink` (≥ 4.5:1, measured 6.9–11:1). White text on jelly fills fails (≤ 2.6:1).
/// - Coloured text on light backgrounds uses `accentTextLight` (≥ 4.5:1), never a jelly fill colour.
/// - Chart marks are a jelly fill plus a `cap` line in the deeper tone (≥ 3:1 against the light card).
/// - Zone order keeps the convention MyWhoosh/Zwift users know: grey → blue → green → yellow → orange → red → violet.
public enum Palette {
    public struct RGB: Equatable, Sendable {
        public let r, g, b: Double
        public init(hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }

        /// WCAG relative luminance.
        public var luminance: Double {
            func channel(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }

        /// OKLab coordinates (Björn Ottosson), from sRGB.
        public var oklab: (l: Double, a: Double, b: Double) {
            let (lr, lg, lb) = (Self.linear(r), Self.linear(g), Self.linear(b))
            let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
            let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
            let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
            return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
        }

        /// Perceptual distance in OKLab, scaled by 100 (≥ 15 reads as clearly different).
        public func deltaE(to other: RGB) -> Double {
            let (p, q) = (oklab, other.oklab)
            return 100 * (pow(p.l - q.l, 2) + pow(p.a - q.a, 2) + pow(p.b - q.b, 2)).squareRoot()
        }

        /// Colour seen with full protan/deuteran deficiency (Machado et al. 2009, severity 1.0, linear RGB).
        public func simulating(_ vision: ColorVision) -> RGB {
            let m = vision.matrix
            let (lr, lg, lb) = (Self.linear(r), Self.linear(g), Self.linear(b))
            func out(_ row: Int) -> Double { min(1, max(0, m[row][0] * lr + m[row][1] * lg + m[row][2] * lb)) }
            return RGB(r: Self.gamma(out(0)), g: Self.gamma(out(1)), b: Self.gamma(out(2)))
        }

        /// This colour drawn with `alpha` over `background` (sRGB blend, as the compositor does).
        public func over(_ background: RGB, alpha: Double) -> RGB {
            RGB(r: r * alpha + background.r * (1 - alpha), g: g * alpha + background.g * (1 - alpha),
                b: b * alpha + background.b * (1 - alpha))
        }

        init(r: Double, g: Double, b: Double) { (self.r, self.g, self.b) = (r, g, b) }

        static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        static func gamma(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

        public func contrast(with other: RGB) -> Double {
            let (a, b) = (luminance, other.luminance)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
    }

    public enum ColorVision: Sendable {
        case protanopia, deuteranopia

        var matrix: [[Double]] {
            switch self {
            case .protanopia: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]
            case .deuteranopia: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
            }
        }
    }

    /// One zone: the jelly `fill` (chips, bars) and a deeper `cap` (bar tops, lines, small glyphs on light).
    public struct Swatch: Sendable {
        public let name: String
        public let fill: RGB
        public let cap: RGB
        /// Chart mark for light mode (≥ 3:1 on the white card, concept 21 §3.2). Chips keep `fill`.
        public let mark: RGB
        /// Chart mark for dark mode (≥ 3:1 on the dark card and on black).
        public let markDark: RGB
    }

    // MARK: Neutrals

    /// Plum-black for text and glyphs on jelly fills.
    public static let ink = RGB(hex: 0x24131D)
    /// Warm "paper" canvas behind cards in light mode (from the poster background).
    public static let canvasLight = RGB(hex: 0xFBF6F2)
    public static let cardLight = RGB(hex: 0xFFFFFF)
    public static let canvasDark = RGB(hex: 0x000000)
    public static let cardDark = RGB(hex: 0x1C1C1E)

    // MARK: Brand (Sunset Jelly)

    public static let peachFizz = RGB(hex: 0xFFB38A)
    public static let jellyPink = RGB(hex: 0xFF6FAE)
    public static let warmCoral = RGB(hex: 0xFF866E)
    public static let mangoPop = RGB(hex: 0xFFC247)

    /// Tint for text, links and system controls in light mode (deep jelly berry).
    public static let accentTextLight = RGB(hex: 0xB5175A)
    /// In dark mode the jelly pink itself is readable on black and on dark cards.
    public static let accentTextDark = jellyPink

    // MARK: Training zones (Coggan Z1–Z7)

    public static let zones: [Swatch] = [
        Swatch(name: "Z1 Lavendel", fill: RGB(hex: 0xC9C3E6), cap: RGB(hex: 0x948BA6), mark: RGB(hex: 0x5152C1), markDark: RGB(hex: 0x5863DA)),
        Swatch(name: "Z2 Periwinkle", fill: RGB(hex: 0x8FA8FF), cap: RGB(hex: 0x7B8CD4), mark: RGB(hex: 0x4998DD), markDark: RGB(hex: 0x1BA0D5)),
        Swatch(name: "Z3 Mint", fill: RGB(hex: 0x5EDBB8), cap: RGB(hex: 0x4C9D88), mark: RGB(hex: 0x048E5C), markDark: RGB(hex: 0x19925D)),
        Swatch(name: "Z4 Mango Pop", fill: mangoPop, cap: RGB(hex: 0xB58639), mark: RGB(hex: 0xB68E0A), markDark: RGB(hex: 0xB29000)),
        Swatch(name: "Z5 Warm Coral", fill: warmCoral, cap: RGB(hex: 0xD8715F), mark: RGB(hex: 0xC74007), markDark: RGB(hex: 0xD13D1A)),
        // Deeper than the brand jelly pink so Z5 (coral) and Z6 differ in hue *and* lightness.
        Swatch(name: "Z6 Hot Jelly", fill: RGB(hex: 0xF23D8B), cap: RGB(hex: 0xC92A6F), mark: RGB(hex: 0xE34992), markDark: RGB(hex: 0xE658A0)),
        Swatch(name: "Z7 Grape", fill: RGB(hex: 0xB48CFF), cap: RGB(hex: 0xA17CE2), mark: RGB(hex: 0x7F36BC), markDark: RGB(hex: 0x9A43CE)),
    ]

    // MARK: Chart marks (concept 21 §3.2/§3.3)

    /// Zone mark colour for charts. Marks live on card surfaces only (Z2/Z4 are < 3:1 on the warm canvas).
    public static func mark(_ zone: PowerZone, dark: Bool) -> RGB {
        let swatch = zones[zone.rawValue - 1]
        return dark ? swatch.markDark : swatch.mark
    }

    public static func card(dark: Bool) -> RGB { dark ? cardDark : cardLight }
    /// Text/primary colour of the system (black in light, white in dark mode).
    static func primary(dark: Bool) -> RGB { dark ? RGB(hex: 0xFFFFFF) : RGB(hex: 0x000000) }

    public static func fitness(dark: Bool) -> RGB { mark(.z2, dark: dark) }
    public static func fatigue(dark: Bool) -> RGB { mark(.z6, dark: dark) }

    /// Accent muted but opaque (earlier weeks): 3.1:1 light, 3.2:1 dark.
    public static func accentMuted(dark: Bool) -> RGB { dark ? RGB(hex: 0xA44E74) : RGB(hex: 0xD3749C) }
    /// Comparison, target and FTP lines: primary at 55 % on the card (4.7:1 / 6.0:1).
    public static func reference(dark: Bool) -> RGB { primary(dark: dark).over(card(dark: dark), alpha: 0.55) }
    /// Earlier weeks in bar charts: a lighter neutral than `reference` (primary at 45 %), still ≥ 3:1 on the card,
    /// so only the current week carries colour (as in the reference designs).
    public static func pastBar(dark: Bool) -> RGB { primary(dark: dark).over(card(dark: dark), alpha: 0.45) }
    /// Horizontal grid hairline: primary at 10 % on the card (≈ 1.25:1 / 1.35:1).
    public static func grid(dark: Bool) -> RGB { primary(dark: dark).over(card(dark: dark), alpha: 0.10) }
    /// Baseline hairline: primary at 25 %.
    public static func baseline(dark: Bool) -> RGB { primary(dark: dark).over(card(dark: dark), alpha: 0.25) }
    /// Neutral band (target range, "ausgewogen"): primary at 6 %.
    public static func band(dark: Bool) -> RGB { primary(dark: dark).over(card(dark: dark), alpha: 0.06) }

    /// Label colour on a tall zone-coloured segment: white or ink, whichever reads better (≥ 4.2:1 for every zone).
    public static func labelInk(on zone: PowerZone, dark: Bool) -> RGB {
        let mark = mark(zone, dark: dark), white = RGB(hex: 0xFFFFFF)
        return white.contrast(with: mark) >= ink.contrast(with: mark) ? white : ink
    }
}
