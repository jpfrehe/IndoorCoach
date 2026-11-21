import CoreGraphics
import Foundation
import Testing
@testable import IndoorCoachKit

/// Pure helpers of the workout profile views and the segmented bar (concept 21, AP2/AP3).
@Suite("Workout profile support")
struct WorkoutProfileSupportTests {
    typealias S = WorkoutProfileSupport

    static func def(_ segments: [Segment]) -> WorkoutDefinition {
        WorkoutDefinition(title: "T", type: .vo2max, summary: "", segments: segments)
    }

    /// 20 min Z1, 5 × (4 min Z5 / 4 min Z1) = 60 min.
    static let vo2 = def([.steady(20, at: 0.5), .intervals(5, on: 240, at: 1.15, off: 240, at: 0.5)])

    // MARK: Summary

    @Test func profileSummaryMentionsZonesAndIntervals() {
        let text = S.summary(definition: Self.vo2, ftp: 250)
        #expect(text.contains("2 Abschnitte"))
        #expect(text.contains("Spitze 115 % FTP (288 W)"))
        #expect(text.contains("überwiegend Z1 und Z5"))
        #expect(text.contains("5 Intervalle à 4:00"))
    }

    @Test func summaryNamesRealCountOfShortIntervalsAndMergesEqualSets() {
        let d = Self.def([.intervals(10, on: 30, at: 1.2, off: 30, at: 0.5), .steady(5, at: 0.5),
                          .intervals(10, on: 30, at: 1.2, off: 30, at: 0.5)])
        #expect(S.summary(definition: d, ftp: 250).contains("20 Intervalle à 0:30"))
    }

    @Test func summaryWithoutIntervalsHasNoIntervalPart() {
        let d = Self.def([.steady(60, at: 0.65)])
        let text = S.summary(definition: d, ftp: 200)
        #expect(!text.contains("Intervalle"))
        #expect(text.contains("überwiegend Z2"))
    }

    // MARK: Selection

    @Test func segmentIndexAtX() {
        let d = Self.def([.steady(10, at: 0.6), .intervals(3, on: 720, at: 0.92, off: 240, at: 0.5), .steady(5, at: 0.5)])
        let blocks = WorkoutProfileGeometry.make(definition: d, size: CGSize(width: 390, height: 210), scale: 3, variant: .detail)
        #expect(blocks.count == 8)
        for block in blocks {
            #expect(S.stepIndex(atX: block.bounds.midX, blocks: blocks) == block.stepIndex)
        }
        #expect(S.stepIndex(atX: -20, blocks: blocks) == 0)
        #expect(S.stepIndex(atX: 5000, blocks: blocks) == 7)
        // A position inside a 2 pt gap snaps to the nearer neighbour.
        let gapX = (blocks[0].bounds.maxX + blocks[1].bounds.minX) / 2 - 0.4
        #expect(S.stepIndex(atX: gapX, blocks: blocks) == 0)
        #expect(S.stepIndex(atX: 3, blocks: []) == nil)
    }

    @Test func selectionTextNamesStepDurationPowerAndZone() {
        let text = S.selectionText(definition: Self.vo2, ftp: 250, stepIndex: 1)
        #expect(text == "Abschnitt 2 · 4:00 @ 115 % (288 W) · Z5")
        #expect(S.selectionText(definition: Self.vo2, ftp: 250, stepIndex: 99) == nil)
    }

    @Test func selectionTextOfRampShowsBothEndsAndZones() {
        let d = Self.def([.warmup(10, from: 0.5, to: 0.8)])
        #expect(S.selectionText(definition: d, ftp: 200, stepIndex: 0) == "Abschnitt 1 · 10:00 @ 50 → 80 % (100 → 160 W) · Z1–Z3")
    }

    // MARK: Axis and audio graph

    @Test func minuteTicksAreRound() {
        #expect(S.minuteTicks(totalSeconds: 3600) == [0, 15, 30, 45, 60])
        #expect(S.minuteTicks(totalSeconds: 2700) == [0, 15, 30, 45])
        #expect(S.minuteTicks(totalSeconds: 5700) == [0, 30, 60, 90])
        #expect(S.minuteTicks(totalSeconds: 1800) == [0, 10, 20, 30])
        #expect(S.minuteTicks(totalSeconds: 30) == [0])
        #expect(S.minuteTicks(totalSeconds: 0) == [0])
    }

    @Test func audioPointsCoverStartAndEndOfEveryStep() {
        let points = S.audioPoints(definition: Self.vo2, ftp: 200)
        #expect(points.count == 2 * 11)
        #expect(points.first?.minute == 0 && points.first?.watts == 100)
        #expect(points.last?.minute == 60)
        #expect(points.map(\.minute) == points.map(\.minute).sorted())
    }

    // MARK: Segmented bar

    @Test func segmentedBarWidthsAndMinimum() {
        for scale in [CGFloat(2), 3] {
            let width: CGFloat = 300
            let items = SegmentedBarLayout.make(values: [600, 0, 300, 100, 2], width: width, scale: scale)
            #expect(items.map(\.index) == [0, 2, 3, 4])
            // Sum of segments plus 2 pt gaps equals the width, all on the pixel grid.
            let sum = items.reduce(0) { $0 + $1.width } + 2 * CGFloat(items.count - 1)
            #expect(abs(sum - width) < 1e-6)
            for (a, b) in zip(items, items.dropFirst()) { #expect(abs(b.x - (a.x + a.width) - 2) < 1e-6) }
            for item in items {
                #expect(item.width >= 4 - 1e-6)
                #expect(abs(item.width * scale - (item.width * scale).rounded()) < 1e-6)
            }
            // Large segments keep their proportion (600 : 300).
            #expect(abs(items[0].width / items[1].width - 2) < 0.1)
        }
    }

    @Test func segmentedBarNeverDropsToNothing() {
        #expect(SegmentedBarLayout.make(values: [], width: 100, scale: 3).isEmpty)
        #expect(SegmentedBarLayout.make(values: [0, 0], width: 100, scale: 3).isEmpty)
        let one = SegmentedBarLayout.make(values: [5], width: 100, scale: 3)
        #expect(one.count == 1 && abs(one[0].width - 100) < 1e-6)
        // Too narrow for minimum widths: still sums up.
        let tight = SegmentedBarLayout.make(values: [1, 1, 1, 1, 1, 1], width: 20, scale: 2)
        #expect(tight.count == 6)
        #expect(abs(tight.reduce(0) { $0 + $1.width } + 2 * 5 - 20) < 1e-6 || tight.allSatisfy { $0.width > 0 })
    }
}
