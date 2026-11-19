import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Aufwärm-Check")
struct WarmupCheckTests {
    static let ftp = 250
    static let ref = 140

    static var definition: WorkoutDefinition {
        let base: [Segment] = [.warmup(10, from: 0.5, to: 0.7), .intervals(2, on: 1200, at: 0.9, off: 300, at: 0.55),
                               .cooldown(8, from: 0.6, to: 0.4)]
        return WorkoutDefinition(title: "SS", type: .sweetSpot, summary: "",
                                 segments: WarmupCheck.ensuringBlock(in: base, refWatts: ref, ftp: ftp))
    }

    /// Ride along `definition` (block scaled by `blockFactor`), `lead` seconds earlier; pulse climbs to `hr` within the block.
    static func ride(lead: Int = 0, blockFactor: Double = 1, hr: Double = 118, withPower: Bool = true,
                     hrDropouts: Int = 0, hrJump: Bool = false, truncateTo: Int? = nil) -> RideSeconds {
        let def = definition
        var watts = [Double](repeating: 100, count: lead)
        var heart = [Double](repeating: 105, count: lead)
        let blockStart = lead + 600
        for step in def.steps {
            for i in 0..<step.duration {
                let f = step.startPower + (step.endPower - step.startPower) * (Double(i) + 0.5) / Double(step.duration)
                let t = lead + step.start + i
                let inBlock = t >= blockStart && t < blockStart + 360
                watts.append(f * Double(ftp) * (inBlock ? blockFactor : 1))
                if inBlock {
                    let k = t - blockStart
                    var h = k < 240 ? 105 + (hr - 105) * Double(k) / 240 : hr
                    if k >= 300 {
                        if k - 300 < hrDropouts { h = 0 }
                        if hrJump && k == 330 { h = hr + 25 }
                    }
                    heart.append(h)
                } else {
                    heart.append(110)
                }
            }
        }
        if let truncateTo { watts = Array(watts.prefix(truncateTo)); heart = Array(heart.prefix(truncateTo)) }
        return RideSeconds(watts: withPower ? watts : watts.map { _ in 0 }, beatsPerMinute: heart)
    }

    // MARK: Block in the plan

    @Test func defaultReferenceIsFiftyFivePercentRoundedToFiveWatts() {
        #expect(WarmupCheck.defaultWatts(ftp: 273) == 150)
        #expect(WarmupCheck.defaultWatts(ftp: 250) == 140)
        #expect(WarmupCheck.defaultWatts(ftp: 0) == 0)
    }

    @Test func insertsStandardBlockAfterWarmup() {
        let segments = Self.definition.segments
        #expect(segments.count == 4)
        let block = segments[1]
        #expect(block.kind == .steady)
        #expect(block.duration == 360)
        #expect(block.cadence == 90)
        #expect(block.text == WarmupCheck.markerText)
        #expect(abs((block.power ?? 0) - 140.0 / 250.0) < 0.001)
    }

    @Test func normalizesAnExistingBlockInPlaceAndIsIdempotent() {
        var segments: [Segment] = [.warmup(8, from: 0.4, to: 0.6),
                                   Segment(kind: .steady, duration: 300, power: 0.7, text: "aufwärm-check bitte"),
                                   .steady(30, at: 0.65)]
        segments = WarmupCheck.ensuringBlock(in: segments, refWatts: 140, ftp: 250)
        #expect(segments.count == 3)
        #expect(segments[1].duration == 360 && segments[1].text == WarmupCheck.markerText)
        #expect(abs((segments[1].power ?? 0) - 0.56) < 0.001)
        #expect(WarmupCheck.ensuringBlock(in: segments, refWatts: 140, ftp: 250) == segments)
    }

    @Test func workoutWithoutWarmupGetsNoBlock() {
        let segments: [Segment] = [.steady(30, at: 0.65)]
        #expect(WarmupCheck.ensuringBlock(in: segments, refWatts: 140, ftp: 250) == segments)
    }

    @Test func blockStartFollowsPlanTimeline() {
        #expect(WarmupCheck.blockStart(in: Self.definition) == 600)
        #expect(WarmupCheck.blockStart(in: WorkoutDefinition(title: "x", type: .endurance, summary: "", segments: [.steady(30, at: 0.6)])) == nil)
    }

    // MARK: Evaluation

    @Test func measuredCheckAlignsAndTakesLastMinuteMean() throws {
        let check = try #require(WarmupCheck.evaluate(date: .now, definition: Self.definition, seconds: Self.ride(lead: 75),
                                                      ftp: Self.ftp, refWatts: Self.ref))
        #expect(check.valid)
        #expect(check.source == .measured)
        #expect(check.refWatts == Self.ref)
        #expect(abs((check.hrMean ?? 0) - 118) < 0.5)
    }

    @Test func invalidWhenPowerMissesTheReference() throws {
        let check = try #require(WarmupCheck.evaluate(date: .now, definition: Self.definition,
                                                      seconds: Self.ride(blockFactor: 1.12), ftp: Self.ftp, refWatts: Self.ref))
        #expect(!check.valid)
        #expect(check.reason?.contains("Leistung") == true)
    }

    @Test func invalidWithHeartRateDropoutsOrJumps() throws {
        let dropouts = try #require(WarmupCheck.evaluate(date: .now, definition: Self.definition,
                                                         seconds: Self.ride(hrDropouts: 20), ftp: Self.ftp, refWatts: Self.ref))
        #expect(!dropouts.valid)
        #expect(dropouts.reason?.contains("Puls") == true)
        let jump = try #require(WarmupCheck.evaluate(date: .now, definition: Self.definition,
                                                     seconds: Self.ride(hrJump: true), ftp: Self.ftp, refWatts: Self.ref))
        #expect(!jump.valid)
    }

    @Test func toleratesFewDropouts() throws {
        let check = try #require(WarmupCheck.evaluate(date: .now, definition: Self.definition,
                                                      seconds: Self.ride(hrDropouts: 8), ftp: Self.ftp, refWatts: Self.ref))
        #expect(check.valid)
        #expect(abs((check.hrMean ?? 0) - 118) < 0.5, "dropout seconds do not enter the mean")
    }

    @Test func withoutPowerSecondsTheCheckIsAssumedErg() throws {
        let check = try #require(WarmupCheck.evaluate(date: .now, definition: Self.definition,
                                                      seconds: Self.ride(withPower: false), ftp: Self.ftp, refWatts: Self.ref))
        #expect(check.valid)
        #expect(check.source == .assumedERG)
        #expect(abs((check.hrMean ?? 0) - 118) < 0.5)
    }

    @Test func withoutPowerAndWithoutPlanThereIsNoCheck() {
        #expect(WarmupCheck.evaluate(date: .now, definition: nil, seconds: Self.ride(withPower: false),
                                     ftp: Self.ftp, refWatts: Self.ref) == nil)
    }

    @Test func shortRideIsInvalidNotMissing() throws {
        let check = try #require(WarmupCheck.evaluate(date: .now, definition: Self.definition,
                                                      seconds: Self.ride(truncateTo: 800), ftp: Self.ftp, refWatts: Self.ref))
        #expect(!check.valid)
        #expect(check.hrMean == nil)
    }

    @Test func fallbackFindsSteadyStretchWithoutPlan() throws {
        let check = try #require(WarmupCheck.evaluate(date: .now, definition: nil, seconds: Self.ride(lead: 0),
                                                      ftp: Self.ftp, refWatts: Self.ref))
        #expect(check.valid)
        #expect(check.source == .measured)
        #expect(abs((check.hrMean ?? 0) - 118) < 1.5)
    }

    @Test func fallbackFindsNothingInAnUnstructuredRide() {
        let watts = (0..<3000).map { 100 + 80 * sin(Double($0) / 40) }
        let seconds = RideSeconds(watts: watts, beatsPerMinute: [Double](repeating: 120, count: 3000))
        #expect(WarmupCheck.evaluate(date: .now, definition: nil, seconds: seconds, ftp: Self.ftp, refWatts: Self.ref) == nil)
    }

    // MARK: Trend

    static func check(_ day: Int, hr: Double, ref: Int = ref, valid: Bool = true) -> WarmupCheck {
        WarmupCheck(date: Date(timeIntervalSince1970: Double(day) * 86_400), refWatts: ref, hrMean: valid ? hr : nil,
                    valid: valid, reason: valid ? nil : "x", source: .measured)
    }

    @Test func trendNeedsThreeValidChecksAtTheSameReference() {
        let two = WarmupCheck.trend(checks: [Self.check(1, hr: 120), Self.check(2, hr: 119)], refWatts: Self.ref)
        #expect(two.direction == .notEnough && two.count == 2)
        let mixed = WarmupCheck.trend(checks: [Self.check(1, hr: 120), Self.check(2, hr: 119),
                                               Self.check(3, hr: 119, ref: 150), Self.check(4, hr: 100, valid: false)], refWatts: Self.ref)
        #expect(mixed.direction == .notEnough && mixed.count == 2)
    }

    @Test func trendIsMedianBasedAndDetectsFallingPulse() {
        let checks = [Self.check(1, hr: 126), Self.check(2, hr: 140), Self.check(3, hr: 124),
                      Self.check(4, hr: 121), Self.check(5, hr: 119), Self.check(6, hr: 118)]
        let trend = WarmupCheck.trend(checks: checks, refWatts: Self.ref)
        #expect(trend.direction == .falling)
        #expect(trend.count == 6)
        #expect(trend.medianHR == 119, "median of the last three")
    }

    @Test func trendStableAndRising() {
        let stable = (1...4).map { Self.check($0, hr: 120 + Double($0 % 2)) }
        #expect(WarmupCheck.trend(checks: stable, refWatts: Self.ref).direction == .stable)
        let rising = [120, 121, 124, 126].enumerated().map { Self.check($0.offset, hr: Double($0.element)) }
        #expect(WarmupCheck.trend(checks: rising, refWatts: Self.ref).direction == .rising)
    }

    @Test func trendOnlyCountsChecksSinceTheBaseDate() {
        let checks = (1...5).map { Self.check($0, hr: 120) }
        let since = Date(timeIntervalSince1970: 4 * 86_400)
        #expect(WarmupCheck.trend(checks: checks, refWatts: Self.ref, since: since).count == 2)
    }

    // MARK: Profile

    @Test func profileDecodesLegacyJSONWithoutWarmupFields() throws {
        let profile = try JSONDecoder().decode(AthleteProfile.self, from: Data(#"{"ftp":260}"#.utf8))
        #expect(profile.warmupCheckWatts == nil && profile.warmupCheckBaseSince == nil)
        #expect(profile.effectiveWarmupCheckWatts == 145)
    }

    @Test func profileKeepsStoredReferenceWhenFTPChanges() throws {
        var profile = AthleteProfile()
        profile.warmupCheckWatts = 140
        profile.ftp = 300
        let data = try JSONEncoder().encode(profile)
        let back = try JSONDecoder().decode(AthleteProfile.self, from: data)
        #expect(back.effectiveWarmupCheckWatts == 140)
    }

    // MARK: Plan prompt

    static func planContext(ftp: Int = 250, ref: Int? = nil) -> PlanContext {
        var profile = AthleteProfile()
        profile.ftp = ftp
        profile.warmupCheckWatts = ref
        let cal = Calendar.current
        let today = cal.startOfDay(for: Formatters.isoDay.date(from: "2026-11-17") ?? .now)
        return PlanContext(profile: profile, today: today, horizonStart: today,
                           horizonEnd: cal.date(byAdding: .day, value: 6, to: today) ?? today,
                           load: nil, weeks: [], recentRides: [], alreadyPlanned: [], wish: "")
    }

    static let planJSON = """
    {"weekFocus":"f","notes":"n","workouts":[
      {"date":"2026-11-17","title":"Grundlage","type":"endurance","summary":"s","rationale":"r","segments":[
        {"kind":"warmup","duration":600,"power":null,"powerLow":0.45,"powerHigh":0.7,"repeat":null,"onDuration":null,"offDuration":null,"onPower":null,"offPower":null,"cadence":null,"text":null},
        {"kind":"steady","duration":3000,"power":0.65,"powerLow":null,"powerHigh":null,"repeat":null,"onDuration":null,"offDuration":null,"onPower":null,"offPower":null,"cadence":null,"text":null},
        {"kind":"cooldown","duration":300,"power":null,"powerLow":0.4,"powerHigh":0.6,"repeat":null,"onDuration":null,"offDuration":null,"onPower":null,"offPower":null,"cadence":null,"text":null}]}
    ]}
    """

    @Test func parseAddsTheBlockDeterministically() throws {
        let plan = try PlanPrompt.parse(Self.planJSON, context: Self.planContext(ftp: 250, ref: 140))
        let segments = try #require(plan.workouts.first?.definition.segments)
        #expect(segments.count == 4)
        #expect(segments[1].text == WarmupCheck.markerText && segments[1].duration == 360)
        #expect(abs((segments[1].power ?? 0) - 0.56) < 0.001)
        #expect(plan.workouts[0].definition.totalDuration == 600 + 360 + 3000 + 300)
    }

    @Test func parseDerivesReferenceFromFTPWhenProfileHasNone() throws {
        let plan = try PlanPrompt.parse(Self.planJSON, context: Self.planContext(ftp: 300, ref: nil))
        #expect(abs((plan.workouts[0].definition.segments[1].power ?? 0) - 165.0 / 300.0) < 0.001)
    }

    @Test func systemPromptAndUserMessageCarryTheRule() {
        #expect(PlanPrompt.system.contains("Aufwärm-Check"))
        #expect(!PlanPrompt.system.contains("LSCT"))
        let msg = PlanPrompt.userMessage(Self.planContext(ftp: 250, ref: 140))
        #expect(msg.contains("Aufwärm-Check: 140 W"))
        #expect(msg.contains("56 % FTP"))
    }

    @Test func zwoExportCarriesTheTextEvent() throws {
        let plan = try PlanPrompt.parse(Self.planJSON, context: Self.planContext(ftp: 250, ref: 140))
        let xml = ZWOExporter.xml(for: plan.workouts[0].definition)
        #expect(xml.contains(#"message="Aufwärm-Check""#))
        #expect(xml.contains(#"Cadence="90""#) || xml.contains("Cadence=\"90\""))
    }
}

@Suite("Aufwärm-Check Demo")
struct WarmupCheckDemoTests {
    @Test func demoRidesShowAFallingTrend() {
        let ftp = 250
        let ref = WarmupCheck.defaultWatts(ftp: ftp)
        let rides = DemoData.rides(days: 84, ftp: ftp).filter(\.trainer)
        let checks = rides.compactMap { ride in
            WarmupCheck.evaluate(date: ride.startDate, definition: nil, seconds: DemoData.syntheticSeconds(for: ride, ftp: ftp),
                                 ftp: ftp, refWatts: ref)
        }
        let trend = WarmupCheck.trend(checks: checks, refWatts: ref)
        #expect(trend.count >= 6)
        #expect(trend.direction == .falling)
    }
}
