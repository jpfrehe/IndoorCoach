import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Workout adjust")
struct WorkoutAdjustTests {
    let sweetSpot = WorkoutDefinition(title: "Sweet Spot 2×20", type: .sweetSpot, summary: "s", segments: [
        .warmup(10, from: 0.45, to: 0.75), .intervals(2, on: 1200, at: 0.9, off: 300, at: 0.55), .cooldown(10, from: 0.65, to: 0.4)
    ]) // 70 min
    let vo2 = WorkoutDefinition(title: "VO2 5×3", type: .vo2max, summary: "s", segments: [
        .warmup(10, from: 0.45, to: 0.75), .intervals(5, on: 180, at: 1.15, off: 180, at: 0.5), .cooldown(10, from: 0.65, to: 0.4)
    ]) // 50 min
    let endurance = WorkoutDefinition(title: "Grundlage", type: .endurance, summary: "s", segments: [
        .warmup(10, from: 0.45, to: 0.65), .steady(70, at: 0.65), .cooldown(10, from: 0.6, to: 0.4)
    ]) // 90 min
    let tempo = WorkoutDefinition(title: "Tempo", type: .tempo, summary: "s", segments: [
        .warmup(10, from: 0.45, to: 0.75), .steady(40, at: 0.82), .cooldown(10, from: 0.65, to: 0.4)
    ]) // 60 min

    func assertValid(_ d: WorkoutDefinition) {
        #expect(!d.segments.isEmpty)
        for s in d.segments {
            #expect(s.effectiveDuration > 0)
            if s.kind == .intervals { #expect((s.repeatCount ?? 0) >= 1); #expect(s.duration == s.effectiveDuration) }
        }
        #expect(d.segments.first?.kind == .warmup)
        #expect(d.segments.last?.kind == .cooldown)
    }

    @Test func sweetSpotTo45DropsOneRepeat() throws {
        let r = try #require(WorkoutAdjust.apply(to: sweetSpot, minutes: 45, easierBy: nil))
        assertValid(r.definition)
        #expect(abs(r.definition.totalDuration - 45 * 60) <= 60)
        #expect(r.definition.segments[1].repeatCount == 1)
        #expect(r.description == "45 min statt 70 min")
        #expect(r.definition.estimatedTSS < sweetSpot.estimatedTSS)
    }

    @Test func vo2To30() throws {
        let r = try #require(WorkoutAdjust.apply(to: vo2, minutes: 30, easierBy: nil))
        assertValid(r.definition)
        #expect(abs(r.definition.totalDuration - 30 * 60) <= 60)
        #expect((r.definition.segments[1].repeatCount ?? 0) >= 1)
        #expect(r.definition.segments.first!.duration >= 300)
        #expect(r.definition.segments.last!.duration >= 300)
    }

    @Test func enduranceTrimsFillerFirst() throws {
        let r = try #require(WorkoutAdjust.apply(to: endurance, minutes: 60, easierBy: nil))
        assertValid(r.definition)
        #expect(abs(r.definition.totalDuration - 3600) <= 60)
        #expect(r.definition.segments.first!.duration == 600)
        #expect(r.definition.segments.last!.duration == 600)
        #expect(r.description == "60 min statt 90 min")
    }

    @Test func mainBlockNeverBelowHalf() throws {
        let r = try #require(WorkoutAdjust.apply(to: tempo, minutes: 30, easierBy: nil))
        assertValid(r.definition)
        #expect(r.definition.segments[1].duration >= 20 * 60)
        #expect(abs(r.definition.totalDuration - 1800) <= 60)
    }

    @Test func infeasibleReportsClosest() throws {
        let hard = WorkoutDefinition(title: "x", type: .threshold, summary: "", segments: [
            .warmup(10, from: 0.5, to: 0.75), .steady(60, at: 0.95), .cooldown(10, from: 0.6, to: 0.4)
        ])
        let r = try #require(WorkoutAdjust.apply(to: hard, minutes: 30, easierBy: nil))
        assertValid(r.definition)
        #expect(!r.isExact)
        #expect(r.definition.totalDuration > 30 * 60)
        #expect(r.definition.segments[1].duration >= 30 * 60)
        #expect(r.description.hasSuffix("min statt 80 min"))
    }

    @Test func shortenOptionsOnlyIfAtLeastFiveMinutesShorter() {
        #expect(WorkoutAdjust.shortenOptions(for: sweetSpot) == [30, 45, 60])
        #expect(WorkoutAdjust.shortenOptions(for: vo2) == [30, 45])
        #expect(WorkoutAdjust.shortenOptions(for: tempo) == [30, 45])
        let short = WorkoutDefinition(title: "k", type: .recovery, summary: "", segments: [.steady(30, at: 0.5)])
        #expect(WorkoutAdjust.shortenOptions(for: short).isEmpty)
        #expect(WorkoutAdjust.apply(to: short, minutes: 30, easierBy: nil) == nil)
    }

    @Test func easierScalesPowersKeepsDurations() throws {
        let r = try #require(WorkoutAdjust.apply(to: sweetSpot, minutes: nil, easierBy: 10))
        #expect(r.definition.totalDuration == sweetSpot.totalDuration)
        #expect(abs((r.definition.segments[1].onPower ?? 0) - 0.81) < 0.0001)
        #expect(abs((r.definition.segments[0].powerLow ?? 0) - 0.405) < 0.0001)
        #expect(abs((r.definition.segments[0].powerHigh ?? 0) - 0.675) < 0.0001)
        #expect(r.definition.segments[1].offPower == 0.55)
        #expect(r.description == "−10 % Intensität")
        #expect(r.definition.estimatedTSS < sweetSpot.estimatedTSS)
        let s = try #require(WorkoutAdjust.apply(to: tempo, minutes: nil, easierBy: 5))
        #expect(abs((s.definition.segments[1].power ?? 0) - 0.779) < 0.0001)
    }

    @Test func combined() throws {
        let r = try #require(WorkoutAdjust.apply(to: sweetSpot, minutes: 45, easierBy: 5))
        #expect(r.description == "45 min statt 70 min · −5 % Intensität")
        assertValid(r.definition)
    }

    @Test func nothingToDoIsNil() {
        #expect(WorkoutAdjust.apply(to: sweetSpot, minutes: nil, easierBy: nil) == nil)
        #expect(WorkoutAdjust.apply(to: sweetSpot, minutes: 90, easierBy: 0) == nil)
    }
}
