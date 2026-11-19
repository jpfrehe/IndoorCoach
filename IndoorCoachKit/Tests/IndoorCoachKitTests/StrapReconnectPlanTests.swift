import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Gurt: Wiederverbinden (Rückfall-Scan, Backoff)")
struct StrapReconnectPlanTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let strap = UUID()

    @Test func discoveringTheSavedStrapInTheFallbackScanConnects() {
        var plan = StrapReconnectPlan()
        plan.connectRequested(strap)
        #expect(plan.peripheralUnknown(now: t0) == .startFallbackScan(deadline: t0.addingTimeInterval(60)))
        #expect(plan.discovered(UUID()) == .none)               // anderer Gurt: ignorieren
        #expect(plan.discovered(strap) == .connect(strap))      // der gemerkte: verbinden (und Scan beenden)
        #expect(!plan.isFallbackScanning)
        #expect(plan.discovered(strap) == .none)                // nicht doppelt
    }

    @Test func theDevicesScreenScanNeverAutoConnects() {
        var plan = StrapReconnectPlan()
        plan.connectRequested(strap)
        #expect(plan.discovered(strap) == .none)                // kein Rückfall-Scan aktiv
    }

    @Test func fallbackScanEndsAfterSixtySecondsWithNotFound() {
        var plan = StrapReconnectPlan()
        plan.connectRequested(strap)
        _ = plan.peripheralUnknown(now: t0)
        #expect(plan.fallbackTimerFired(now: t0.addingTimeInterval(59)) == .none)
        #expect(plan.isFallbackScanning)
        #expect(plan.fallbackTimerFired(now: t0.addingTimeInterval(60)) == .reportNotFound)
        #expect(plan.fallbackTimerFired(now: t0.addingTimeInterval(61)) == .none)
        #expect(plan.discovered(strap) == .none)                // nach Ablauf verbindet nichts mehr
    }

    @Test func foundStrapDefusesTheTimer() {
        var plan = StrapReconnectPlan()
        plan.connectRequested(strap)
        _ = plan.peripheralUnknown(now: t0)
        #expect(plan.discovered(strap) == .connect(strap))
        #expect(plan.fallbackTimerFired(now: t0.addingTimeInterval(90)) == .none)
    }

    @Test func failedConnectsBackOffTwoFiveTenThenThirtySeconds() {
        var plan = StrapReconnectPlan()
        plan.connectRequested(strap)
        let delays = (0..<6).map { _ -> TimeInterval in
            if case .retryConnect(let after) = plan.connectFailed() { return after }
            return -1
        }
        #expect(delays == [2, 5, 10, 30, 30, 30])
        plan.connected()
        #expect(plan.failures == 0)
        #expect(plan.connectFailed() == .retryConnect(after: 2))
    }

    @Test func cancelStopsEverything() {
        var plan = StrapReconnectPlan()
        plan.connectRequested(strap)
        _ = plan.peripheralUnknown(now: t0)
        plan.cancel()
        #expect(plan.discovered(strap) == .none)
        #expect(plan.connectFailed() == .none)
        #expect(plan.peripheralUnknown(now: t0) == .none)
    }
}
