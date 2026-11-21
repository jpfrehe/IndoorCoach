import CoreGraphics
import Foundation

/// One drawable piece of the workout profile. Pure data (no SwiftUI) so it can be unit-tested and drawn by any renderer.
/// Coordinates are points, origin top-left; all vertices lie on the pixel grid of the `scale` they were made for.
public struct ProfileBlock: Equatable, Sendable {
    public enum Role: Sendable {
        /// One workout step (steady, ramp part, interval on or off in individual mode).
        case step
        /// One "on" interval inside a compact set (narrow bar standing on the set's `offFill`).
        case stake
        /// Continuous off-area under the stakes of a compact set.
        case offFill
        /// A whole interval set too dense even for 1 px stakes: draw one hatched block (VoiceOver names the real count).
        case hatched
    }

    public struct Corners: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let topLeading = Corners(rawValue: 1)
        public static let topTrailing = Corners(rawValue: 2)
        public static let bottomTrailing = Corners(rawValue: 4)
        public static let bottomLeading = Corners(rawValue: 8)
    }

    public var role: Role
    /// Index into `WorkoutDefinition.steps`.
    public var stepIndex: Int
    /// Index into `WorkoutDefinition.segments`.
    public var segmentIndex: Int
    /// Position of this piece within a ramp split at zone boundaries (0 for everything else).
    public var part: Int
    public var partCount: Int
    public var zone: PowerZone
    /// Top-leading, top-trailing, bottom-trailing, bottom-leading. Ramps have a slanted top edge.
    public var polygon: [CGPoint]
    /// Already clamped to half the block's width and height.
    public var cornerRadius: CGFloat
    public var roundedCorners: Corners
    /// True when the power exceeds the (fixed) y domain and the block was cut at full height.
    public var clipped: Bool

    public var bounds: CGRect {
        guard let first = polygon.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in polygon {
            minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Geometry of the workout profile (concept 21 §4). One block per step; ramps are trapezoids split exactly at power-zone
/// boundaries; gaps and edges are whole pixels. The small variants squeeze very short intervals (minimum widths, compact
/// sets) without ever losing the interval count; the detail variant keeps time proportional.
public enum WorkoutProfileGeometry {
    public enum Variant: Hashable, Sendable {
        /// `WorkoutRow` 72 × 34 pt.
        case row
        /// Today "next workout" and plan proposal (56–64 pt high).
        case card
        /// Adjust preview (110 pt high).
        case preview
        /// Workout detail (210 pt), real time axis.
        case detail
        /// `WorkoutRow` at accessibility sizes (28 pt high, full width).
        case accessibilityRow
    }

    struct Metrics {
        var gap: CGFloat, radius: CGFloat, minBlock: CGFloat, minStake: CGFloat, minHeight: CGFloat
        var fixedDomain: Bool, roundsBottom: Bool, warpsTime: Bool
    }

    static func metrics(_ variant: Variant) -> Metrics {
        switch variant {
        case .row, .accessibilityRow:
            Metrics(gap: 1, radius: 1.5, minBlock: 2, minStake: 1.5, minHeight: 2, fixedDomain: true, roundsBottom: true, warpsTime: true)
        case .card:
            Metrics(gap: 2, radius: 3, minBlock: 3, minStake: 2, minHeight: 3, fixedDomain: true, roundsBottom: true, warpsTime: true)
        case .preview:
            Metrics(gap: 2, radius: 4, minBlock: 3, minStake: 2, minHeight: 3, fixedDomain: true, roundsBottom: true, warpsTime: true)
        case .detail:
            Metrics(gap: 2, radius: 4, minBlock: 0, minStake: 0, minHeight: 2, fixedDomain: false, roundsBottom: false, warpsTime: false)
        }
    }

    /// Most interval repeats the profile will unroll; anything beyond is corrupt data and is neither drawn nor unrolled.
    public static let maxRepeats = 500

    /// Power fraction above which the detail domain stops growing (a 1000 % FTP peak is data noise).
    static let maxDomainTop = 10.0

    /// True when a segment asks for more repeats than `maxRepeats` (guards `WorkoutDefinition.steps`' unrolling).
    public static func exceedsRepeatLimit(_ definition: WorkoutDefinition) -> Bool {
        definition.segments.contains { ($0.repeatCount ?? 0) > maxRepeats }
    }

    static func finite(_ power: Double) -> Double { power.isFinite ? power : 0 }

    /// Top of the y axis as a fraction of FTP: fixed 1.6 for the minis, `max(1.3, peak + 0.1)` rounded up to 0.1 for the detail.
    /// Non-finite powers are ignored. The chart axis uses this same value (×100), so axis and blocks share one domain.
    public static func domainTop(for definition: WorkoutDefinition, variant: Variant) -> Double {
        if metrics(variant).fixedDomain { return 1.6 }
        guard !exceedsRepeatLimit(definition) else { return 1.3 }
        var peak = 0.0
        for step in definition.steps { peak = max(peak, finite(step.startPower), finite(step.endPower)) }
        return (max(1.3, min(peak + 0.1, maxDomainTop)) * 10 - 1e-9).rounded(.up) / 10
    }

    // MARK: Cache

    private struct CacheKey: Hashable {
        var definition: WorkoutDefinition
        var width: CGFloat, height: CGFloat, scale: CGFloat
        var variant: Variant
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [CacheKey: [ProfileBlock]] = [:]

        func blocks(for key: CacheKey, make: () -> [ProfileBlock]) -> [ProfileBlock] {
            lock.lock()
            if let hit = entries[key] { lock.unlock(); return hit }
            lock.unlock()
            let blocks = make()
            lock.lock()
            // Rows scroll through a few dozen distinct workouts; start over rather than grow without bound.
            if entries.count >= 128 { entries.removeAll(keepingCapacity: true) }
            entries[key] = blocks
            lock.unlock()
            return blocks
        }
    }

    private static let cache = Cache()

    /// `make` through a small cache (key: definition, size, scale, variant). Lists and redraws ask for the same
    /// geometry on every frame; the result is a pure function of the key.
    public static func cachedMake(definition: WorkoutDefinition, size: CGSize, scale: CGFloat, variant: Variant) -> [ProfileBlock] {
        cache.blocks(for: CacheKey(definition: definition, width: size.width, height: size.height, scale: scale, variant: variant)) {
            make(definition: definition, size: size, scale: scale, variant: variant)
        }
    }

    // MARK: Layout

    private enum Role { case plain, on, off }
    private struct SetInfo {
        var segment: Int, firstStep: Int, count: Int, on: Int, off: Int, onPower: Double, offPower: Double
        var stepsPerRep: Int { off > 0 ? 2 : 1 }
    }
    private enum Unit {
        case single(step: Int, segment: Int, role: Role)
        case set(Int)
    }
    private enum SetMode { case normal, compact, hatched }
    private enum CellKind {
        case step(step: Int, segment: Int)
        case compact(Int)
        case hatched(Int)
    }
    private struct Cell {
        var kind: CellKind
        var duration: Double
        var minWidth: Int
    }

    public static func make(definition: WorkoutDefinition, size: CGSize, scale: CGFloat, variant: Variant) -> [ProfileBlock] {
        guard size.width > 0, size.height > 0, scale > 0 else { return [] }
        guard !exceedsRepeatLimit(definition) else { return [] }
        let m = metrics(variant)
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0 else { return [] }
        let steps = definition.steps
        guard steps.contains(where: { $0.duration > 0 }) else { return [] }

        func pixels(_ pt: CGFloat) -> Int { max(1, Int((pt * scale - 1e-9).rounded(.up))) }
        let gapPx = max(1, Int((m.gap * scale).rounded()))
        let minBlock = m.warpsTime ? pixels(m.minBlock) : 1
        let minStake = m.warpsTime ? pixels(m.minStake) : 1
        let domain = domainTop(for: definition, variant: variant)
        let minHeight = pixels(m.minHeight)

        // Units in drawing order; intervals with ≥ 2 repeats may be compacted in the small variants.
        var units: [Unit] = []
        var sets: [SetInfo] = []
        var index = 0
        for (segmentIndex, segment) in definition.segments.enumerated() {
            switch segment.kind {
            case .intervals:
                let n = max(segment.repeatCount ?? 1, 0), on = segment.onDuration ?? 60, off = segment.offDuration ?? 60
                let info = SetInfo(segment: segmentIndex, firstStep: index, count: n, on: on, off: off,
                                   onPower: finite(segment.onPower ?? 1.0), offPower: finite(segment.offPower ?? 0.5))
                if m.warpsTime, n >= 2, on > 0, off >= 0 {
                    units.append(.set(sets.count))
                    sets.append(info)
                } else {
                    for rep in 0..<n {
                        units.append(.single(step: index + rep * info.stepsPerRep, segment: segmentIndex, role: .on))
                        if off > 0 { units.append(.single(step: index + rep * info.stepsPerRep + 1, segment: segmentIndex, role: .off)) }
                    }
                }
                index += n * info.stepsPerRep
            default:
                units.append(.single(step: index, segment: segmentIndex, role: .plain))
                index += 1
            }
        }
        guard index == steps.count else { return [] }

        func cells(_ modes: [SetMode], floorStake: Bool) -> [Cell] {
            var result: [Cell] = []
            result.reserveCapacity(units.count)
            for unit in units {
                switch unit {
                case let .single(step, segment, role):
                    let d = steps[step].duration
                    if d > 0 {
                        let minW = role == .plain ? minBlock : (role == .on ? minStake : 1)
                        result.append(Cell(kind: .step(step: step, segment: segment), duration: Double(d), minWidth: minW))
                    }
                case let .set(i):
                    let s = sets[i]
                    switch modes[i] {
                    case .normal:
                        for rep in 0..<s.count {
                            let on = s.firstStep + rep * s.stepsPerRep
                            result.append(Cell(kind: .step(step: on, segment: s.segment), duration: Double(s.on), minWidth: minStake))
                            if s.off > 0 {
                                result.append(Cell(kind: .step(step: on + 1, segment: s.segment), duration: Double(s.off), minWidth: 1))
                            }
                        }
                    case .compact:
                        let sMin = floorStake ? 1 : minStake
                        result.append(Cell(kind: .compact(i), duration: Double(s.count * (s.on + s.off)),
                                           minWidth: s.count * sMin + (s.count - 1)))
                    case .hatched:
                        result.append(Cell(kind: .hatched(i), duration: Double(s.count * (s.on + s.off)), minWidth: minBlock))
                    }
                }
            }
            return result
        }

        func allocate(_ cells: [Cell], gap: Int, ignoreMinimum: Bool = false) -> [Int]? {
            let n = cells.count
            guard n > 0 else { return nil }
            let available = width - gap * (n - 1)
            guard available > 0 else { return nil }
            let total = cells.reduce(0.0) { $0 + $1.duration }
            guard total > 0 else { return nil }
            var wanted = [Double](repeating: 0, count: n)
            var deficit = 0.0, capacity = 0.0
            for i in 0..<n {
                let nat = cells[i].duration / total * Double(available)
                let minW = ignoreMinimum ? 0.0 : Double(cells[i].minWidth)
                wanted[i] = nat
                if nat < minW { deficit += minW - nat; wanted[i] = minW } else if nat > 4 * minW { capacity += nat - 2 * minW }
            }
            if deficit > 1e-9 {
                guard deficit <= capacity + 1e-9 else { return nil }
                for i in 0..<n {
                    let minW = ignoreMinimum ? 0.0 : Double(cells[i].minWidth)
                    let nat = cells[i].duration / total * Double(available)
                    if nat > 4 * minW { wanted[i] = nat - deficit * (nat - 2 * minW) / capacity }
                }
            }
            var result = wanted.map { Int(($0 + 1e-7).rounded(.down)) }
            var rest = available - result.reduce(0, +)
            if rest > 0 {
                let order = (0..<n).sorted { (wanted[$0] - Double(result[$0])) > (wanted[$1] - Double(result[$1])) }
                var k = 0
                while rest > 0 { result[order[k % n]] += 1; rest -= 1; k += 1 }
            }
            while rest < 0, let widest = result.indices.max(by: { result[$0] < result[$1] }) { result[widest] -= 1; rest += 1 }
            return result
        }

        // Choose the least aggressive structure that fits: individual blocks → compact sets → 1 px stakes → hatched sets.
        var modes = [SetMode](repeating: .normal, count: sets.count)
        var floorStake = false
        var layout = cells(modes, floorStake: false)
        var widths = allocate(layout, gap: gapPx)
        if widths == nil, !sets.isEmpty {
            let order = sets.indices.sorted { sets[$0].count != sets[$1].count ? sets[$0].count > sets[$1].count : $0 < $1 }
            func apply(compact k: Int, hatched h: Int, floor: Bool) -> [SetMode] {
                var result = [SetMode](repeating: .normal, count: sets.count)
                for (rank, i) in order.enumerated() { result[i] = rank < h ? .hatched : (rank < k ? .compact : .normal) }
                return result
            }
            func fits(_ k: Int, _ h: Int, _ floor: Bool) -> Bool {
                allocate(cells(apply(compact: k, hatched: h, floor: floor), floorStake: floor), gap: gapPx) != nil
            }
            func smallest(_ upper: Int, _ test: (Int) -> Bool) -> Int {
                var lo = 1, hi = upper
                while lo < hi { let mid = (lo + hi) / 2; if test(mid) { hi = mid } else { lo = mid + 1 } }
                return lo
            }
            let s = sets.count
            if fits(s, 0, false) {
                modes = apply(compact: smallest(s) { fits($0, 0, false) }, hatched: 0, floor: false)
            } else if fits(s, 0, true) {
                floorStake = true
                modes = apply(compact: smallest(s) { fits($0, 0, true) }, hatched: 0, floor: true)
            } else {
                floorStake = true
                modes = apply(compact: s, hatched: fits(s, s, true) ? smallest(s) { fits(s, $0, true) } : s, floor: true)
            }
            layout = cells(modes, floorStake: floorStake)
            widths = allocate(layout, gap: gapPx)
        }
        var gap = gapPx
        if widths == nil {
            // Pathological input (hundreds of steps in a few pixels): ignore minimum widths, then gaps.
            widths = allocate(layout, gap: gapPx, ignoreMinimum: true)
            if widths == nil { gap = 0; widths = allocate(layout, gap: 0, ignoreMinimum: true) }
        }
        guard let widths else { return [] }

        // Vertical helpers (pixel units, bottom-aligned on `height`).
        func heightPx(_ power: Double) -> Int {
            let h = Int((min(max(power, 0), domain) / domain * Double(height)).rounded())
            return min(height, max(minHeight, h))
        }
        func clipped(_ power: Double) -> Bool { power > domain + 1e-9 }
        func point(_ x: Int, _ y: Int) -> CGPoint { CGPoint(x: CGFloat(x) / scale, y: CGFloat(y) / scale) }
        let allCorners: ProfileBlock.Corners = m.roundsBottom
            ? [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading] : [.topLeading, .topTrailing]
        let leadingCorners: ProfileBlock.Corners = m.roundsBottom ? [.topLeading, .bottomLeading] : [.topLeading]
        let trailingCorners: ProfileBlock.Corners = m.roundsBottom ? [.topTrailing, .bottomTrailing] : [.topTrailing]

        func radius(_ widthPx: Int, _ minHeightPx: Int) -> CGFloat {
            min(m.radius, CGFloat(widthPx) / scale / 2, CGFloat(minHeightPx) / scale / 2)
        }
        func block(role: ProfileBlock.Role, step: Int, segment: Int, part: Int = 0, partCount: Int = 1, power: Double,
                   x0: Int, x1: Int, y0: Int, y1: Int, clipped: Bool, corners: ProfileBlock.Corners) -> ProfileBlock {
            // y0/y1 are the top edge heights in px above the baseline at the left/right edge.
            ProfileBlock(role: role, stepIndex: step, segmentIndex: segment, part: part, partCount: partCount,
                         zone: PowerZone(fractionOfFTP: power),
                         polygon: [point(x0, height - y0), point(x1, height - y1), point(x1, height), point(x0, height)],
                         cornerRadius: radius(x1 - x0, min(y0, y1)), roundedCorners: corners, clipped: clipped)
        }

        var blocks: [ProfileBlock] = []
        blocks.reserveCapacity(layout.count + 8)
        var x = 0
        for (cell, w) in zip(layout, widths) {
            let x0 = x, x1 = x + w
            x = x1 + gap
            guard w > 0 else { continue }
            switch cell.kind {
            case let .step(stepIndex, segment):
                let step = steps[stepIndex]
                let p0 = finite(step.startPower), p1 = finite(step.endPower)
                // Cut points: zone boundaries strictly inside the ramp, as fractions of the step.
                var cuts: [Double] = [0]
                if abs(p1 - p0) > 1e-9, w > 1 {
                    let lo = min(p0, p1), hi = max(p0, p1)
                    var inside = PowerZone.allCases.dropFirst().map(\.lowerBound).filter { $0 > lo && $0 < hi }.map { ($0 - p0) / (p1 - p0) }
                    inside.sort()
                    cuts += inside
                }
                cuts.append(1)
                // Pixel x of every cut; drop parts that collapse to zero width.
                var edges: [(x: Int, t: Double)] = []
                for t in cuts {
                    let px = t >= 1 ? x1 : x0 + Int((t * Double(w)).rounded())
                    if let last = edges.last, last.x >= px, t < 1 { continue }
                    edges.append((px, t))
                }
                if edges.count >= 2, edges[edges.count - 2].x >= edges[edges.count - 1].x { edges.remove(at: edges.count - 2) }
                if edges.count < 2 { edges = [(x0, 0), (x1, 1)] }
                let parts = edges.count - 1
                for part in 0..<parts {
                    let a = edges[part], b = edges[part + 1]
                    let pa = part == 0 ? p0 : p0 + (p1 - p0) * a.t, pb = part == parts - 1 ? p1 : p0 + (p1 - p0) * b.t
                    var corners: ProfileBlock.Corners = []
                    if part == 0 { corners.formUnion(leadingCorners) }
                    if part == parts - 1 { corners.formUnion(trailingCorners) }
                    let mid = p0 + (p1 - p0) * (a.t + b.t) / 2
                    blocks.append(block(role: .step, step: stepIndex, segment: segment, part: part, partCount: parts, power: mid,
                                        x0: a.x, x1: b.x, y0: heightPx(pa), y1: heightPx(pb),
                                        clipped: clipped(pa) || clipped(pb), corners: corners.isEmpty && parts == 1 ? allCorners : corners))
                }
            case let .hatched(i):
                let s = sets[i]
                blocks.append(block(role: .hatched, step: s.firstStep, segment: s.segment, power: s.onPower, x0: x0, x1: x1,
                                    y0: heightPx(s.onPower), y1: heightPx(s.onPower), clipped: clipped(s.onPower), corners: allCorners))
            case let .compact(i):
                let s = sets[i]
                if s.off > 0 {
                    blocks.append(block(role: .offFill, step: s.firstStep + 1, segment: s.segment, power: s.offPower, x0: x0, x1: x1,
                                        y0: heightPx(s.offPower), y1: heightPx(s.offPower), clipped: clipped(s.offPower), corners: allCorners))
                }
                let ring = 1, sMin = floorStake ? 1 : minStake
                let pitch = Double(w + ring) / Double(s.count)
                let onShare = Double(s.on) / Double(s.on + s.off)
                let maxW = Int((pitch - Double(ring) + 1e-9).rounded(.down))
                let stakeW = max(1, min(max(Int((onShare * pitch).rounded()), sMin), maxW))
                for k in 0..<s.count {
                    let left = x0 + Int((Double(k) * pitch + 1e-9).rounded(.down))
                    blocks.append(block(role: .stake, step: s.firstStep + k * s.stepsPerRep, segment: s.segment, power: s.onPower,
                                        x0: left, x1: min(x1, left + stakeW), y0: heightPx(s.onPower), y1: heightPx(s.onPower),
                                        clipped: clipped(s.onPower), corners: allCorners))
                }
            }
        }
        return blocks
    }
}
