import Foundation
import Testing
@testable import IndoorCoachKit

/// FIT bytes arrive from the network (Mac bridge) and from "Öffnen in": hostile input must not exhaust memory.
@Suite("FIT parser limits")
struct FITParserLimitsTests {
    /// Two power records ~136 years apart would have allocated a 4-billion-entry series.
    @Test func hugeTimestampSpanYieldsNoSeriesInsteadOfAllocating() throws {
        var fit = FITBuilder()
        fit.message(global: 20, fields: [(253, 4, 0), (7, 2, 200)])
        fit.data([(4, 0xFFFF_FFF0), (2, 210)])
        #expect(FITParser.powerSeries(from: fit.bytes) == nil)
        #expect(FITParser.heartRateSeries(from: fit.bytes) == nil)
        let summary = try? FITParser.summary(from: fit.bytes)
        #expect(summary?.powerCurve == nil)
    }

    @Test func a24HourRideStillHasItsSeries() {
        var fit = FITBuilder()
        let t0 = fitTime(rideStart)
        fit.message(global: 20, fields: [(253, 4, t0), (7, 2, 150)])
        fit.data([(4, t0 + UInt64(FITParser.maxSeriesSeconds - 1)), (2, 150)])
        #expect(FITParser.powerSeries(from: fit.bytes)?.count == FITParser.maxSeriesSeconds)
    }

    /// Zero-field data messages are 1 byte each: a 20 MB file must not turn into 20 M decoded messages.
    @Test func tooManyMessagesAreRejected() {
        var fit = FITBuilder()
        fit.message(global: 21, fields: [])
        for _ in 0..<(FITParser.maxMessages + 5) { fit.data([]) }
        #expect(throws: FITParser.Error.self) { try FITParser.summary(from: fit.bytes) }
    }
}
