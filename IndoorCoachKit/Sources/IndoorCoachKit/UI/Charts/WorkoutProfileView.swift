import Accessibility
import Charts
import SwiftUI

// Workout profile (concept 21 §4): one geometry (`WorkoutProfileGeometry`), one `Canvas` renderer, two shells.
// `WorkoutProfileView` is the axis-less mini for lists and cards; `WorkoutProfileChart` wraps the same renderer in
// Swift Charts for axes, the FTP line and selection.

// MARK: - Renderer

enum WorkoutProfileRenderer {
    struct Style {
        /// "Ausgelassen": every block in the neutral reference colour instead of its zone colour.
        var skipped = false
        /// When set, all blocks of other steps are dimmed (detail selection).
        var highlightedStep: Int?
        /// Hairline along the bottom edge (detail variant).
        var baseline = false
    }

    /// Block outline with rounded corners only where `roundedCorners` says so (ramps keep their slanted top edge).
    static func path(for block: ProfileBlock) -> Path {
        let p = block.polygon
        guard p.count == 4 else { return Path() }
        var path = Path()
        guard block.cornerRadius > 0, !block.roundedCorners.isEmpty else {
            path.addLines(p)
            path.closeSubpath()
            return path
        }
        let corners: [ProfileBlock.Corners] = [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading]
        path.move(to: CGPoint(x: (p[3].x + p[0].x) / 2, y: (p[3].y + p[0].y) / 2))
        for i in 0..<4 {
            if block.roundedCorners.contains(corners[i]) {
                path.addArc(tangent1End: p[i], tangent2End: p[(i + 1) % 4], radius: block.cornerRadius)
            } else {
                path.addLine(to: p[i])
            }
        }
        path.closeSubpath()
        return path
    }

    static func color(for block: ProfileBlock, style: Style) -> Color {
        style.skipped ? ChartPalette.reference : ChartPalette.zone(block.zone)
    }

    /// Draws the blocks in array order (off-fill before stakes). `Canvas` hands out the context by `inout`.
    static func draw(_ blocks: [ProfileBlock], in context: inout GraphicsContext, size: CGSize, scale: CGFloat, style: Style) {
        // Nothing may leave the plot rectangle, whatever the geometry says.
        context.clip(to: Path(CGRect(origin: .zero, size: size)))
        if style.baseline {
            let line = 1 / scale
            context.fill(Path(CGRect(x: 0, y: size.height - line, width: size.width, height: line)), with: .color(ChartPalette.baseline))
        }
        for block in blocks {
            let path = path(for: block)
            let color = color(for: block, style: style)
            let dimmed = style.highlightedStep.map { $0 != block.stepIndex } ?? false
            var layer = context
            if dimmed { layer.opacity = 0.45 }
            if block.role == .hatched {
                // 45° hatching: a set too dense even for 1 px stakes (VoiceOver names the real count).
                layer.clip(to: path)
                layer.fill(path, with: .color(color.opacity(0.35)))
                let b = block.bounds
                var lines = Path()
                var x = b.minX - b.height
                while x < b.maxX {
                    lines.move(to: CGPoint(x: x, y: b.maxY))
                    lines.addLine(to: CGPoint(x: x + b.height, y: b.minY))
                    x += 3
                }
                layer.stroke(lines, with: .color(color), lineWidth: 1)
            } else {
                layer.fill(path, with: .color(color))
            }
        }
    }
}

extension WorkoutProfileGeometry.Variant {
    /// Default height in points; call sites may override (Heute 64, Planvorschlag 56).
    var defaultHeight: CGFloat {
        switch self {
        case .row: 34
        case .card: 64
        case .preview: 110
        case .detail: 210
        case .accessibilityRow: 28
        }
    }
}

// MARK: - Mini

/// Axis-less profile for rows, cards and previews. `Equatable`: use `.equatable()` so unchanged rows do not redraw
/// while scrolling. One VoiceOver element with the summary sentence.
struct WorkoutProfileView: View, @MainActor Equatable {
    var definition: WorkoutDefinition
    var ftp: Int
    var variant: WorkoutProfileGeometry.Variant = .row
    var height: CGFloat?
    var skipped = false
    @Environment(\.displayScale) private var displayScale

    static func == (lhs: WorkoutProfileView, rhs: WorkoutProfileView) -> Bool {
        lhs.definition == rhs.definition && lhs.ftp == rhs.ftp && lhs.variant == rhs.variant
            && lhs.height == rhs.height && lhs.skipped == rhs.skipped
    }

    var body: some View {
        let definition = definition, variant = variant, style = WorkoutProfileRenderer.Style(skipped: skipped)
        let scale = max(displayScale, 1)
        Canvas { context, size in
            let blocks = WorkoutProfileGeometry.cachedMake(definition: definition, size: size, scale: scale, variant: variant)
            if variant == .preview {
                // FTP (100 %) as a hairline behind the blocks, snapped to a pixel row.
                let y = (floor(size.height * (1 - 1 / WorkoutProfileGeometry.domainTop(for: definition, variant: variant)) * scale) + 0.5) / scale
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(ChartPalette.reference), lineWidth: 1 / scale)
            }
            WorkoutProfileRenderer.draw(blocks, in: &context, size: size, scale: scale, style: style)
        }
        .frame(height: height ?? variant.defaultHeight)
        // Canvas is invisible to VoiceOver and XCUITest: one element with label, sentence and identifier.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Leistungsprofil \(definition.title)")
        .accessibilityValue(accessibilitySummary)
        .accessibilityIdentifier("profile.mini")
    }

    var accessibilitySummary: String { WorkoutProfileSupport.summary(definition: definition, ftp: ftp) }
}

// MARK: - Detail

/// Detail profile (210 pt): Swift Charts supplies axes on the right, the dashed FTP line and the selection; the blocks
/// come from the same renderer inside `chartBackground`.
struct WorkoutProfileChart: View {
    var definition: WorkoutDefinition
    var ftp: Int
    var height: CGFloat = WorkoutProfileGeometry.Variant.detail.defaultHeight

    @State private var selectedMinute: Double?
    @State private var plotSize: CGSize = .zero
    @Environment(\.displayScale) private var displayScale

    private var scale: CGFloat { max(displayScale, 1) }
    private var totalMinutes: Double { max(Double(definition.totalDuration) / 60, 1.0 / 60) }
    private var domainTop: Double { WorkoutProfileGeometry.domainTop(for: definition, variant: .detail) * 100 }

    /// Step under the selection, found on the drawn blocks (gaps shift them slightly against the time axis).
    private var selectedStep: Int? {
        guard let selectedMinute, plotSize.width > 0 else { return nil }
        let blocks = WorkoutProfileGeometry.cachedMake(definition: definition, size: plotSize, scale: scale, variant: .detail)
        let x = CGFloat(min(max(selectedMinute / totalMinutes, 0), 1)) * plotSize.width
        return WorkoutProfileSupport.stepIndex(atX: x, blocks: blocks)
    }

    var body: some View {
        let step = selectedStep
        VStack(alignment: .leading, spacing: 4) {
            header(step: step)
            chart(step: step)
        }
    }

    private func header(step: Int?) -> some View {
        let text = step.flatMap { WorkoutProfileSupport.selectionText(definition: definition, ftp: ftp, stepIndex: $0) }
        return HStack(alignment: .center) {
            Text(text ?? "Abschnitt antippen für Details")
                .font(.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(text == nil ? Theme.rowSecondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if text != nil {
                Button { selectedMinute = nil } label: {
                    Text("Aufheben").frame(minHeight: 44).contentShape(Rectangle())
                }
                .font(.caption.weight(.semibold))
            }
        }
        .frame(minHeight: 44)
        .animation(nil, value: step)
    }

    private func chart(step: Int?) -> some View {
        let definition = definition, scale = scale
        let ticks = WorkoutProfileSupport.minuteTicks(totalSeconds: definition.totalDuration).map(Double.init)
        let yTicks = [50, 100, 150].filter { Double($0) <= domainTop }
        let style = WorkoutProfileRenderer.Style(highlightedStep: step, baseline: true)
        return Chart {
            RuleMark(y: .value("FTP", 100))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(ChartPalette.reference)
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("FTP \(ftp) W").font(.caption2.weight(.semibold)).foregroundStyle(Theme.axisLabel)
                }
        }
        .chartYScale(domain: 0...domainTop)
        .chartXScale(domain: 0...totalMinutes)
        .chartXSelection(value: $selectedMinute)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))′").font(.caption2).monospacedDigit().foregroundStyle(Theme.axisLabel)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: yTicks) { value in
                // No horizontal grid here: the blocks are drawn behind the plot and a grid would cut through them.
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v * ftp / 100) W").font(.caption2).monospacedDigit().foregroundStyle(Theme.axisLabel)
                    }
                }
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    let frame = geo[anchor]
                    // Plot rectangle on the pixel grid so block edges stay sharp.
                    let origin = CGPoint(x: (frame.minX * scale).rounded() / scale, y: (frame.minY * scale).rounded() / scale)
                    let size = CGSize(width: (frame.width * scale).rounded() / scale, height: (frame.height * scale).rounded() / scale)
                    Canvas { context, canvasSize in
                        let blocks = WorkoutProfileGeometry.cachedMake(definition: definition, size: canvasSize, scale: scale, variant: .detail)
                        WorkoutProfileRenderer.draw(blocks, in: &context, size: canvasSize, scale: scale, style: style)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { plotSize = $0 })
                    .offset(x: origin.x, y: origin.y)
                    .allowsHitTesting(false)
                }
            }
        }
        .transaction { $0.animation = nil }
        .frame(height: height)
        // One VoiceOver element (Swift Charts' own children are dropped) with the Audio Graph attached.
        .chartAccessibility(label: "Leistungsprofil \(definition.title)",
                            value: WorkoutProfileSupport.summary(definition: definition, ftp: ftp),
                            descriptor: WorkoutProfileAudioGraph(definition: definition, ftp: ftp))
        .accessibilityIdentifier("profile.detail")
    }
}

// MARK: - Audio graph

/// Audio graph of the detail profile: watts over minutes, one continuous series.
struct WorkoutProfileAudioGraph: AXChartDescriptorRepresentable {
    var definition: WorkoutDefinition
    var ftp: Int

    func makeChartDescriptor() -> AXChartDescriptor { descriptor() }

    /// Refill the existing descriptor (VoiceOver keeps it): without this the Audio Graph stays on the first workout.
    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let fresh = self.descriptor()
        descriptor.title = fresh.title
        descriptor.summary = fresh.summary
        descriptor.xAxis = fresh.xAxis
        descriptor.yAxis = fresh.yAxis
        descriptor.additionalAxes = fresh.additionalAxes
        descriptor.series = fresh.series
    }

    private func descriptor() -> AXChartDescriptor {
        let points = WorkoutProfileSupport.audioPoints(definition: definition, ftp: ftp)
        let totalMinutes = max(Double(definition.totalDuration) / 60, 1)
        let maxWatts = max(points.map(\.watts).max() ?? 1, 1)
        let x = AXNumericDataAxisDescriptor(title: "Zeit in Minuten", range: 0...totalMinutes, gridlinePositions: []) {
            "\(Int($0.rounded())) Minuten"
        }
        let y = AXNumericDataAxisDescriptor(title: "Leistung in Watt", range: 0...maxWatts, gridlinePositions: []) {
            "\(Int($0.rounded())) Watt"
        }
        let series = AXDataSeriesDescriptor(name: definition.title, isContinuous: true,
                                            dataPoints: points.map { AXDataPoint(x: $0.minute, y: $0.watts) })
        return AXChartDescriptor(title: "Leistungsprofil \(definition.title)",
                                 summary: WorkoutProfileSupport.summary(definition: definition, ftp: ftp),
                                 xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}
