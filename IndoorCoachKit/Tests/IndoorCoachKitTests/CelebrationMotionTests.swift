import SwiftUI
import Testing
@testable import IndoorCoachKit

@Suite("Feier-Bewegung (AP0)")
struct CelebrationMotionTests {
    @Test func exactlyTwoCurves() {
        #expect(CelebrationMotion.Curve.allCases.count == 2)
        #expect(CelebrationMotion.animation(.spring, reduceMotion: false) == .spring(duration: 0.5, bounce: 0.25))
        #expect(CelebrationMotion.animation(.smooth, reduceMotion: false) == .smooth(duration: 0.25))
    }

    @Test func reduceMotionIsAShortFadeForBothCurves() {
        let fade = Animation.easeInOut(duration: 0.2)
        #expect(CelebrationMotion.reducedFade == fade)
        #expect(CelebrationMotion.animation(.spring, reduceMotion: true) == fade)
        #expect(CelebrationMotion.animation(.smooth, reduceMotion: true) == fade)
    }

    @Test func particlesMoveOnlyWithoutReduceMotionAndLowPower() {
        #expect(CelebrationMotion.allowsParticleMotion(reduceMotion: false, lowPowerMode: false))
        #expect(!CelebrationMotion.allowsParticleMotion(reduceMotion: true, lowPowerMode: false))
        #expect(!CelebrationMotion.allowsParticleMotion(reduceMotion: false, lowPowerMode: true))
        #expect(!CelebrationMotion.allowsParticleMotion(reduceMotion: true, lowPowerMode: true))
    }
}
