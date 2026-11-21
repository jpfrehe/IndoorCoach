import Accessibility
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import IndoorCoachKit

/// Views of the workout profile (concept 21, AP2/AP3): renderer path, audio graph, gallery samples.
@MainActor
@Suite("Workout profile views")
struct WorkoutProfileViewTests {
    #if DEBUG
    @Test func gallerySamplesCoverTheTypicalCases() {
        let samples = ChartGallerySamples.all
        #expect(Set(samples.map(\.id)).count == samples.count)
        #expect(samples.count == 8)
        func steps(_ id: String) -> [PowerStep] { samples.first { $0.id == id }!.definition.steps }
        #expect(steps("vo2max").filter { $0.startPower > 1.1 }.count == 5)
        #expect(steps("dreissig").filter { $0.startPower > 1.2 }.count == 20)
        #expect(steps("tabata").contains { $0.startPower > 1.6 })       // above the fixed 160 % domain: clipped
        #expect(steps("rampe").contains { $0.startPower != $0.endPower })
        #expect(samples.first { $0.id == "ausgelassen" }?.skipped == true)
        for sample in samples { #expect(sample.definition.totalDuration > 0, "\(sample.id)") }
    }

    @Test func everyGallerySampleProducesBlocksInEveryVariant() {
        let variants: [(WorkoutProfileGeometry.Variant, CGSize)] = [
            (.row, CGSize(width: 72, height: 34)), (.card, CGSize(width: 340, height: 64)),
            (.preview, CGSize(width: 340, height: 110)), (.accessibilityRow, CGSize(width: 340, height: 28)),
            (.detail, CGSize(width: 340, height: 180)),
        ]
        for sample in ChartGallerySamples.all {
            for (variant, size) in variants {
                #expect(!WorkoutProfileGeometry.make(definition: sample.definition, size: size, scale: 3, variant: variant).isEmpty,
                        "\(sample.id) \(variant)")
            }
        }
    }
    #endif

    @Test func rendererPathStaysInsideTheBlockBounds() {
        let d = WorkoutDefinition(title: "T", type: .mixed, summary: "",
                                  segments: [.warmup(10, from: 0.4, to: 1.0), .steady(5, at: 0.9)])
        let blocks = WorkoutProfileGeometry.make(definition: d, size: CGSize(width: 340, height: 64), scale: 3, variant: .card)
        #expect(blocks.count >= 3)   // the ramp is split at zone boundaries
        for block in blocks {
            let bounds = WorkoutProfileRenderer.path(for: block).boundingRect
            let expected = block.bounds.insetBy(dx: -0.01, dy: -0.01)
            #expect(expected.contains(bounds), "part \(block.part)")
            #expect(bounds.width > 0 && bounds.height > 0)
        }
    }

    @Test func squareBlocksWithoutRoundedCornersAreSimplePolygons() {
        var block = WorkoutProfileGeometry.make(
            definition: WorkoutDefinition(title: "T", type: .mixed, summary: "", segments: [.steady(10, at: 0.7)]),
            size: CGSize(width: 100, height: 40), scale: 2, variant: .detail)[0]
        block.roundedCorners = []
        #expect(WorkoutProfileRenderer.path(for: block).boundingRect == block.bounds)
    }

    @Test func audioGraphDescribesWattsOverMinutes() {
        let d = WorkoutDefinition(title: "VO₂max 5×4", type: .vo2max, summary: "",
                                  segments: [.steady(20, at: 0.5), .intervals(5, on: 240, at: 1.15, off: 240, at: 0.5)])
        let descriptor = WorkoutProfileAudioGraph(definition: d, ftp: 200).makeChartDescriptor()
        #expect(descriptor.title?.contains("VO₂max 5×4") == true)
        #expect(descriptor.series.count == 1)
        #expect(descriptor.series[0].dataPoints.count == 22)
        #expect(descriptor.summary?.contains("5 Intervalle à 4:00") == true)
    }

    @Test func miniAccessibilitySummaryIsTheSupportSentence() {
        let d = WorkoutDefinition(title: "T", type: .mixed, summary: "", segments: [.steady(10, at: 1.0)])
        let view = WorkoutProfileView(definition: d, ftp: 250)
        #expect(view.accessibilitySummary == WorkoutProfileSupport.summary(definition: d, ftp: 250))
        #expect(view == WorkoutProfileView(definition: d, ftp: 250))
        #expect(view != WorkoutProfileView(definition: d, ftp: 250, skipped: true))
    }
}
