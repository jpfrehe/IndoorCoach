import ImageIO
import SwiftUI
import Testing
@testable import IndoorCoachKit

@Suite("Gipfelmoment · Feier (AP3)")
struct CelebrationParticlesTests {
    @Test func fortyDeterministicParticles() {
        let a = CelebrationParticles.make()
        #expect(a.count == 40)
        #expect(a == CelebrationParticles.make())
        #expect(Set(a.map(\.x)).count > 30) // verteilt, nicht gestapelt
    }

    @Test func particlesStayInsideTheScreenAtAnyTime() {
        for p in CelebrationParticles.make() {
            for t in stride(from: 0.0, through: 3.0, by: 0.1) {
                let f = CelebrationParticles.frame(of: p, at: t)
                #expect((0...1).contains(f.x) && f.y >= -0.1 && f.y <= 1, "t=\(t) x=\(f.x) y=\(f.y)")
                #expect((0...1).contains(f.progress) && (0...1).contains(f.opacity) && f.radius > 0)
            }
        }
    }

    @Test func flakesTurnIntoSparksAndThenStandStill() {
        for p in CelebrationParticles.make() {
            let times = stride(from: 0.0, through: 2.0, by: 0.05).map { CelebrationParticles.frame(of: p, at: $0) }
            #expect(zip(times, times.dropFirst()).allSatisfy { $0.progress <= $1.progress }) // Weiß → Gold, nie zurück
            #expect(zip(times, times.dropFirst()).allSatisfy { $0.y <= $1.y + 1e-9 })         // fällt nur
            #expect(times.last?.progress == 1)
            // nach der Dauer keine Bewegung mehr: keine Schleife
            #expect(CelebrationParticles.frame(of: p, at: CelebrationParticles.duration) == CelebrationParticles.frame(of: p, at: 60))
        }
        #expect(CelebrationParticles.duration == 1.2)
    }

    @Test func colorRunsFromWhiteToMango() {
        let m = Palette.mangoPop
        #expect(CelebrationParticles.color(progress: 0) == Color(red: 1, green: 1, blue: 1))
        #expect(CelebrationParticles.color(progress: 1) == Color(red: m.r, green: m.g, blue: m.b))
    }
}

@MainActor
@Suite("Gipfelmoment · Teilen-Bild (AP3)")
struct MomentShareImageTests {
    private func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    @Test func cardIsStoryFormat() throws {
        #expect(MomentShareCard.size == CGSize(width: 1080, height: 1920))
        let card = MomentShareCard(headline: "Level 4 · Rollen-Routine", detail: "Etappe 4 von 10: Stilfser Joch, 2757 m",
                                   symbol: "figure.indoor.cycle", dateText: "Fr., 18. Dez.", name: nil, skyProgress: 0.33)
        let rendered = try #require(ShareImageRenderer.render(card, size: MomentShareCard.size, filename: "moment-test.png"))
        #expect(pixelSize(of: rendered.url) == CGSize(width: 1080, height: 1920))
        try? FileManager.default.removeItem(at: rendered.url)
    }

    @Test func cardRendersWithAllOptionalLinesAndWithNone() throws {
        for (detail, name) in [(String?.none, String?.none), ("Zeile", "Sabine")] {
            let card = MomentShareCard(headline: "Neue Bestleistung: 20 min · 268 W und ein sehr langer Zusatz, der umbrechen muss",
                                       detail: detail, symbol: "trophy", dateText: "Fr., 18. Dez.", name: name, skyProgress: 1)
            let rendered = try #require(ShareImageRenderer.render(card, size: MomentShareCard.size, filename: "moment-test-\(name ?? "x").png"))
            #expect(pixelSize(of: rendered.url) == CGSize(width: 1080, height: 1920))
            try? FileManager.default.removeItem(at: rendered.url)
        }
    }
}

@Suite("Gipfelmoment · Helfer (AP3)")
struct MomentStyleTests {
    @Test func everyKindHasASymbolAndLevelsUseTheirOwn() {
        for kind in Moment.Kind.allCases {
            let m = Moment(id: kind == .levelUp ? "level-4-2026" : "x", kind: kind, date: .now, headline: "h")
            #expect(!MomentStyle.symbol(for: m).isEmpty)
        }
        #expect(MomentStyle.symbol(for: Moment(id: "level-4-2026", kind: .levelUp, date: .now, headline: "h")) == WinterArc.levels[3].symbol)
        #expect(MomentStyle.symbol(for: Moment(id: "level-99-2026", kind: .levelUp, date: .now, headline: "h")) == WinterArc.levels[9].symbol)
    }

    @Test func dateTextIsGermanAndShort() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let date = cal.date(from: DateComponents(year: 2026, month: 12, day: 18, hour: 12))!
        #expect(MomentStyle.dateText(date, calendar: cal) == "Fr., 18. Dez.")
    }

    @Test func onlyMeasuredMomentsCarryASourceChip() {
        func chip(_ kind: Moment.Kind) -> String? { MomentStyle.sourceChip(for: Moment(id: "x", kind: kind, date: .now, headline: "h")) }
        #expect(chip(.record) == "gemessen · Sekundendaten")
        #expect(chip(.ftpRise) == "geschätzt · Sekundendaten")
        #expect(chip(.levelUp) == nil)
    }

    @Test func newTrophyDotCoversSevenDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func trophy(_ ago: Double?) -> Trophy {
            Trophy(id: "t", kind: .record, title: "T", condition: "c", detail: nil, symbol: "trophy", earnedOn: ago.map { now.addingTimeInterval(-$0 * 86_400) })
        }
        #expect(NewTrophyDot.isNew(trophy(0), now: now))
        #expect(NewTrophyDot.isNew(trophy(7), now: now))
        #expect(!NewTrophyDot.isNew(trophy(7.1), now: now))
        #expect(!NewTrophyDot.isNew(trophy(nil), now: now))
        #expect(!NewTrophyDot.isNew(trophy(-1), now: now)) // nie aus der Zukunft
    }

    @Test func greetingOnlyWithNameAndEverySecondTime() {
        var ledger = MomentLedger()
        #expect(MomentGreeting.make(name: "Sabine", ledger: ledger) == "Stark, Sabine.")
        #expect(MomentGreeting.make(name: "  ", ledger: ledger) == nil)
        ledger.markSeen("level-2-2026")
        #expect(MomentGreeting.make(name: "Sabine", ledger: ledger) == nil)
        ledger.markSeen("level-3-2026")
        #expect(MomentGreeting.make(name: "Sabine", ledger: ledger) == "Stark, Sabine.")
    }

    @Test func demoExamplesAreMarkedAndNamedByKind() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for kind in DemoMoments.kinds {
            let batch = DemoMoments.example(kind, now: now)
            #expect(!batch.isEmpty)
            #expect(batch.moments.allSatisfy(DemoMoments.isExample))
        }
        #expect(DemoMoments.example("levelUp", now: now).headline?.kind == .levelUp)
        #expect(DemoMoments.example("record", now: now).headline?.kind == .record)
        #expect(DemoMoments.example("comeback", now: now).headline?.kind == .comeback)
        #expect(DemoMoments.example("week", now: now).headline?.kind == .weekPlanDone)
        #expect(DemoMoments.example("unbekannt", now: now).headline?.kind == .levelUp)
        for kind in DemoMoments.kinds {
            let note = DemoMoments.coachNote(for: DemoMoments.example(kind, now: now), now: now)
            #expect(note != nil && !note!.source.isEmpty)
        }
    }
}
