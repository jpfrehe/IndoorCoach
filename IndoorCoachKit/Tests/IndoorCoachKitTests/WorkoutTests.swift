import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Workout domain")
struct WorkoutTests {
    let sweetSpot = WorkoutDefinition(
        title: "Sweet Spot 3×12",
        type: .sweetSpot,
        summary: "Drei lange Sweet-Spot-Blöcke",
        segments: [
            .warmup(10, from: 0.45, to: 0.75),
            .intervals(3, on: 720, at: 0.9, off: 300, at: 0.55),
            .cooldown(8, from: 0.65, to: 0.4)
        ]
    )

    @Test func totalDurationSumsSegmentsIncludingIntervals() {
        // 10 min + 3 × (12 + 5) min + 8 min = 69 min
        #expect(sweetSpot.totalDuration == 69 * 60)
    }

    @Test func intervalsAreUnrolledIntoOnOffSteps() {
        let steps = sweetSpot.steps
        #expect(steps.count == 1 + 6 + 1)
        #expect(steps[1].startPower == 0.9)
        #expect(steps[2].isRecovery)
        #expect(steps.last!.start + steps.last!.duration == sweetSpot.totalDuration)
    }

    @Test func steadyHourAtFTPIsHundredTSS() {
        let ftpHour = WorkoutDefinition(title: "FTP", type: .test, summary: "", segments: [.steady(60, at: 1.0)])
        #expect(abs(ftpHour.intensityFactor - 1.0) < 0.0001)
        #expect(abs(ftpHour.estimatedTSS - 100) < 0.01)
    }

    @Test func sweetSpotTSSIsPlausible() {
        // A 69-minute sweet-spot session lands roughly between 65 and 85 TSS.
        #expect((65...85).contains(sweetSpot.estimatedTSS))
    }

    @Test func intervalDurationIsRecomputedWhenInconsistent() {
        var seg = Segment.intervals(5, on: 60, at: 1.2, off: 60, at: 0.5)
        seg.duration = 1 // inconsistent input, e.g. from an LLM
        #expect(seg.effectiveDuration == 600)
    }

    @Test func zonesFollowCogganBoundaries() {
        #expect(PowerZone(fractionOfFTP: 0.50) == .z1)
        #expect(PowerZone(fractionOfFTP: 0.56) == .z2)
        #expect(PowerZone(fractionOfFTP: 0.90) == .z3)
        #expect(PowerZone(fractionOfFTP: 0.95) == .z4)
        #expect(PowerZone(fractionOfFTP: 1.10) == .z5)
        #expect(PowerZone(fractionOfFTP: 1.30) == .z6)
        #expect(PowerZone(fractionOfFTP: 2.00) == .z7)
    }

    @Test func timeInZonesCoversTheWholeWorkout() {
        let total = sweetSpot.timeInZones().values.reduce(0, +)
        #expect(total == sweetSpot.totalDuration)
    }

    @Test func segmentCodingUsesRepeatKey() throws {
        let json = #"{"kind":"intervals","duration":0,"repeat":4,"onDuration":240,"offDuration":180,"onPower":1.12,"offPower":0.5}"#
        let seg = try JSONDecoder().decode(Segment.self, from: Data(json.utf8))
        #expect(seg.repeatCount == 4)
        #expect(seg.effectiveDuration == 4 * 420)
    }

    @Test func plainTextDescriptionShowsWatts() {
        let text = sweetSpot.plainTextDescription(ftp: 250)
        #expect(text.contains("3× 12 min @ 90 % (225 W)"))
        #expect(text.contains("Einfahren 10 min"))
    }

    @Test func durationFormatting() {
        #expect(Formatters.duration(0) == "0 min")
        #expect(Formatters.duration(45) == "45 s")
        #expect(Formatters.duration(600) == "10 min")
        #expect(Formatters.duration(90) == "1:30 min")
        #expect(Formatters.duration(3900) == "1:05 h")
    }
}

@Suite("ZWO export")
struct ZWOExporterTests {
    let workout = WorkoutDefinition(
        title: "VO2 5×4 <hart> & kurz",
        type: .vo2max,
        summary: "Kurz & knackig",
        segments: [
            .warmup(10, from: 0.45, to: 0.75),
            .intervals(5, on: 240, at: 1.15, off: 240, at: 0.5, cadence: 100, text: "Hohe Trittfrequenz"),
            .steady(5, at: 0.6),
            .freeRide(2),
            .cooldown(5, from: 0.6, to: 0.4)
        ]
    )

    @Test func producesWellFormedXML() throws {
        let xml = ZWOExporter.xml(for: workout)
        let doc = try XMLDocument(xmlString: xml)
        #expect(doc.rootElement()?.name == "workout_file")
        let steps = try doc.nodes(forXPath: "/workout_file/workout/*")
        #expect(steps.map(\.name) == ["Warmup", "IntervalsT", "SteadyState", "FreeRide", "Cooldown"])
    }

    @Test func escapesSpecialCharacters() {
        let xml = ZWOExporter.xml(for: workout)
        #expect(xml.contains("<name>VO2 5×4 &lt;hart&gt; &amp; kurz</name>"))
    }

    @Test func intervalAttributesUseDotDecimals() {
        let xml = ZWOExporter.xml(for: workout)
        #expect(xml.contains(#"<IntervalsT Repeat="5" OnDuration="240" OffDuration="240" OnPower="1.15" OffPower="0.50" Cadence="100">"#))
        #expect(xml.contains(#"<textevent timeoffset="0" message="Hohe Trittfrequenz"/>"#))
    }

    @Test func cooldownRunsFromHighToLowInZwoOrder() {
        let xml = ZWOExporter.xml(for: workout)
        #expect(xml.contains(#"<Cooldown Duration="300" PowerLow="0.60" PowerHigh="0.40"/>"#))
    }

    @Test func fileNameIsSafe() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 18
        let date = Calendar.current.date(from: comps)!
        #expect(ZWOExporter.fileName(for: workout, date: date) == "2026-11-18_VO2_5_4_hart_kurz.zwo")
    }
}
