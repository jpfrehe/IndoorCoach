import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Erholungskontext (W4-C)")
struct RecoverySummaryTests {
    func answers(legs: CheckIn.Level = .ok, sleep: CheckIn.Level = .ok, mood: CheckIn.Level = .ok, tags: Set<CheckIn.Tag> = []) -> CheckIn.Answers {
        CheckIn.Answers(legs: legs, sleep: sleep, mood: mood, tags: tags)
    }

    let wellness = RecoveryWellness(sleepRecentHours: 6.43, sleepBaselineHours: 7.61,
                                    restingHRRecent: 54.0, restingHRBaseline: 49.0,
                                    hrvRecent: 41.3, hrvBaseline: 58.7, trendGuardActive: true)

    func fullInput() -> RecoverySummary.Input {
        .init(wellness: wellness,
              checkIns: [answers(legs: .bad), answers(legs: .bad), answers(tags: [.infekt]), answers()],
              warmup: .falling)
    }

    @Test func leereEingabeGibtNil() {
        #expect(RecoverySummary.make(.init()) == nil)
        #expect(RecoverySummary.make(.init(checkIns: [answers(), answers()])) != nil)   // Check-ins ohne Auffälligkeit sind eine Aussage
    }

    @Test func relativeWerteGerundet() throws {
        let s = try #require(RecoverySummary.make(fullInput()))
        #expect(s.sleepDeltaHours == -1.0)        // −1,18 h → auf 0,5 gerundet
        #expect(s.restingHRDeltaBpm == 5)
        #expect(s.hrv == .below)
        #expect(s.warmup == .falling)
        #expect(s.trendGuardActive)
        #expect(s.checkIns.legsHeavy == 2)
        #expect(s.checkIns.infection == 1)
    }

    @Test func hrvTrendSchwellen() {
        func t(_ r: Double) -> RecoverySummary.HRVTrend? {
            RecoverySummary.make(.init(wellness: .init(hrvRecent: r, hrvBaseline: 50)))?.hrv
        }
        #expect(t(40) == .below)
        #expect(t(50) == .within)
        #expect(t(54) == .within)
        #expect(t(60) == .above)
    }

    @Test func aufwaermCheckRichtungen() {
        func w(_ d: WarmupCheck.Trend.Direction) -> RecoverySummary.WarmupTrend? {
            RecoverySummary.make(.init(checkIns: [answers()], warmup: d))?.warmup
        }
        #expect(w(.stable) == .stable)
        #expect(w(.falling) == .falling)
        #expect(w(.rising) == .higher)
        #expect(w(.notEnough) == nil)
    }

    @Test func textEnthaeltNurRelativeAussagen() throws {
        let text = try #require(RecoverySummary.make(fullInput())).promptLines.joined(separator: "\n")
        #expect(text.contains("2× Beine schwer"))
        #expect(text.contains("1× Infekt"))
        #expect(text.contains("Ruhepuls"))
        #expect(text.contains("Trend-Wächter"))
        #expect(text.contains("Aufwärm-Check"))
    }

    @Test func verboteneInhalteLandenNieImText() throws {
        let text = try #require(RecoverySummary.make(fullInput())).promptLines.joined(separator: "\n").lowercased()
        // Rohwerte
        for raw in ["6,43", "6.43", "7,61", "7.61", "54 bpm", "49 bpm", "41,3", "58,7", "41.3", "58.7"] {
            #expect(!text.contains(raw), "Rohwert \(raw)")
        }
        // Gerätenamen
        for device in ["garmin", "wahoo", "polar", "apple watch", "whoop", "oura", "fitbit", "suunto", "coros", "iphone", "kickr", "h10"] {
            #expect(!text.contains(device), "Gerät \(device)")
        }
        // Diagnosebegriffe
        for term in ["diagnose", "übertraining", "burnout", "krankheit", "erkrankung", "arrhythm", "apnoe", "depress", "herz-kreislauf", "syndrom"] {
            #expect(!text.contains(term), "Diagnose \(term)")
        }
    }

    @Test func textBleibtKurzBeiAllenKombinationen() throws {
        let all = CheckIn.Level.allCases.flatMap { l in CheckIn.Level.allCases.map { answers(legs: l, sleep: l, mood: $0, tags: Set(CheckIn.Tag.allCases)) } }
        let text = try #require(RecoverySummary.make(.init(checkIns: all))).promptLines.joined(separator: "\n")
        #expect(text.count < 400)
    }

    @Test func schlafUndRuhepulsImNormalbereich() throws {
        let s = try #require(RecoverySummary.make(.init(wellness: .init(sleepRecentHours: 7.5, sleepBaselineHours: 7.6,
                                                                       restingHRRecent: 50, restingHRBaseline: 50))))
        let text = s.promptLines.joined(separator: "\n")
        #expect(text.contains("Schlaf: wie gewohnt"))
        #expect(text.contains("Ruhepuls: wie gewohnt"))
    }

    // MARK: Prompt

    func context(recovery: RecoverySummary?) -> PlanContext {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        var ctx = PlanContext(profile: AthleteProfile(), today: today, horizonStart: today,
                              horizonEnd: cal.date(byAdding: .day, value: 6, to: today)!, load: nil, weeks: [],
                              recentRides: [], alreadyPlanned: [], wish: "")
        ctx.recovery = recovery
        return ctx
    }

    @Test func abschnittNurWennGesetzt() throws {
        #expect(!PlanPrompt.userMessage(context(recovery: nil)).contains("Erholung (14 Tage, relativ)"))
        let msg = PlanPrompt.userMessage(context(recovery: RecoverySummary.make(fullInput())))
        #expect(msg.contains("## Erholung (14 Tage, relativ)"))
        #expect(msg.contains("2× Beine schwer"))
    }

    @Test func systemPromptRegelErholung() {
        let s = PlanPrompt.system
        #expect(s.contains("Erholung"))
        #expect(s.contains("konservativer"))
        #expect(s.contains("keine Diagnosen"))
    }

    @Test func planContextOhneRecoveryAbwaertskompatibel() {
        #expect(context(recovery: nil).recovery == nil)
    }
}
