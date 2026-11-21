import CoreGraphics
import Foundation

/// Pure helpers around the workout profile (concept 21 §4, AP2/AP3): VoiceOver sentence, selection by position,
/// minute ticks of the detail axis and the audio-graph points. No SwiftUI, so everything here is unit-tested.
enum WorkoutProfileSupport {
    /// "4:00", "1:05:00" – clock style used for step durations.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// One VoiceOver sentence: duration, section count, peak, dominant zones and interval sets.
    /// Example: "1 h, 3 Abschnitte, Spitze 115 % FTP (288 W), überwiegend Z1 und Z5, 5 Intervalle à 4:00".
    static func summary(definition: WorkoutDefinition, ftp: Int) -> String {
        let sections = definition.segments.count == 1 ? "1 Abschnitt" : "\(definition.segments.count) Abschnitte"
        // Corrupt repeat counts would unroll into millions of steps: name the section count only.
        guard !WorkoutProfileGeometry.exceedsRepeatLimit(definition) else {
            return "\(sections), mehr als \(WorkoutProfileGeometry.maxRepeats) Wiederholungen"
        }
        let peak = min(definition.steps.map { max(WorkoutProfileGeometry.finite($0.startPower), WorkoutProfileGeometry.finite($0.endPower)) }.max() ?? 0,
                       WorkoutProfileGeometry.maxDomainTop)
        var parts = [
            Formatters.duration(definition.totalDuration),
            sections,
            "Spitze \(Int((peak * 100).rounded())) % FTP (\(Int((peak * Double(ftp)).rounded())) W)",
        ]
        let zones = definition.timeInZones()
        let total = Double(zones.values.reduce(0, +))
        if total > 0 {
            let main = zones.filter { Double($0.value) / total >= 0.2 }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(2).map(\.key).sorted()
            if !main.isEmpty { parts.append("überwiegend " + main.map(\.shortName).joined(separator: " und ")) }
        }
        // Real interval counts, merged per on-duration ("3 Intervalle à 12:00").
        var counts: [(on: Int, count: Int)] = []
        for s in definition.segments where s.kind == .intervals {
            let n = s.repeatCount ?? 1, on = s.onDuration ?? 60
            guard n >= 2, on > 0 else { continue }
            if let i = counts.firstIndex(where: { $0.on == on }) { counts[i].count += n } else { counts.append((on, n)) }
        }
        parts += counts.map { "\($0.count) Intervalle à \(clock($0.on))" }
        return parts.joined(separator: ", ")
    }

    // MARK: Selection

    /// Step under (or nearest to) a horizontal position of the detail plot; ignores compact-set helper blocks.
    static func stepIndex(atX x: CGFloat, blocks: [ProfileBlock]) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for block in blocks where block.role != .offFill {
            let b = block.bounds
            let d = x < b.minX ? b.minX - x : (x > b.maxX ? x - b.maxX : 0)
            if best == nil || d < best!.distance { best = (block.stepIndex, d) }
        }
        return best?.index
    }

    /// "Abschnitt 3 · 4:00 @ 115 % (288 W) · Z5" – ramps read "10:00 @ 50 → 70 % (125 → 175 W) · Z1–Z2".
    static func selectionText(definition: WorkoutDefinition, ftp: Int, stepIndex: Int) -> String? {
        guard !WorkoutProfileGeometry.exceedsRepeatLimit(definition) else { return nil }
        let steps = definition.steps
        guard steps.indices.contains(stepIndex) else { return nil }
        let step = steps[stepIndex]
        func clean(_ p: Double) -> Double { min(max(WorkoutProfileGeometry.finite(p), 0), WorkoutProfileGeometry.maxDomainTop) }
        func pct(_ p: Double) -> Int { Int((clean(p) * 100).rounded()) }
        func watts(_ p: Double) -> Int { Int((clean(p) * Double(ftp)).rounded()) }
        let power: String, zone: String
        if pct(step.startPower) == pct(step.endPower) {
            power = "\(pct(step.startPower)) % (\(watts(step.startPower)) W)"
            zone = PowerZone(fractionOfFTP: step.startPower).shortName
        } else {
            power = "\(pct(step.startPower)) → \(pct(step.endPower)) % (\(watts(step.startPower)) → \(watts(step.endPower)) W)"
            let a = PowerZone(fractionOfFTP: step.startPower), b = PowerZone(fractionOfFTP: step.endPower)
            zone = a == b ? a.shortName : "\(min(a, b).shortName)–\(max(a, b).shortName)"
        }
        return "Abschnitt \(stepIndex + 1) · \(clock(step.duration)) @ \(power) · \(zone)"
    }

    // MARK: Axis and audio graph

    /// Round minute ticks, at most five: 60 → 0/15/30/45/60, 45 → 0/15/30/45, 95 → 0/30/60/90.
    static func minuteTicks(totalSeconds: Int) -> [Int] {
        let minutes = Double(totalSeconds) / 60
        guard minutes >= 1 else { return [0] }
        let step = [1, 2, 5, 10, 15, 30, 60, 120, 240].first { minutes / Double($0) <= 4 } ?? 240
        return Array(stride(from: 0, through: Int(minutes), by: step))
    }

    /// Points of the audio graph: minute and watts at the start and end of every step.
    static func audioPoints(definition: WorkoutDefinition, ftp: Int) -> [(minute: Double, watts: Double)] {
        var result: [(minute: Double, watts: Double)] = []
        guard !WorkoutProfileGeometry.exceedsRepeatLimit(definition) else { return result }
        for step in definition.steps where step.duration > 0 {
            result.append((Double(step.start) / 60, WorkoutProfileGeometry.finite(step.startPower) * Double(ftp)))
            result.append((Double(step.start + step.duration) / 60, WorkoutProfileGeometry.finite(step.endPower) * Double(ftp)))
        }
        return result
    }
}

/// Widths of the segmented bar (concept 21 §5, D3/D17): shares of the width, whole-pixel gaps, a minimum width per
/// visible segment, and the sum of segments plus gaps equals the width. Zero values get no segment.
enum SegmentedBarLayout {
    struct Item: Equatable {
        var index: Int
        var x: CGFloat
        var width: CGFloat
    }

    static func make(values: [Double], width: CGFloat, scale: CGFloat, gap: CGFloat = 2, minWidth: CGFloat = 4) -> [Item] {
        let visible = values.indices.filter { values[$0].isFinite && values[$0] > 0 }
        guard !visible.isEmpty, width > 0, scale > 0 else { return [] }
        let total = Int((width * scale).rounded())
        let n = visible.count
        var gapPx = max(1, Int((gap * scale).rounded()))
        if total - gapPx * (n - 1) < n { gapPx = 0 }
        let available = total - gapPx * (n - 1)
        guard available > 0 else { return [] }
        let minPx = Double(Int((minWidth * scale).rounded(.up)))
        let sum = visible.reduce(0.0) { $0 + values[$1] }

        // Water-filling: segments below the minimum are pinned to it, the rest share what is left.
        var wanted = [Int: Double]()
        if Double(n) * minPx > Double(available) {
            for i in visible { wanted[i] = values[i] / sum * Double(available) }   // too narrow for minimums
        } else {
            var pinned = Set<Int>()
            while true {
                let free = visible.filter { !pinned.contains($0) }
                let freeSum = free.reduce(0.0) { $0 + values[$1] }
                let room = Double(available) - Double(pinned.count) * minPx
                var changed = false
                for i in free {
                    let w = values[i] / freeSum * room
                    wanted[i] = w
                    if w < minPx { pinned.insert(i); changed = true }
                }
                if !changed || pinned.count == n { break }
            }
            for i in pinned { wanted[i] = minPx }
        }
        var px = visible.map { Int((wanted[$0] ?? 0) + 1e-7) }
        var rest = available - px.reduce(0, +)
        let order = px.indices.sorted {
            (wanted[visible[$0]] ?? 0) - Double(px[$0]) > (wanted[visible[$1]] ?? 0) - Double(px[$1])
        }
        var k = 0
        while rest > 0 { px[order[k % n]] += 1; rest -= 1; k += 1 }
        while rest < 0, let widest = px.indices.max(by: { px[$0] < px[$1] }) { px[widest] -= 1; rest += 1 }

        var items: [Item] = []
        var x = 0
        for (slot, i) in visible.enumerated() {
            items.append(Item(index: i, x: CGFloat(x) / scale, width: CGFloat(px[slot]) / scale))
            x += px[slot] + gapPx
        }
        return items
    }
}
