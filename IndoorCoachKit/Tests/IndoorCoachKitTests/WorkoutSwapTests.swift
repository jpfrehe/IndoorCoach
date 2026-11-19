import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Gegen Grundlage tauschen")
struct WorkoutSwapTests {
    let vo2 = WorkoutDefinition(title: "VO₂ 5×4", type: .vo2max, summary: "s", segments: [
        .warmup(15, from: 0.45, to: 0.75), .intervals(5, on: 240, at: 1.15, off: 240, at: 0.5), .cooldown(10, from: 0.65, to: 0.4)
    ])

    @Test func keepsDurationAndIsZ2() throws {
        let base = try #require(WorkoutSwap.base(for: vo2))
        #expect(base.totalDuration == vo2.totalDuration)
        #expect(base.type == .endurance)
        let main = try #require(base.segments.first { $0.kind == .steady })
        #expect((0.60...0.70).contains(main.power ?? 0))
        #expect(base.segments.first?.kind == .warmup && base.segments.last?.kind == .cooldown)
    }

    @Test func resultIsValid() throws {
        for minutes in [15, 20, 30, 45, 60, 90, 180] {
            let d = WorkoutDefinition(title: "t", type: .threshold, summary: "s", segments: [.steady(Double(minutes), at: 0.95)])
            let base = try #require(WorkoutSwap.base(for: d))
            #expect(base.totalDuration == minutes * 60)
            #expect(base.segments.allSatisfy { $0.duration > 0 })
            #expect(base.intensityFactor < 0.75)
            let data = try JSONEncoder().encode(base.segments)
            #expect(try JSONDecoder().decode([Segment].self, from: data).count == base.segments.count)
        }
    }

    @Test func tooShortIsNotSwapped() {
        let d = WorkoutDefinition(title: "t", type: .vo2max, summary: "s", segments: [.steady(10, at: 1.1)])
        #expect(WorkoutSwap.base(for: d) == nil)
    }
}
