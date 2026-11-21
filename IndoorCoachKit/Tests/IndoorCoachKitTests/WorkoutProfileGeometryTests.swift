import CoreGraphics
import Foundation
import Testing
@testable import IndoorCoachKit

/// Pure geometry of the workout profile (concept 21 §4, AP1): one block per step, trapezoid ramps split at zone
/// boundaries, whole-pixel edges and gaps, minimum widths and compact interval sets for the small variants.
@Suite("Workout profile geometry")
struct WorkoutProfileGeometryTests {
    typealias G = WorkoutProfileGeometry
    static let rowSize = CGSize(width: 72, height: 34)
    static let detailSize = CGSize(width: 390, height: 210)

    static func def(_ segments: [Segment]) -> WorkoutDefinition {
        WorkoutDefinition(title: "T", type: .mixed, summary: "", segments: segments)
    }

    static func make(_ d: WorkoutDefinition, size: CGSize = rowSize, scale: CGFloat = 3,
                     variant: G.Variant = .row) -> [ProfileBlock] {
        G.make(definition: d, size: size, scale: scale, variant: variant)
    }

    /// Sweet Spot 3×12: steady warm-up, 3 × (12 on / 4 off), steady cool-down = 1 + 6 + 1 steps.
    static let sweetSpot = def([
        .steady(10, at: 0.6),
        .intervals(3, on: 720, at: 0.92, off: 240, at: 0.5),
        .steady(5, at: 0.5),
    ])

    static func isWholePixel(_ v: CGFloat, _ scale: CGFloat) -> Bool {
        let p = v * scale
        return abs(p - p.rounded()) < 1e-6
    }

    // MARK: Blocks per step

    @Test func oneBlockPerSteadyStep() {
        let blocks = Self.make(Self.sweetSpot)
        #expect(blocks.count == 8)
        #expect(blocks.map(\.stepIndex) == Array(0..<8))
        #expect(blocks.allSatisfy { $0.role == .step && $0.partCount == 1 })
        #expect(blocks.map(\.segmentIndex) == [0, 1, 1, 1, 1, 1, 1, 2])
        #expect(blocks[1].zone == .z4 && blocks[2].zone == .z1)
    }

    @Test func blocksAreOrderedAndDoNotOverlap() {
        for scale in [CGFloat(2), 3] {
            let blocks = Self.make(Self.sweetSpot, scale: scale)
            for (a, b) in zip(blocks, blocks.dropFirst()) {
                #expect(b.bounds.minX >= a.bounds.maxX - 1e-9, "scale \(scale)")
            }
        }
    }

    @Test func gapsAreWholePixelsAndAtLeastOne() {
        for scale in [CGFloat(2), 3] {
            let blocks = Self.make(Self.sweetSpot, scale: scale)
            for (a, b) in zip(blocks, blocks.dropFirst()) {
                let gap = b.bounds.minX - a.bounds.maxX
                #expect(gap * scale >= 1 - 1e-6, "gap \(gap) at \(scale)x")
                #expect(Self.isWholePixel(gap, scale))
                #expect(abs(gap * scale - (1 * scale).rounded()) < 1e-6, "row gap is 1 pt = \((1 * scale).rounded()) px")
            }
        }
    }

    @Test func firstAndLastTouchEdges() {
        for variant in [G.Variant.row, .card, .preview] {
            let blocks = Self.make(Self.sweetSpot, variant: variant)
            #expect(blocks.first?.bounds.minX == 0)
            #expect(abs((blocks.last?.bounds.maxX ?? 0) - Self.rowSize.width) < 1e-9)
        }
        let detail = Self.make(Self.sweetSpot, size: Self.detailSize, variant: .detail)
        #expect(detail.first?.bounds.minX == 0)
        #expect(abs((detail.last?.bounds.maxX ?? 0) - Self.detailSize.width) < 1e-9)
    }

    @Test func allEdgesSnapToPixelGrid() {
        let rich = Self.def([.warmup(8, from: 0.45, to: 0.75), .steady(5, at: 0.9),
                             .intervals(5, on: 240, at: 1.15, off: 180, at: 0.5),
                             .ramp(6, from: 0.5, to: 1.3), .cooldown(7, from: 0.7, to: 0.4)])
        for (size, variant) in [(Self.rowSize, G.Variant.row), (Self.detailSize, .detail), (CGSize(width: 341.3, height: 56.7), .card)] {
            for scale in [CGFloat(2), 3] {
                for block in Self.make(rich, size: size, scale: scale, variant: variant) {
                    for p in block.polygon {
                        #expect(Self.isWholePixel(p.x, scale) && Self.isWholePixel(p.y, scale), "\(p) at \(scale)x \(variant)")
                    }
                }
            }
        }
    }

    // MARK: Ramps

    @Test func rampIsTrapezoidNotStairs() {
        let blocks = Self.make(Self.def([.warmup(10, from: 0.5, to: 0.7)]))
        #expect(blocks.count == 2)
        #expect(blocks.allSatisfy { $0.stepIndex == 0 && $0.partCount == 2 })
        #expect(blocks.map(\.part) == [0, 1])
        let h = Self.rowSize.height * 3
        func top(_ p: Double) -> CGFloat { (h - (p / 1.6 * h).rounded()) / 3 }
        #expect(abs(blocks[0].polygon[0].y - top(0.5)) < 1e-6, "left height = 50 %")
        #expect(abs(blocks[1].polygon[1].y - top(0.7)) < 1e-6, "right height = 70 %")
        // Straight top edge: the split vertex lies on the line between both ends (±1 px snapping).
        let split = blocks[0].polygon[1]
        let t = (split.x - blocks[0].polygon[0].x) / (blocks[1].polygon[1].x - blocks[0].polygon[0].x)
        let expectedY = blocks[0].polygon[0].y + t * (blocks[1].polygon[1].y - blocks[0].polygon[0].y)
        #expect(abs(split.y - expectedY) <= 1.0 / 3 + 1e-6)
    }

    @Test func rampSplitsExactlyAtZoneBoundary() {
        let blocks = Self.make(Self.def([.warmup(10, from: 0.5, to: 0.7)]))
        let splitX = blocks[0].bounds.maxX * 3
        #expect(abs(splitX - 216 * 0.3) <= 1.0, "split at \(splitX) px, expected 64.8")
        #expect(blocks[0].zone == .z1 && blocks[1].zone == .z2)
        let three = Self.make(Self.def([.ramp(10, from: 0.45, to: 0.85)]), size: Self.detailSize, variant: .detail)
        #expect(three.map(\.zone) == [.z1, .z2, .z3])
        // t = (0.56 - 0.45) / 0.4 and (0.76 - 0.45) / 0.4 of the block width.
        let w = three.last!.bounds.maxX
        #expect(abs(three[0].bounds.maxX / w - 0.275) < 1.5 / (390 * 3))
        #expect(abs(three[1].bounds.maxX / w - 0.775) < 1.5 / (390 * 3))
        let all = Self.make(Self.def([.ramp(10, from: 0.4, to: 1.3)]), size: Self.detailSize, variant: .detail)
        #expect(all.map(\.zone) == [.z1, .z2, .z3, .z4, .z5, .z6])
    }

    @Test func rampPartsShareEdgeWithoutGap() {
        let blocks = Self.make(Self.def([.ramp(10, from: 0.4, to: 1.3)]), size: Self.detailSize, variant: .detail)
        for (a, b) in zip(blocks, blocks.dropFirst()) {
            #expect(a.polygon[1] == b.polygon[0], "top vertex shared")
            #expect(a.polygon[2] == b.polygon[3], "bottom vertex shared")
        }
    }

    @Test func cooldownDescends() {
        let blocks = Self.make(Self.def([.cooldown(10, from: 0.7, to: 0.4)]))
        #expect(blocks.map(\.zone) == [.z2, .z1])
        let first = blocks.first!, last = blocks.last!
        #expect(first.polygon[0].y < last.polygon[1].y, "left edge is taller than right edge")
        #expect(blocks[0].polygon[1].y > blocks[0].polygon[0].y)
    }

    @Test func outerCornersOnlyRounded() {
        let ramp = Self.make(Self.def([.ramp(10, from: 0.45, to: 0.85)]))
        #expect(ramp.count == 3)
        #expect(ramp[0].roundedCorners == [.topLeading, .bottomLeading])
        #expect(ramp[1].roundedCorners.isEmpty)
        #expect(ramp[2].roundedCorners == [.topTrailing, .bottomTrailing])
        let steady = Self.make(Self.def([.steady(10, at: 0.8)]))
        #expect(steady[0].roundedCorners == [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing])
        let detail = Self.make(Self.def([.steady(10, at: 0.8)]), size: Self.detailSize, variant: .detail)
        #expect(detail[0].roundedCorners == [.topLeading, .topTrailing], "detail blocks sit on the axis")
        let detailRamp = Self.make(Self.def([.ramp(10, from: 0.45, to: 0.85)]), size: Self.detailSize, variant: .detail)
        #expect(detailRamp[0].roundedCorners == [.topLeading])
        #expect(detailRamp[2].roundedCorners == [.topTrailing])
    }

    // MARK: Heights

    @Test func heightsFollowFixedListDomain() {
        let full = Self.make(Self.def([.steady(30, at: 1.0)]))[0]
        #expect(abs(full.bounds.height - 21.25) <= 1.0 / 3 + 1e-9, "100 % of 0-160 % at 34 pt")
        #expect(full.bounds.maxY == 34)
        let half = Self.make(Self.def([.steady(30, at: 0.5)]))[0]
        #expect(abs(half.bounds.height / full.bounds.height - 0.5) < 0.06)
        // Fixed scale: a recovery ride looks flat next to a VO2max ride, independent of the workout's own peak.
        #expect(Self.make(Self.def([.steady(30, at: 0.5), .steady(5, at: 0.55)]))[0].bounds.height == half.bounds.height)
        #expect(G.domainTop(for: Self.def([.steady(30, at: 0.5)]), variant: .row) == 1.6)
    }

    @Test func clampsAboveDomainAndFlagsClipped() {
        let sprint = Self.make(Self.def([.steady(1, at: 2.0)]))[0]
        #expect(sprint.bounds.height == 34 && sprint.clipped)
        #expect(sprint.zone == .z7)
        #expect(!Self.make(Self.def([.steady(1, at: 1.5)]))[0].clipped)
    }

    @Test func minimumHeight() {
        let low = Self.make(Self.def([.steady(10, at: 0.03)]))[0]
        #expect(low.bounds.height >= 2 - 1e-9)
        let card = Self.make(Self.def([.steady(10, at: 0.03)]), size: CGSize(width: 300, height: 64), variant: .card)[0]
        #expect(card.bounds.height >= 3 - 1e-9)
    }

    @Test func detailDomainRoundsUp() {
        func top(_ p: Double) -> Double { G.domainTop(for: Self.def([.steady(10, at: p)]), variant: .detail) }
        #expect(top(1.0) == 1.3)
        #expect(top(1.25) == 1.4)
        #expect(abs(top(1.5) - 1.6) < 1e-9)
        let blocks = Self.make(Self.def([.steady(10, at: 1.0)]), size: Self.detailSize, variant: .detail)
        #expect(abs(blocks[0].bounds.height - 210 / 1.3) <= 1.0 / 3 + 1e-9)
        #expect(!blocks[0].clipped)
    }

    @Test func freeRideIs55Percent() {
        let block = Self.make(Self.def([.freeRide(30)]))[0]
        #expect(abs(block.bounds.height - 0.55 / 1.6 * 34) <= 1.0 / 3 + 1e-9)
        #expect(block.zone == .z1)
    }

    // MARK: Short intervals

    static let shortSet = def([
        .steady(10, at: 0.55), .intervals(20, on: 30, at: 1.3, off: 30, at: 0.5), .steady(30, at: 0.5),
    ])

    @Test func shortIntervalsKeepMinimumStakeWidth() {
        let blocks = Self.make(Self.shortSet)
        let stakes = blocks.filter { $0.zone == .z6 }
        #expect(stakes.count == 20)
        for stake in stakes { #expect(stake.bounds.width >= 1.5 - 1e-9, "stake \(stake.bounds.width) pt") }
        #expect(stakes.allSatisfy { $0.role == .stake })
    }

    static let setsOf30 = def([
        .steady(10, at: 0.5),
        .intervals(10, on: 30, at: 1.3, off: 30, at: 0.45), .steady(5, at: 0.5),
        .intervals(10, on: 30, at: 1.3, off: 30, at: 0.45), .steady(5, at: 0.5),
        .intervals(10, on: 30, at: 1.3, off: 30, at: 0.45), .steady(10, at: 0.5),
    ])

    @Test func compactModeKeepsIntervalCount() {
        let blocks = Self.make(Self.setsOf30)
        let stakes = blocks.filter { $0.role == .stake }
        #expect(stakes.count == 30)
        #expect(blocks.filter { $0.role == .offFill }.count == 3, "one continuous off area per set")
        #expect(!blocks.contains { $0.role == .hatched })
        for (a, b) in zip(stakes, stakes.dropFirst()) {
            #expect(b.bounds.minX >= a.bounds.maxX + 1.0 / 3 - 1e-6, "at least a 1 px ring between stakes")
        }
        // Stakes stand on the off area of their set.
        for off in blocks.filter({ $0.role == .offFill }) {
            #expect(stakes.filter { $0.bounds.minX >= off.bounds.minX - 1e-9 && $0.bounds.maxX <= off.bounds.maxX + 1e-9 }.count == 10)
            #expect(off.bounds.height < stakes[0].bounds.height)
        }
        #expect(abs((blocks.last?.bounds.maxX ?? 0) - 72) < 1e-9)
    }

    @Test func fewShortIntervalsStayIndividualBlocks() {
        let blocks = Self.make(Self.def([.steady(20, at: 0.6), .intervals(5, on: 240, at: 1.15, off: 240, at: 0.5), .steady(10, at: 0.5)]),
                               size: CGSize(width: 300, height: 56), variant: .card)
        #expect(blocks.count == 1 + 10 + 1)
        #expect(blocks.allSatisfy { $0.role == .step })
    }

    @Test func hatchFallbackOnlyBeyondPixelLimit() {
        let many = Self.def([.intervals(100, on: 30, at: 1.3, off: 30, at: 0.5)])
        let fits = Self.make(many)
        #expect(fits.filter { $0.role == .stake }.count == 100)
        #expect(!fits.contains { $0.role == .hatched })
        for stake in fits where stake.role == .stake { #expect(stake.bounds.width * 3 >= 1 - 1e-6) }

        let tooMany = Self.make(Self.def([.intervals(150, on: 30, at: 1.3, off: 30, at: 0.5)]))
        #expect(tooMany.filter { $0.role == .hatched }.count == 1)
        #expect(!tooMany.contains { $0.role == .stake })
        #expect(tooMany[0].zone == .z6)
    }

    @Test func deficitIsTakenFromLongBlocks() {
        let blocks = Self.make(Self.def([.steady(0.1, at: 1.0), .steady(60, at: 0.6)]))
        #expect(blocks.count == 2)
        #expect(blocks[0].bounds.width >= 2 - 1e-9, "6 s block keeps its minimum width")
        #expect(abs(blocks[1].bounds.maxX - 72) < 1e-9)
    }

    // MARK: Width conservation and time

    @Test func widthIsConserved() {
        let defs = [Self.sweetSpot, Self.shortSet, Self.setsOf30,
                    Self.def([.warmup(8, from: 0.45, to: 0.75), .steady(5, at: 0.9), .cooldown(7, from: 0.7, to: 0.4)])]
        for d in defs {
            for (size, variant) in [(Self.rowSize, G.Variant.row), (CGSize(width: 340, height: 56), .card), (Self.detailSize, .detail)] {
                for scale in [CGFloat(2), 3] {
                    let blocks = Self.make(d, size: size, scale: scale, variant: variant)
                    #expect(blocks.first?.bounds.minX == 0)
                    #expect(abs((blocks.last?.bounds.maxX ?? 0) - size.width) <= 1 / scale + 1e-9, "\(variant) \(scale)x")
                    // The union of blocks plus gaps tiles the full width.
                    let covered = blocks.reduce(0) { $0 + $1.bounds.width }
                    let gaps = zip(blocks, blocks.dropFirst()).reduce(0) { $0 + max(0, $1.1.bounds.minX - $1.0.bounds.maxX) }
                    let overlap = zip(blocks, blocks.dropFirst()).reduce(0) { $0 + max(0, $1.0.bounds.maxX - $1.1.bounds.minX) }
                    #expect(abs(covered + gaps - overlap - size.width) <= 1 / scale + 1e-9)
                }
            }
        }
    }

    @Test func detailVariantDoesNotWarpTime() {
        let d = Self.shortSet
        let blocks = Self.make(d, size: Self.detailSize, variant: .detail)
        #expect(blocks.count == d.steps.count)
        #expect(blocks.allSatisfy { $0.role == .step })
        let total = Double(d.totalDuration)
        let gapPx = (2.0 * 3).rounded()
        let available = 390.0 * 3 - gapPx * Double(blocks.count - 1)
        for (block, step) in zip(blocks, d.steps) {
            let expected = Double(step.duration) / total * available
            #expect(abs(Double(block.bounds.width) * 3 - expected) <= 1.0 + 1e-6, "step \(step.start): \(block.bounds.width * 3) vs \(expected)")
        }
    }

    @Test func zoneAreaMatchesTimeInZones() {
        let d = Self.def([.steady(20, at: 0.5), .steady(25, at: 0.8), .steady(10, at: 0.95), .steady(5, at: 1.1)])
        let blocks = Self.make(d, size: Self.detailSize, variant: .detail)
        let total = Double(d.totalDuration)
        let gapPx = 6.0, available = 390.0 * 3 - gapPx * Double(blocks.count - 1)
        for (zone, seconds) in d.timeInZones() {
            let zoneBlocks = blocks.filter { $0.zone == zone }
            let widthPx = zoneBlocks.reduce(0.0) { $0 + Double($1.bounds.width) * 3 }
            let impliedSeconds = widthPx / available * total
            let tolerance = Double(zoneBlocks.count) * total / available
            #expect(abs(impliedSeconds - Double(seconds)) <= tolerance + 1e-6, "\(zone)")
        }
    }

    @Test func cornerRadiusClamped() {
        let blocks = Self.make(Self.setsOf30)
        for block in blocks {
            #expect(block.cornerRadius <= block.bounds.width / 2 + 1e-9)
            #expect(block.cornerRadius <= block.bounds.height / 2 + 1e-9)
            #expect(block.cornerRadius <= 1.5 + 1e-9)
        }
        let big = Self.make(Self.def([.steady(30, at: 1.0)]))[0]
        #expect(big.cornerRadius == 1.5)
        let preview = Self.make(Self.def([.steady(30, at: 1.0)]), size: CGSize(width: 300, height: 110), variant: .preview)[0]
        #expect(preview.cornerRadius == 4)
    }

    @Test func emptyAndZeroDurationProduceNoBlocks() {
        #expect(Self.make(Self.def([])).isEmpty)
        #expect(Self.make(Self.def([.steady(0, at: 0.8), .freeRide(0)])).isEmpty)
        #expect(Self.make(Self.sweetSpot, size: .zero).isEmpty)
        #expect(Self.make(Self.sweetSpot, scale: 0).isEmpty)
        #expect(Self.make(Self.def([Segment(kind: .intervals, duration: 0, repeatCount: 0, onDuration: 30, offDuration: 30)])).isEmpty)
        // Zero-length steps are skipped but keep the numbering of `definition.steps`.
        let blocks = Self.make(Self.def([.steady(0, at: 0.8), .steady(10, at: 0.8)]))
        #expect(blocks.map(\.stepIndex) == [1])
    }

    @Test func geometryIsFast() {
        let d = Self.def([.steady(10, at: 0.55), .intervals(99, on: 30, at: 1.3, off: 30, at: 0.5), .cooldown(5, from: 0.7, to: 0.4)])
        #expect(d.steps.count == 200)
        let clock = ContinuousClock()
        var best = Duration.seconds(1)
        for _ in 0..<20 {
            let t = clock.measure { _ = Self.make(d) }
            best = min(best, t)
        }
        #expect(best < .milliseconds(2), "best of 20: \(best)")
        var bestDetail = Duration.seconds(1)
        for _ in 0..<20 {
            bestDetail = min(bestDetail, clock.measure { _ = Self.make(d, size: Self.detailSize, variant: .detail) })
        }
        #expect(bestDetail < .milliseconds(2), "detail best of 20: \(bestDetail)")
    }
}
