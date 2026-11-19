import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Morgenmessung HRV")
struct MorningHRVTests {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()
    static let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 7, minute: 30))!

    /// Schläge mit leichter, gültiger Variation (Differenzen 20 ms).
    static func goodRR(count: Int = 70) -> [Double] { (0..<count).map { 850 + ($0 % 2 == 0 ? 0 : 20) } }

    static func m(daysAgo: Int, ln: Double) -> MorningHRV.Measurement {
        let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysAgo, to: now)!)
        return .init(day: day, lnRMSSD: ln, beats: 70, quality: 1, measuredAt: day.addingTimeInterval(7 * 3600))
    }

    // MARK: Auswertung

    @Test("Gültige Messung liefert lnRMSSD für heute")
    func valid() {
        guard case .valid(let m) = MorningHRV.evaluate(rr: Self.goodRR(), now: Self.now, calendar: Self.cal) else {
            Issue.record("erwartet gültig"); return
        }
        #expect(abs(m.lnRMSSD - log(20)) < 0.001)
        #expect(m.day == Self.cal.startOfDay(for: Self.now))
        #expect(m.beats == 70)
    }

    @Test("Weniger als 40 Schläge wird verworfen")
    func tooFewBeats() {
        #expect(MorningHRV.evaluate(rr: Self.goodRR(count: 39), now: Self.now, calendar: Self.cal) == .discarded(.tooFewBeats))
        if case .valid = MorningHRV.evaluate(rr: Self.goodRR(count: 40), now: Self.now, calendar: Self.cal) {} else {
            Issue.record("40 Schläge reichen")
        }
    }

    @Test("Qualität unter 80 % wird verworfen")
    func lowQuality() {
        var rr = Self.goodRR(count: 100)
        for i in stride(from: 0, to: 100, by: 4) { rr[i] = 250 } // 25 % Artefakte
        #expect(MorningHRV.evaluate(rr: rr, now: Self.now, calendar: Self.cal) == .discarded(.lowQuality))
        var ok = Self.goodRR(count: 100)
        for i in stride(from: 0, to: 100, by: 10) { ok[i] = 250 } // 10 %
        if case .valid = MorningHRV.evaluate(rr: ok, now: Self.now, calendar: Self.cal) {} else { Issue.record("90 % reicht") }
    }

    @Test("Leere Folge: zu wenige Schläge")
    func empty() {
        #expect(MorningHRV.evaluate(rr: [], now: Self.now, calendar: Self.cal) == .discarded(.tooFewBeats))
    }

    // MARK: Pro Tag eine Messung

    @Test("Zweite Messung am Tag ersetzt die erste")
    func oneDay() {
        let a = Self.m(daysAgo: 0, ln: 3.0)
        var b = Self.m(daysAgo: 0, ln: 3.5)
        b.measuredAt = a.measuredAt.addingTimeInterval(600)
        let list = MorningHRV.upserting(b, into: [Self.m(daysAgo: 1, ln: 3.1), a], now: Self.now, calendar: Self.cal)
        #expect(list.count == 2)
        #expect(list.first { $0.day == a.day }?.lnRMSSD == 3.5)
    }

    @Test("Messungen älter als 28 Tage werden gekappt")
    func prune() {
        let list = MorningHRV.upserting(Self.m(daysAgo: 0, ln: 3), into: [Self.m(daysAgo: 60, ln: 3)], now: Self.now, calendar: Self.cal)
        #expect(list.count == 1)
    }

    // MARK: Trend

    @Test("Unter 3 Messungen in 7 Tagen: kein Trend, Signal nil")
    func noTrend() {
        let list = [Self.m(daysAgo: 0, ln: 3), Self.m(daysAgo: 2, ln: 3)]
        #expect(MorningHRV.trend(list, now: Self.now, calendar: Self.cal) == nil)
        #expect(MorningHRV.signalBelowBaseline(list, now: Self.now, calendar: Self.cal) == nil)
        #expect(MorningHRV.measurementsUntilTrend(list, now: Self.now, calendar: Self.cal) == 1)
    }

    /// Basis: Werte um 3.5 (SD ca. 0.1); letzte Woche `recent`.
    static func series(recent: Double) -> [MorningHRV.Measurement] {
        let base = (7...27).map { m(daysAgo: $0, ln: 3.5 + ($0 % 2 == 0 ? 0.1 : -0.1)) }
        let week = [0, 1, 3].map { m(daysAgo: $0, ln: recent) }
        return base + week
    }

    @Test("Status im üblichen Bereich")
    func usual() throws {
        let t = try #require(MorningHRV.trend(Self.series(recent: 3.5), now: Self.now, calendar: Self.cal))
        #expect(t.status == .usual)
        #expect(MorningHRV.signalBelowBaseline(Self.series(recent: 3.5), now: Self.now, calendar: Self.cal) == false)
    }

    @Test("Status unter dem üblichen Bereich")
    func below() throws {
        let list = Self.series(recent: 3.0)
        let t = try #require(MorningHRV.trend(list, now: Self.now, calendar: Self.cal))
        #expect(t.status == .below)
        #expect(t.weekCount == 3)
        #expect(MorningHRV.signalBelowBaseline(list, now: Self.now, calendar: Self.cal) == true)
    }

    @Test("Status über dem üblichen Bereich")
    func above() throws {
        let t = try #require(MorningHRV.trend(Self.series(recent: 4.0), now: Self.now, calendar: Self.cal))
        #expect(t.status == .above)
        #expect(MorningHRV.signalBelowBaseline(Self.series(recent: 4.0), now: Self.now, calendar: Self.cal) == false)
    }

    @Test("Trendtext: nur Trend, keine Ampelwörter")
    func texts() {
        for s in [MorningHRV.Status.below, .usual, .above] {
            #expect(!s.text.lowercased().contains("rot"))
            #expect(s.text.contains("7-Tage"))
        }
    }

    // MARK: Speicher + AppModel

    private func tempStore() -> MorningHRVStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mhrv-\(UUID().uuidString).json")
        return MorningHRVStore(url: url, defaults: UserDefaults(suiteName: "mhrv-\(UUID().uuidString)")!)
    }

    @Test("Speicher: Ersetzen pro Tag, Opt-in, Reset")
    func store() {
        let s = tempStore()
        #expect(s.enabled == false)
        s.enabled = true
        s.save(Self.m(daysAgo: 0, ln: 3.2), now: Self.now, calendar: Self.cal)
        s.save(Self.m(daysAgo: 0, ln: 3.4), now: Self.now, calendar: Self.cal)
        #expect(s.measurements().count == 1)
        #expect(s.measurements().first?.lnRMSSD == 3.4)
        #expect(s.hasMeasurement(on: Self.now, calendar: Self.cal))
        s.reset()
        #expect(s.measurements().isEmpty)
        #expect(s.enabled == false)
    }

    @MainActor
    @Test("AppModel: Signal nil ohne Opt-in und ohne Trend; Reset löscht")
    func appModel() throws {
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "mhrv-\(UUID().uuidString)")!)
        let store = tempStore()
        #expect(model.morningHRVSignal(store: store, now: Self.now) == nil)
        Self.series(recent: 3.0).forEach { store.save($0, now: Self.now, calendar: Self.cal) }
        #expect(model.morningHRVSignal(store: store, now: Self.now) == nil) // nicht aktiviert
        store.enabled = true
        #expect(model.morningHRVSignal(store: store, now: Self.now) == true)
        model.resetMorningHRVState(store: store)
        #expect(store.measurements().isEmpty)
        #expect(model.morningHRVSignal(store: store, now: Self.now) == nil)
    }

    @Test("Messfenster: 60 s, Fortschritt")
    func window() {
        #expect(MorningHRV.duration == 60)
        #expect(MorningHRV.progress(elapsed: 30) == 0.5)
        #expect(MorningHRV.progress(elapsed: 90) == 1)
    }

    @Test("Heute fällig: nur vor 11 Uhr")
    func due() {
        let s = tempStore()
        s.enabled = true
        let early = Self.cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10, minute: 59))!
        let late = Self.cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 11))!
        #expect(s.isDue(now: early, calendar: Self.cal))
        #expect(!s.isDue(now: late, calendar: Self.cal))
        s.save(Self.m(daysAgo: 0, ln: 3), now: Self.now, calendar: Self.cal)
        #expect(!s.isDue(now: early, calendar: Self.cal))
    }
}
