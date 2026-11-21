import Testing
@testable import IndoorCoachKit

@Suite("Winterhimmel · Vertrag (AP0)")
struct WinterSkyContractTests {
    @Test func endpointsAreExactAndInputIsClamped() {
        let start = WinterSky.stops(progress: 0)
        let end = WinterSky.stops(progress: 1)
        #expect(!start.isEmpty && start.count == end.count)
        #expect(start.first == Palette.RGB(hex: 0x5152C1))
        #expect(end.first == Palette.RGB(hex: 0xFFC247))
        #expect(end.last == Palette.peachFizz)
        #expect(WinterSky.stops(progress: -5) == start)
        #expect(WinterSky.stops(progress: 9) == end)
    }

    @Test func stopCountIsConstantAndTheMiddleLiesBetween() {
        let counts = Set(stride(from: 0.0, through: 1.0, by: 0.1).map { WinterSky.stops(progress: $0).count })
        #expect(counts.count == 1)
        let mid = WinterSky.stops(progress: 0.5)[0]
        let a = WinterSky.stops(progress: 0)[0], b = WinterSky.stops(progress: 1)[0]
        #expect(mid.r > min(a.r, b.r) && mid.r < max(a.r, b.r))
    }
}
