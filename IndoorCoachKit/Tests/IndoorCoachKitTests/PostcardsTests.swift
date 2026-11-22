import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import IndoorCoachKit

/// Postkarten (docs/22, B2): Texte, Freischaltung, Datum, Prozent, Szene, Teilen.
@Suite("Postkarten · Inhalt")
struct PostcardsTests {
    private var de: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { de.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    /// Marken und Dienste, die auf keiner Karte stehen dürfen (docs/22, R7).
    static let forbidden = ["MyWhoosh", "Zwift", "Strava", "Garmin", "intervals", "Wahoo", "Rouvy", "Peloton", "TrainerRoad", "Komoot",
                            "Apple", "Google", "Claude", "Watt", "Puls", "FTP"]

    @Test func allTenTextsAreTheOnesFromTheConcept() {
        let texts = Postcards.all(level: 10, levelProgress: 1, levelDates: [:]).map(\.text)
        #expect(texts.count == 10)
        #expect(texts[0] == "Start in Garmisch. Die Zugspitze schaut zu, der Winter fängt gerade erst an. Der erste Tritt ist der schwerste, und der liegt hinter dir.")
        #expect(texts[1] == "Grüße vom Fernpass. Unten glitzern die Seen. Du rollst ruhig und gleichmäßig. Genau so gewinnt man einen Winter.")
        #expect(texts[2] == "Am Reschensee schaut ein Kirchturm aus dem Eis. Hier oben ist es kalt, aber deine Beine sind warm.")
        #expect(texts[3] == "48 Kehren, 2757 Meter: das Dach deiner Reise. Ab hier geht es dem Frühling entgegen.")
        #expect(texts[4] == "Bormio, die Thermen dampfen. Halbzeit. Und ab der Wintersonnenwende werden die Tage wieder länger.")
        #expect(texts[5] == "Über Aprica blinzelt die Sonne jeden Tag ein bisschen länger hinter den Gipfeln hervor.")
        #expect(texts[6] == "In Edolo tropft es von den Dächern. Tauwetter in den Bergen und in deinen Beinen.")
        #expect(texts[7] == "Der Passo Crocedomini: einsam, steil, ehrlich. Hier zeigt sich, was der Winter gebracht hat.")
        #expect(texts[8] == "Am Idrosee riecht es schon nach Frühling. Nur noch eine Etappe.")
        #expect(texts[9] == "Riva am Gardasee. Zitronenbäume, Wasser, Sonne. Du bist angekommen, in Frühlingsform.")
    }

    @Test func textsAreShortInDuFormAndFreeOfBrands() {
        for card in Postcards.all(level: 10, levelProgress: 1, levelDates: [:]) {
            #expect(card.text.count <= 160, "\(card.place): \(card.text.count) Zeichen")
            #expect(!card.text.contains("Sie ") && !card.text.contains(" Ihr"), "\(card.place)")
            for word in Self.forbidden { #expect(!card.text.localizedCaseInsensitiveContains(word), "\(card.place): \(word)") }
            #expect(!card.text.contains("!!"), "\(card.place)")
        }
    }

    @Test func greetingsCoverEveryStageAndNameThePlace() {
        for stage in WinterJourney.stages {
            let greeting = Postcards.greeting(for: stage.number)
            #expect(greeting.hasPrefix("Grüße "), "\(stage.place)")
            #expect(greeting.contains(stage.place) || (stage.place == "Gardasee" || stage.place == "Idrosee" || stage.place == "Reschen"), "\(stage.place): \(greeting)")
        }
        #expect(Postcards.greeting(for: 4) == "Grüße vom Stilfser Joch")
        #expect(Postcards.shareText(for: Postcards.all(level: 4, levelProgress: 0, levelDates: [:])[3])
                == "Grüße vom Stilfser Joch. Etappe 4 von 10 meiner Winter-Alpenüberquerung.")
    }

    @Test func shareTextNeverCarriesNumbersOfTheRider() {
        for card in Postcards.all(level: 10, levelProgress: 1, levelDates: [:]) {
            let text = Postcards.shareText(for: card)
            for word in Self.forbidden { #expect(!text.localizedCaseInsensitiveContains(word), "\(card.place): \(word)") }
        }
    }

    // MARK: Freischaltung, Datum, Prozent (Akzeptanz 1 und 2)

    @Test func levelNUnlocksOneToNWithArrivalDates() {
        let dates = [1: date(2026, 11, 1), 2: date(2026, 11, 20), 3: date(2026, 12, 2), 4: date(2026, 12, 18)]
        let cards = Postcards.all(level: 4, levelProgress: 0.62, levelDates: dates)
        #expect(cards.filter(\.unlocked).map(\.stage) == [1, 2, 3, 4])
        #expect(cards[3].arrivedOn == dates[4])
        #expect(cards[4...].allSatisfy { !$0.unlocked && $0.arrivedOn == nil })
        #expect(cards[4].percentToNext == 38)
        #expect(cards.dropFirst(5).allSatisfy { $0.percentToNext == nil })
    }

    @Test func percentNeverShowsZeroWhileTheNextCardIsStillLocked() {
        let cards = Postcards.all(level: 3, levelProgress: 0.999, levelDates: [:])
        #expect(cards[3].percentToNext == 1)
        #expect(Postcards.all(level: 3, levelProgress: 0, levelDates: [:])[3].percentToNext == 100)
    }

    @Test func garmischIsAlwaysUnlockedFromTheSeasonStart() {
        let cards = Postcards.all(level: 1, levelProgress: 0, levelDates: [1: date(2026, 11, 1)])
        #expect(cards[0].unlocked && cards[0].arrivedOn == date(2026, 11, 1))
        #expect(Postcards.unlockedCount(in: cards) == 1)
        #expect(Postcards.all(level: 7, levelProgress: 0.5, levelDates: [:]).filter(\.unlocked).count == 7)
    }

    // MARK: Teilen, Lesen, Zusatz

    @Test func albumTitleCountsTheCards() {
        let cards = Postcards.all(level: 4, levelProgress: 0.62, levelDates: [:])
        #expect(Postcards.albumTitle(cards) == "Deine Postkarten · 4 von 10")
        #expect(Postcards.albumSubtitle(cards) == "Noch 38 % bis Bormio")
        #expect(Postcards.albumSubtitle(Postcards.all(level: 10, levelProgress: 1, levelDates: [:])) == "Alle zehn Karten gesammelt: Du bist am Gardasee.")
    }

    @Test func unlockedCardIsReadAsOnePostcardWithDateAndText() {
        let cards = Postcards.all(level: 4, levelProgress: 0.62, levelDates: [4: date(2026, 12, 18)])
        let spoken = Postcards.accessibilityLabel(cards[3], calendar: de)
        #expect(spoken == "Postkarte, Etappe 4 von 10, Stilfser Joch, 2757 Meter, angekommen am 18. Dezember. Text: \(cards[3].text)")
    }

    @Test func unlockedCardWithoutADateOmitsIt() {
        let card = Postcards.all(level: 1, levelProgress: 0, levelDates: [:])[0]
        let spoken = Postcards.accessibilityLabel(card, calendar: de)
        #expect(!spoken.contains("angekommen"))
        #expect(spoken.hasPrefix("Postkarte, Etappe 1 von 10, Garmisch, 708 Meter."))
    }

    @Test func lockedCardsAnnounceThePercentOnlyOnTheNextOne() {
        let cards = Postcards.all(level: 4, levelProgress: 0.62, levelDates: [:])
        #expect(Postcards.accessibilityLabel(cards[4], calendar: de) == "Postkarte, Etappe 5 von 10, Bormio. Noch nicht erreicht, noch 38 Prozent bis Bormio.")
        #expect(Postcards.accessibilityLabel(cards[7], calendar: de) == "Postkarte, Etappe 8 von 10, Crocedomini. Noch nicht erreicht.")
        #expect(Postcards.lockedCaption(cards[4]) == "Noch 38 % bis Bormio")
        #expect(Postcards.lockedCaption(cards[7]) == "Noch nicht erreicht")
    }

    @Test func stampAndPostmarkTexts() {
        let card = Postcards.all(level: 4, levelProgress: 0.62, levelDates: [4: date(2026, 12, 18)])[3]
        #expect(Postcards.postmarkDate(card, calendar: de) == "18. DEZ. 2026")
        #expect(Postcards.postmarkDate(Postcards.all(level: 1, levelProgress: 0, levelDates: [:])[0], calendar: de) == nil)
        #expect(Postcards.stampLabel(card) == "Etappe 4/10")
    }

    @Test func gardasseCardCarriesTheRidersOwnSentenceVerbatim() {
        let line = Postcards.whyAddendum(note: "Im Mai die RTF mit Freunden", savedOn: date(2026, 11, 4), calendar: de)
        #expect(line == "Dein Satz vom 4. November: „Im Mai die RTF mit Freunden“")
        #expect(Postcards.whyAddendum(note: "Im Mai die RTF mit Freunden", savedOn: nil, calendar: de) == "Dein Satz: „Im Mai die RTF mit Freunden“")
        #expect(Postcards.whyAddendum(note: nil, savedOn: date(2026, 11, 4), calendar: de) == nil)
        #expect(Postcards.whyAddendum(note: "  ", savedOn: nil, calendar: de) == nil)
    }

    @Test func onlyTheLastCardShowsTheAddendum() {
        let cards = Postcards.all(level: 10, levelProgress: 1, levelDates: [:])
        #expect(Postcards.showsWhy(cards[9]) && cards[..<9].allSatisfy { !Postcards.showsWhy($0) })
        let locked = Postcards.all(level: 9, levelProgress: 0.1, levelDates: [:])[9]
        #expect(!Postcards.showsWhy(locked))   // erst wenn die Karte da ist
    }
}

@Suite("Postkarten · Szene")
struct PostcardSceneTests {
    @Test func snowShrinksAndTheSunClimbsWithTheSeasonProgress() {
        let steps = stride(from: 0.0, through: 1.0, by: 0.1).map { $0 }
        for stage in 1...10 {
            var snow = 2.0, sun = -1.0
            for p in steps {
                let g = PostcardScene.geometry(stage: stage, seasonProgress: p)
                #expect(g.snowCoverage <= snow, "stage \(stage) p=\(p)")
                #expect(g.sunHeight >= sun, "stage \(stage) p=\(p)")
                snow = g.snowCoverage
                sun = g.sunHeight
            }
        }
    }

    @Test func valuesStayInRangeAndAreDeterministic() {
        for stage in 0...11 {
            for p in [-1.0, 0, 0.3, 1, 5] {
                let g = PostcardScene.geometry(stage: stage, seasonProgress: p)
                #expect((0...1).contains(g.snowCoverage) && (0...1).contains(g.sunHeight) && (0...1).contains(g.peakHeight))
                #expect(g.ridgeFront.allSatisfy { (0...1).contains($0) } && g.ridgeBack.allSatisfy { (0...1).contains($0) })
                #expect(g == PostcardScene.geometry(stage: stage, seasonProgress: p))
            }
        }
    }

    @Test func peakHeightFollowsTheElevationOfTheStage() {
        let heights = (1...10).map { PostcardScene.geometry(stage: $0, seasonProgress: 0).peakHeight }
        #expect(heights.firstIndex(of: heights.max()!) == 3)   // Stilfser Joch, 2757 m
        #expect(heights[9] == heights.min())                   // Gardasee, 65 m
    }

    @Test func eachStageDrawsItsOwnSilhouette() {
        let ridges = (1...10).map { PostcardScene.geometry(stage: $0, seasonProgress: 0.5).ridgeFront }
        #expect(Set(ridges.map { $0.map { String(format: "%.3f", $0) }.joined(separator: ",") }).count == 10)
        #expect(ridges.allSatisfy { $0.count == PostcardScene.ridgePoints })
    }

    @Test func skyAndSeasonLookComeFromTheStagePosition() {
        #expect(PostcardScene.seasonProgress(stage: 1) == 0)
        #expect(PostcardScene.seasonProgress(stage: 10) == 1)
        #expect(abs(PostcardScene.seasonProgress(stage: 4) - 1.0 / 3.0) < 1e-9)
    }

    @Test func everyStageHasAMotif() {
        for stage in 1...10 { #expect(PostcardScene.motif(for: stage) != .none, "stage \(stage)") }
        #expect(PostcardScene.motif(for: 3) == .churchTowerInLake)
        #expect(PostcardScene.motif(for: 4) == .serpentineRoad)
        #expect(PostcardScene.motif(for: 10) == .lemonTree)
    }
}

@MainActor
@Suite("Postkarten · Teilen-Bild")
struct PostcardShareImageTests {
    private func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    @Test func shareImageIsFifteenHundredByThousand() throws {
        #expect(PostcardShareCard.size == CGSize(width: 1500, height: 1000))
        let card = Postcards.all(level: 4, levelProgress: 0.5, levelDates: [:])[3]
        let rendered = try #require(PostcardShareRenderer.render(card))
        #expect(pixelSize(of: rendered.url) == CGSize(width: 1500, height: 1000))
        #expect(rendered.url.lastPathComponent == "IndoorCoach-Postkarte-4-Stilfser-Joch.png")
        try? FileManager.default.removeItem(at: rendered.url)
    }

    @Test func fileNamesAreSafeForEveryStage() {
        for card in Postcards.all(level: 10, levelProgress: 1, levelDates: [:]) {
            let name = PostcardShareRenderer.filename(for: card)
            #expect(name.hasSuffix(".png") && !name.contains(" ") && !name.contains("/"), "\(name)")
        }
    }
}
