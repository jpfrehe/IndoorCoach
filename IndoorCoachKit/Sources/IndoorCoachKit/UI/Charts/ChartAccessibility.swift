import Accessibility
import SwiftUI

/// VoiceOver and Audio Graphs for charts (concept 21 §3.7). Every chart is exactly one element: label = title,
/// value = one sentence (`ChartMath.seriesSentence`). P1 analyses additionally attach an `AXChartDescriptor`.
struct ChartDescriptor: AXChartDescriptorRepresentable {
    struct Series {
        var name: String
        var points: [(x: Double, y: Double)]
        var isContinuous = true
    }

    var title: String
    var summary: String
    var xTitle: String
    var yTitle: String
    var series: [Series]
    var xLabel: (Double) -> String = { ChartMath.format($0, decimals: 0) }
    var yLabel: (Double) -> String = { ChartMath.format($0, decimals: 0) }

    func makeChartDescriptor() -> AXChartDescriptor { descriptor() }

    /// Refill the existing descriptor: SwiftUI keeps it across updates, so an empty body leaves a stale Audio Graph.
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
        let all = series.flatMap(\.points)
        let xs = ChartMath.domain(values: all.map(\.x), includeZero: false)
        let ys = ChartMath.domain(values: all.map(\.y), includeZero: false)
        let xLabel = xLabel, yLabel = yLabel
        let xAxis = AXNumericDataAxisDescriptor(title: xTitle, range: xs.lowerBound...xs.upperBound,
                                                gridlinePositions: []) { xLabel($0) }
        let yAxis = AXNumericDataAxisDescriptor(title: yTitle, range: ys.lowerBound...ys.upperBound,
                                                gridlinePositions: []) { yLabel($0) }
        let data = series.map { s in
            AXDataSeriesDescriptor(name: s.name, isContinuous: s.isContinuous,
                                   dataPoints: s.points.map { AXDataPoint(x: $0.x, y: $0.y) })
        }
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: data)
    }
}

enum ChartAccessibility {
    /// Descriptor for dated series: x = seconds since 1970, announced as a German date.
    static func timeSeries(title: String, summary: String, yTitle: String,
                           series: [(name: String, points: [(date: Date, value: Double)])],
                           yLabel: @escaping (Double) -> String = { ChartMath.format($0, decimals: 0) }) -> ChartDescriptor {
        ChartDescriptor(
            title: title, summary: summary, xTitle: "Datum", yTitle: yTitle,
            series: series.map { s in
                .init(name: s.name, points: s.points.map { ($0.date.timeIntervalSince1970, $0.value) })
            },
            xLabel: { Date(timeIntervalSince1970: $0).formatted(.dateTime.day().month(.abbreviated).locale(Locale.de)) },
            yLabel: yLabel)
    }
}

extension View {
    /// Makes the whole chart one VoiceOver element and removes Swift Charts' own child nodes.
    func chartAccessibility(label: String, value: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }

    /// Adds an Audio Graph on top of `chartAccessibility`.
    func chartAccessibility<D: AXChartDescriptorRepresentable>(label: String, value: String, descriptor: D) -> some View {
        chartAccessibility(label: label, value: value).accessibilityChartDescriptor(descriptor)
    }
}
