import Foundation
import Testing
@testable import IndoorCoachKit

/// Winterhimmel (docs/22, B3): OKLab-Schlüsselbilder Indigo → Sunset → Mango, Schneedichte folgt dem Fortschritt.
@Suite("Winterhimmel · Logik")
struct WinterSkyTests {
    private let steps = stride(from: 0.0, through: 1.0, by: 0.02).map { $0 }

    @Test func endpointsAreTheKeyframesExactly() {
        let start = WinterSky.stops(progress: 0), end = WinterSky.stops(progress: 1)
        #expect(start.first == Palette.RGB(hex: 0x5152C1))
        #expect(start.last == Palette.warmCoral)
        #expect(end.first == Palette.mangoPop)
        #expect(end.last == Palette.peachFizz)
    }

    @Test func theMiddleKeyframeIsTheSunset() {
        let mid = WinterSky.stops(progress: 0.5)
        #expect(mid.count == WinterSky.stops(progress: 0).count)
        #expect(mid.last == Palette.peachFizz)    // Sonnenuntergang: Pfirsich am Horizont
        #expect(mid.first == Palette.RGB(hex: 0xF0699F))   // … und Beeren-Pink darüber (Theme.sunset)
    }

    @Test func stopCountIsConstantAndInputIsClamped() {
        #expect(Set(steps.map { WinterSky.stops(progress: $0).count }).count == 1)
        #expect(WinterSky.stops(progress: -3) == WinterSky.stops(progress: 0))
        #expect(WinterSky.stops(progress: 42) == WinterSky.stops(progress: 1))
        #expect(WinterSky.stops(progress: .nan) == WinterSky.stops(progress: 0))
    }

    @Test func everyChannelStaysInRange() {
        for p in steps {
            for rgb in WinterSky.stops(progress: p) {
                #expect((0...1).contains(rgb.r) && (0...1).contains(rgb.g) && (0...1).contains(rgb.b), "p=\(p)")
            }
        }
    }

    @Test func skyBrightnessRisesMonotonicallyInOKLab() {
        for index in 0..<WinterSky.stops(progress: 0).count {
            var previous = -Double.infinity
            for p in steps {
                let l = WinterSky.stops(progress: p)[index].oklab.l
                #expect(l >= previous - 1e-6, "stop \(index) p=\(p)")
                previous = l
            }
        }
        // Und der Himmel wird insgesamt klar heller.
        #expect(WinterSky.stops(progress: 1)[0].oklab.l - WinterSky.stops(progress: 0)[0].oklab.l > 0.25)
    }

    @Test func gradientHasNoJumps() {
        var previous = WinterSky.stops(progress: 0)
        for p in steps.dropFirst() {
            let current = WinterSky.stops(progress: p)
            for (a, b) in zip(previous, current) { #expect(a.deltaE(to: b) < 6, "p=\(p)") }
            previous = current
        }
    }

    @Test func snowDensityFollowsTheProgress() {
        #expect(WinterSky.snowDensity(progress: 0) == 1)
        #expect(WinterSky.snowDensity(progress: 1) == 0)
        #expect(WinterSky.snowDensity(progress: -1) == 1 && WinterSky.snowDensity(progress: 7) == 0)
        var previous = 2.0
        for p in steps {
            let d = WinterSky.snowDensity(progress: p)
            #expect(d <= previous)
            previous = d
        }
    }

    @Test func flakeCountIsCappedAtFortyAndGoneAtLevelTen() {
        #expect(WinterSky.maxFlakes == 40)
        #expect(WinterSky.flakeCount(progress: 0) == 40)
        #expect(WinterSky.flakeCount(progress: 0.5) == 20)
        #expect(WinterSky.flakeCount(progress: 1) == 0)
        #expect(steps.allSatisfy { (0...40).contains(WinterSky.flakeCount(progress: $0)) })
    }

    @Test func labelNamesTheMoodOfTheSky() {
        #expect(WinterSky.mood(progress: 0) == "Winterdämmerung")
        #expect(WinterSky.mood(progress: 0.5) == "Sonnenuntergang")
        #expect(WinterSky.mood(progress: 1) == "Frühlingsmorgen")
    }
}

@Suite("Schneefall · Flocken")
struct SnowFieldTests {
    @Test func flakesAreDeterministicAndStayInsideTheCanvas() {
        let size = CGSize(width: 300, height: 180)
        for i in 0..<WinterSky.maxFlakes {
            let f = SnowField.flake(i)
            #expect(f == SnowField.flake(i))
            for t in [0.0, 1.5, 100.0, 8e8] {
                let p = SnowField.position(f, time: t, size: size)
                #expect(p.y >= 0 && p.y <= size.height && p.x >= -20 && p.x <= size.width + 20)
            }
        }
    }

    @Test func standingFlakesDoNotSway() {
        let f = SnowField.flake(3)
        let p = SnowField.position(f, time: 0, size: CGSize(width: 100, height: 100))
        #expect(abs(p.x - f.x * 100) < 1e-9)
    }
}
