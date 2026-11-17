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

        public func contrast(with other: RGB) -> Double {
            let (a, b) = (luminance, other.luminance)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
    }

    /// One zone: the jelly `fill` (chips, bars) and a deeper `cap` (bar tops, lines, small glyphs on light).
    public struct Swatch: Sendable {
        public let name: String
        public let fill: RGB
        public let cap: RGB
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
        Swatch(name: "Z1 Lavendel", fill: RGB(hex: 0xC9C3E6), cap: RGB(hex: 0x948BA6)),
        Swatch(name: "Z2 Periwinkle", fill: RGB(hex: 0x8FA8FF), cap: RGB(hex: 0x7B8CD4)),
        Swatch(name: "Z3 Mint", fill: RGB(hex: 0x5EDBB8), cap: RGB(hex: 0x4C9D88)),
        Swatch(name: "Z4 Mango Pop", fill: mangoPop, cap: RGB(hex: 0xB58639)),
        Swatch(name: "Z5 Warm Coral", fill: warmCoral, cap: RGB(hex: 0xD8715F)),
        // Deeper than the brand jelly pink so Z5 (coral) and Z6 differ in hue *and* lightness.
        Swatch(name: "Z6 Hot Jelly", fill: RGB(hex: 0xF23D8B), cap: RGB(hex: 0xC92A6F)),
        Swatch(name: "Z7 Grape", fill: RGB(hex: 0xB48CFF), cap: RGB(hex: 0xA17CE2)),
    ]
}
