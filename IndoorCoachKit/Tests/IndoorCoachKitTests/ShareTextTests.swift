import Foundation
import Testing
@testable import IndoorCoachKit

private func moment(_ kind: Moment.Kind, id: String, headline: String, detail: String? = nil) -> Moment {
    Moment(id: id, kind: kind, date: Date(timeIntervalSince1970: 1_800_000_000), headline: headline, detail: detail, rideID: 1)
}

@Suite("ShareText")
struct ShareTextTests {
    // MARK: neutral

    @Test func removesEveryKnownServiceName() {
        for name in ShareText.serviceNames {
            let result = ShareText.neutral("\(name) Sweet Spot 3×12")
            #expect(!result.localizedCaseInsensitiveContains(name), "\(name) → \(result)")
            #expect(result == "Sweet Spot 3×12", "\(name) → \(result)")
        }
    }

    @Test func serviceNameListCoversTheBigOnes() {
        for name in ["MyWhoosh", "Zwift", "Strava", "Garmin", "intervals.icu", "TrainerRoad", "TrainingPeaks", "Wahoo", "Rouvy", "Peloton"] {
            #expect(ShareText.serviceNames.contains(name), "\(name)")
        }
    }

    @Test func isCaseInsensitiveAndTidiesSeparators() {
        #expect(ShareText.neutral("MYWHOOSH – Sweet Spot 3×12") == "Sweet Spot 3×12")
        #expect(ShareText.neutral("Sweet Spot 3×12 (Zwift)") == "Sweet Spot 3×12")
        #expect(ShareText.neutral("Zwift-Fahrt am Morgen") == "Fahrt am Morgen")
        #expect(ShareText.neutral("Strava: Schwelle  2×20") == "Schwelle 2×20")
        #expect(ShareText.neutral("Von Garmin importiert") == "Von importiert")
        #expect(ShareText.neutral("intervals.icu · Grundlage") == "Grundlage")
    }

    @Test func leavesCleanTextAlone() {
        #expect(ShareText.neutral("Sweet Spot 3×12") == "Sweet Spot 3×12")
        #expect(ShareText.neutral("Level 4 · Rollen-Routine") == "Level 4 · Rollen-Routine")
        #expect(ShareText.neutral("") == "")
    }

    @Test func rideLabelFallsBackWhenOnlyTheServiceNameWasThere() {
        #expect(ShareText.rideLabel("MyWhoosh") == "Einheit")
        #expect(ShareText.rideLabel("  ") == "Einheit")
        #expect(ShareText.rideLabel("Zwift Sweet Spot 3×12") == "Sweet Spot 3×12")
    }

    // MARK: Werte

    @Test func valueFreeStripsWattsButKeepsTheMeaning() {
        #expect(ShareText.valueFree("Neue Bestleistung: 5 min · 268 W") == "Neue Bestleistung: 5 min")
        #expect(ShareText.valueFree("Deine Schwelle ist gestiegen: 231 → 238 W") == "Deine Schwelle ist gestiegen")
        #expect(ShareText.valueFree("Level 4 · Rollen-Routine") == "Level 4 · Rollen-Routine")
        #expect(ShareText.valueFree("Neue Bestleistung: 20 min · 1.020 W") == "Neue Bestleistung: 20 min")
    }

    @Test func headlineShowsValuesOnlyOnRequest() {
        let record = moment(.record, id: "record-300-1", headline: "Neue Bestleistung: 5 min · 268 W")
        #expect(ShareText.headline(for: record, showValues: false) == "Neue Bestleistung: 5 min")
        #expect(ShareText.headline(for: record, showValues: true) == "Neue Bestleistung: 5 min · 268 W")
    }

    @Test func detailDropsPerformanceNumbersWithoutTheSwitch() {
        let record = moment(.record, id: "record-300-1", headline: "h", detail: "+7 W gegenüber deiner bisherigen Bestleistung (3. Dez.)")
        #expect(ShareText.detail(for: record, showValues: false) == nil)
        #expect(ShareText.detail(for: record, showValues: true) == "+7 W gegenüber deiner bisherigen Bestleistung (3. Dez.)")
        let level = moment(.levelUp, id: "level-4-2026", headline: "Level 4 · Rollen-Routine", detail: "Etappe 4 von 10: Stilfser Joch, 2757 m")
        #expect(ShareText.detail(for: level, showValues: false) == "Etappe 4 von 10: Stilfser Joch, 2757 m")
        let ftp = moment(.ftpRise, id: "ftp-238-2026", headline: "h", detail: "geschätzt aus deiner besten 20-Minuten-Leistung, ohne Test")
        #expect(ShareText.detail(for: ftp, showValues: false) == "geschätzt aus deiner besten 20-Minuten-Leistung, ohne Test")
    }

    // MARK: Begleittext

    @Test func captionForALevelNamesTheStage() {
        let level = moment(.levelUp, id: "level-4-2026", headline: "Level 4 · Rollen-Routine")
        #expect(ShareText.caption(for: level, showValues: false) == "Gipfelmoment: Level 4 · Rollen-Routine – Etappe Stilfser Joch.")
    }

    @Test func captionForOtherKinds() {
        let record = moment(.record, id: "record-300-1", headline: "Neue Bestleistung: 5 min · 268 W")
        #expect(ShareText.caption(for: record, showValues: false) == "Gipfelmoment: Neue Bestleistung: 5 min.")
        #expect(ShareText.caption(for: record, showValues: true) == "Gipfelmoment: Neue Bestleistung: 5 min · 268 W.")
        let week = moment(.weekPlanDone, id: "week-2026-12-14", headline: "Plan der Woche geschafft · 4/4")
        #expect(ShareText.caption(for: week, showValues: false) == "Gipfelmoment: Plan der Woche geschafft · 4/4.")
    }

    @Test func captionsNeverNameAService() {
        let all = [moment(.levelUp, id: "level-4-2026", headline: "Level 4 · Rollen-Routine"),
                   moment(.record, id: "record-300-1", headline: "Neue Bestleistung: MyWhoosh 5 min · 268 W"),
                   moment(.comeback, id: "comeback-1", headline: "Du bist zurück Strava")]
        for m in all {
            for showValues in [false, true] {
                let text = ShareText.caption(for: m, showValues: showValues) + ShareText.headline(for: m, showValues: showValues)
                for name in ShareText.serviceNames { #expect(!text.localizedCaseInsensitiveContains(name), "\(name) in \(text)") }
            }
        }
    }

    @Test func levelNumberAndStageComeFromTheID() {
        #expect(ShareText.levelNumber(of: moment(.levelUp, id: "level-7-2026", headline: "h")) == 7)
        #expect(ShareText.levelNumber(of: moment(.record, id: "record-300-1", headline: "h")) == nil)
        #expect(ShareText.levelNumber(of: moment(.levelUp, id: "demo-level-4", headline: "h")) == 4)
    }
}
