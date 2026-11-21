import SwiftUI

/// Segmented bar (concept 21 §5): `.thin` for "Zeit in Zonen" (D3), `.tall` for distributions with a share inside
/// the segment (D17). Every segment is its own rounded block; gaps are whole pixels (see `SegmentedBarLayout`).
/// Pure SwiftUI `Canvas`, so no clip can cut the rounding of the first and last segment.
struct SegmentedBar: View {
    enum Variant {
        case thin, tall

        var height: CGFloat { self == .thin ? 10 : 28 }
    }

    struct Item: Identifiable {
        var id: Int
        var value: Double
        var color: Color
        /// Share text inside a `.tall` segment, drawn only when it fits.
        var label: String?
        var labelColor: Color = .white
    }

    var items: [Item]
    var variant: Variant = .thin
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let items = items, variant = variant, scale = max(displayScale, 1)
        Canvas { context, size in
            let layout = SegmentedBarLayout.make(values: items.map(\.value), width: size.width, scale: scale)
            for slot in layout {
                let item = items[slot.index]
                let rect = CGRect(x: slot.x, y: 0, width: slot.width, height: size.height)
                let radius = variant == .thin ? min(size.height, slot.width) / 2 : min(4, slot.width / 2, size.height / 2)
                context.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), with: .color(item.color))
                if variant == .tall, let label = item.label {
                    let text = context.resolve(Text(label).font(.caption.weight(.semibold)).foregroundColor(item.labelColor))
                    if text.measure(in: size).width + 12 <= rect.width {
                        context.draw(text, at: CGPoint(x: rect.minX + 6, y: rect.midY), anchor: .leading)
                    }
                }
            }
        }
        .frame(height: variant.height)
    }
}
