import SwiftUI

/// Chart colour tokens (concept 21 §3). Values live in `Palette` as testable sRGB data; this only wraps them in
/// mode-adaptive `Color`s. Zone marks belong on card surfaces only.
public enum ChartPalette {
    static func adaptive(_ light: Palette.RGB, _ dark: Palette.RGB) -> Color {
        Color(light: Color(light), dark: Color(dark))
    }

    public static func zone(_ zone: PowerZone) -> Color {
        adaptive(Palette.mark(zone, dark: false), Palette.mark(zone, dark: true))
    }

    /// Text/glyph colour on a tall segment of `zone` (white or ink, ≥ 4.2:1).
    static func label(on zone: PowerZone) -> Color {
        adaptive(Palette.labelInk(on: zone, dark: false), Palette.labelInk(on: zone, dark: true))
    }

    static let fitness = zone(.z2)
    static let fatigue = zone(.z6)
    static let accentMuted = adaptive(Palette.accentMuted(dark: false), Palette.accentMuted(dark: true))
    static let reference = adaptive(Palette.reference(dark: false), Palette.reference(dark: true))
    static let grid = adaptive(Palette.grid(dark: false), Palette.grid(dark: true))
    static let baseline = adaptive(Palette.baseline(dark: false), Palette.baseline(dark: true))
    static let band = adaptive(Palette.band(dark: false), Palette.band(dark: true))
}
