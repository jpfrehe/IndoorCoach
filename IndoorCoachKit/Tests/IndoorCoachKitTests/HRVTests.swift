import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("HRV: RR-Filter, RMSSD")
struct HRVTests {
    @Test("Werte außerhalb 300–2000 ms werden verworfen")
    func range() {
        let r = HRV.analyze([800, 250, 810, 2500, 790])
        #expect(r.accepted == 3)
        #expect(r.rejected == 2)
    }

    @Test("Ausreißer > 20 % zum lokalen Median wird verworfen")
    func outlier() {
        let r = HRV.analyze([800, 810, 1600, 790, 800])
        #expect(r.rejected == 1)
        #expect(r.accepted == 4)
    }

    @Test("RMSSD und lnRMSSD aus aufeinanderfolgenden Werten")
    func rmssd() throws {
        let r = HRV.analyze([800, 810, 790, 800])
        let v = try #require(r.rmssd)
        #expect(abs(v - 200.0.squareRoot()) < 0.001)
        #expect(abs(try #require(r.lnRMSSD) - log(200.0.squareRoot())) < 0.001)
        #expect(r.quality == 1)
    }

    @Test("Differenzen über verworfene Werte hinweg zählen nicht")
    func gapSkipped() throws {
        let r = HRV.analyze([800, 810, 1600, 790, 800, 810])
        #expect(abs(try #require(r.rmssd) - 10) < 0.001)
    }

    @Test("Qualität ist der Anteil behaltener Werte")
    func quality() {
        let r = HRV.analyze([800, 810, 250, 790])
        #expect(abs(r.quality - 0.75) < 0.001)
    }

    @Test("Zu wenige Werte: kein RMSSD")
    func tooFew() {
        #expect(HRV.analyze([800, 810]).rmssd == nil)
        let empty = HRV.analyze([])
        #expect(empty.rmssd == nil)
        #expect(empty.quality == 0)
    }
}
