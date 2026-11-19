import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Trend-Wächter")
struct TrendGuardTests {
    typealias T = WellnessTrendTests

    /// 25 Tage Basis, dann 3 Tage `recent`; Basis-Streuung 0 -> MAD 0, Schwelle = 5 bpm.
    static func rhr(base: Double = 50, recent: Double) -> WellnessTrend {
        T.trend(Array(repeating: base, count: 25) + Array(repeating: recent, count: 3))
    }

    static func input(rhr: WellnessTrend? = nil, resp: WellnessTrend? = nil, temp: WellnessTrend? = nil, hrv: WellnessTrend? = nil,
                      hrvWatchPinned: Bool = false, lastNegative: Bool = false, infekt: Bool = false, negatives3d: Int = 0,
                      warmupDelta: Double? = nil, morning: Bool? = nil) -> TrendGuard.Input {
        TrendGuard.Input(restingHR: rhr, respiratoryRate: resp, wristTemperature: temp, hrv: hrv, hrvWatchPinned: hrvWatchPinned,
                         lastCheckInNegative: lastNegative, lastCheckInInfection: infekt, negativeCheckIns3Days: negatives3d,
                         warmupDeltaBpm: warmupDelta, morningHRVSignal: morning)
    }

    // MARK: Ruhepuls-Schwelle

    @Test func restingHRBoundaryNeedsSecondSignal() {
        let at = Self.rhr(recent: 55)       // exakt +5
        let below = Self.rhr(recent: 54.9)
        #expect(TrendGuard.evaluate(Self.input(rhr: at, lastNegative: true)) == .triggered(variant: .restingHR, reasons: [.restingHR, .negativeCheckIn]))
        #expect(TrendGuard.evaluate(Self.input(rhr: below, lastNegative: true)) == .quiet)
    }

    @Test func restingHRAloneNeverTriggers() {
        #expect(TrendGuard.evaluate(Self.input(rhr: Self.rhr(recent: 70))) == .quiet)
    }

    @Test func thresholdUsesTwoMADWhenLarger() {
        // Streuung 44/50/56 -> Median 50, MAD 6 -> Schwelle 12
        let base = Array(repeating: 44.0, count: 10) + Array(repeating: 50.0, count: 5) + Array(repeating: 56.0, count: 10)
        func t(_ recent: Double) -> WellnessTrend { T.trend(base + Array(repeating: recent, count: 3)) }
        #expect(t(60).mad == 6)
        #expect(TrendGuard.evaluate(Self.input(rhr: t(61), infekt: true)) == .quiet)
        #expect(TrendGuard.evaluate(Self.input(rhr: t(62), infekt: true)) == .triggered(variant: .restingHR, reasons: [.restingHR, .infectionTag]))
    }

    @Test func notReadyRestingHRDoesNotTrigger() {
        let short = T.trend(Array(repeating: 50, count: 10) + [70, 70, 70])
        #expect(TrendGuard.evaluate(Self.input(rhr: short, lastNegative: true)) == .quiet)
    }

    // MARK: Zweite Signale

    @Test func infectionTagIsSecondSignal() {
        #expect(TrendGuard.evaluate(Self.input(rhr: Self.rhr(recent: 60), infekt: true))
                == .triggered(variant: .restingHR, reasons: [.restingHR, .infectionTag]))
    }

    @Test func respiratoryBoundary() {
        func resp(_ r: Double) -> WellnessTrend { T.trend(Array(repeating: 14, count: 25) + Array(repeating: r, count: 3), metric: .respiratoryRate) }
        let high = Self.rhr(recent: 60)
        #expect(TrendGuard.evaluate(Self.input(rhr: high, resp: resp(15.5))) == .triggered(variant: .restingHR, reasons: [.restingHR, .respiratoryRate]))
        #expect(TrendGuard.evaluate(Self.input(rhr: high, resp: resp(15.4))) == .quiet)
    }

    @Test func wristTemperatureBoundary() {
        func temp(_ r: Double) -> WellnessTrend { T.trend(Array(repeating: 35.5, count: 25) + Array(repeating: r, count: 3), metric: .wristTempDelta) }
        let high = Self.rhr(recent: 60)
        #expect(TrendGuard.evaluate(Self.input(rhr: high, temp: temp(36.0))) == .triggered(variant: .restingHR, reasons: [.restingHR, .wristTemperature]))
        #expect(TrendGuard.evaluate(Self.input(rhr: high, temp: temp(35.9))) == .quiet)
    }

    @Test func hrvOnlyCountsWithPinnedWatch() {
        // ln-Basis mit SD: abwechselnd 30/50, letzte 7 Tage 12 -> deutlich unter Basis - 1 SD
        let base = (0..<21).map { $0 % 2 == 0 ? 30.0 : 50.0 }
        let hrv = T.trend(base + Array(repeating: 12.0, count: 7), metric: .hrvSDNN)
        let high = Self.rhr(recent: 60)
        #expect(TrendGuard.evaluate(Self.input(rhr: high, hrv: hrv, hrvWatchPinned: false)) == .quiet)
        #expect(TrendGuard.evaluate(Self.input(rhr: high, hrv: hrv, hrvWatchPinned: true)) == .triggered(variant: .restingHR, reasons: [.restingHR, .hrv]))
    }

    @Test func hrvAtBoundaryDoesNotCount() {
        let flat = T.trend(Array(repeating: 40.0, count: 28), metric: .hrvSDNN)   // SD 0, 7-Tage = Basis -> nicht kleiner
        #expect(TrendGuard.evaluate(Self.input(rhr: Self.rhr(recent: 60), hrv: flat, hrvWatchPinned: true)) == .quiet)
    }

    @Test func morningHRVSignalIsSecondSignal() {
        let high = Self.rhr(recent: 60)
        #expect(TrendGuard.evaluate(Self.input(rhr: high, morning: true)) == .triggered(variant: .restingHR, reasons: [.restingHR, .morningHRV]))
        #expect(TrendGuard.evaluate(Self.input(rhr: high, morning: false)) == .quiet)
        #expect(TrendGuard.evaluate(Self.input(rhr: high, morning: nil)) == .quiet)
    }

    @Test func reasonsListAllSignals() {
        let r = TrendGuard.evaluate(Self.input(rhr: Self.rhr(recent: 60), lastNegative: true, infekt: true))
        #expect(r == .triggered(variant: .restingHR, reasons: [.restingHR, .negativeCheckIn, .infectionTag]))
    }

    // MARK: S0 ohne Ruhepuls

    @Test func s0NeedsTwoNegativeCheckInsAndWarmupDelta() {
        #expect(TrendGuard.evaluate(Self.input(negatives3d: 2, warmupDelta: 5)) == .triggered(variant: .withoutRestingHR, reasons: [.repeatedNegativeCheckIns, .warmupHR]))
        #expect(TrendGuard.evaluate(Self.input(negatives3d: 2, warmupDelta: 4.9)) == .quiet)
        #expect(TrendGuard.evaluate(Self.input(negatives3d: 1, warmupDelta: 8)) == .quiet)
        #expect(TrendGuard.evaluate(Self.input(negatives3d: 2, warmupDelta: nil)) == .quiet)
    }

    @Test func s0OnlyWithoutUsableRestingHR() {
        // Ruhepuls vorhanden und ruhig -> S0 greift nicht
        #expect(TrendGuard.evaluate(Self.input(rhr: Self.rhr(recent: 50), negatives3d: 2, warmupDelta: 9)) == .quiet)
    }

    // MARK: Aufwärm-Check

    @Test func warmupDeltaIsLastAgainstMedianOfEarlier() {
        func check(_ day: Int, _ hr: Double?, valid: Bool = true) -> WarmupCheck {
            WarmupCheck(date: Date(timeIntervalSince1970: Double(day) * 86_400), refWatts: 140, hrMean: hr, valid: valid, reason: nil, source: .measured)
        }
        let checks = [check(1, 120), check(2, 122), check(3, 118), check(4, 126)]
        #expect(TrendGuard.warmupDelta(checks: checks, refWatts: 140) == 6)               // 126 - Median(118,120,122)=120
        #expect(TrendGuard.warmupDelta(checks: Array(checks.prefix(3)), refWatts: 140) == nil)   // zu wenige
        #expect(TrendGuard.warmupDelta(checks: checks + [check(5, 130, valid: false)], refWatts: 140) == 6)
        #expect(TrendGuard.warmupDelta(checks: checks, refWatts: 150) == nil)
    }

    // MARK: Harte Einheit

    @Test func hardWorkoutTypes() {
        for t in [WorkoutType.vo2max, .threshold, .anaerobic, .sweetSpot] { #expect(TrendGuard.isHard(t)) }
        for t in [WorkoutType.recovery, .endurance, .tempo, .sprint, .test, .mixed] { #expect(!TrendGuard.isHard(t)) }
    }

    @Test func textsAreNeutral() {
        #expect(TrendGuard.cardText == "Deine Werte weichen seit 3 Tagen von deiner Basis ab. Wie fühlst du dich? Morgen lieber locker?")
    }
}
