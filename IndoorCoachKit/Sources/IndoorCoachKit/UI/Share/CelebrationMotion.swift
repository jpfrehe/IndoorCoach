import SwiftUI

/// Gemeinsame Bewegung aller Begeisterungs-Elemente (docs/22 §4): genau zwei Kurven, bei „Bewegung reduzieren“
/// nur eine Überblendung von 0,2 s, bei Stromsparmodus keine laufenden Partikel.
enum CelebrationMotion {
    enum Curve: CaseIterable {
        /// `.spring(duration: 0.5, bounce: 0.25)` – Erscheinen, Skalieren, Umblättern.
        case spring
        /// `.smooth(duration: 0.25)` – Einblenden von Texten und Karten.
        case smooth
    }

    /// Ersatz für beide Kurven bei „Bewegung reduzieren“.
    static let reducedFade = Animation.easeInOut(duration: 0.2)

    static func animation(_ curve: Curve, reduceMotion: Bool) -> Animation {
        if reduceMotion { return reducedFade }
        switch curve {
        case .spring: return .spring(duration: 0.5, bounce: 0.25)
        case .smooth: return .smooth(duration: 0.25)
        }
    }

    /// Partikel und Schnee laufen nur, wenn weder „Bewegung reduzieren“ noch der Stromsparmodus aktiv ist.
    static func allowsParticleMotion(reduceMotion: Bool, lowPowerMode: Bool) -> Bool { !reduceMotion && !lowPowerMode }

    static func allowsParticleMotion(reduceMotion: Bool) -> Bool {
        allowsParticleMotion(reduceMotion: reduceMotion, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}
