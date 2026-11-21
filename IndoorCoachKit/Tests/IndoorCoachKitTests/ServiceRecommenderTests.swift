import Foundation
import Testing
@testable import IndoorCoachKit

/// docs/20-KONZEPT-ONBOARDING-DIENSTE.md §5: Empfehlungslogik der Einführung (AP1, Fälle T1–T20 und §5.6).
@Suite("ServiceRecommender")
struct ServiceRecommenderTests {
    // MARK: Helfer

    static let all = ServiceAvailability(intervalsOAuth: true, bridgeDownload: true, health: true)

    static func answers(rides: Set<RideApp> = [], device: RideDevice? = nil, extras: Set<ExtraGear> = [],
                        showAll: Bool = false) -> ServiceAnswers {
        ServiceAnswers(rideApps: rides, myWhooshDevice: device, extras: extras, showAll: showAll)
    }

    static func recommend(_ answers: ServiceAnswers, _ availability: ServiceAvailability = all) -> [ServiceRecommendation] {
        ServiceRecommender.recommend(answers, availability)
    }

    /// Reihenfolge innerhalb einer Stufe (§5.5).
    static let order: [ConnectionID] = [.myWhoosh, .intervalsICU, .macBridge, .appleHealth, .strap, .fitImport, .strava]

    static func tier(_ id: ConnectionID, in list: [ServiceRecommendation]) -> RecommendationTier? {
        list.first { $0.id == id }?.tier
    }

    static func entry(_ id: ConnectionID, in list: [ServiceRecommendation]) -> ServiceRecommendation? {
        list.first { $0.id == id }
    }

    static func ids(_ tier: RecommendationTier, in list: [ServiceRecommendation]) -> [ConnectionID] {
        list.filter { $0.tier == tier }.map(\.id)
    }

    // MARK: T1, Leerfälle

    @Test func t1_emptyAnswersRecommendNothing() {
        let list = Self.recommend(Self.answers())
        #expect(ids(.recommended, list).isEmpty && ids(.optional, list).isEmpty && ids(.advanced, list).isEmpty)
        #expect(Set(ids(.more, list)) == Set(Self.order))   // 5 Dienste + FIT + Strava
        #expect(list.count == 7)
        #expect(list.allSatisfy { $0.reasons == [.catalog] })
    }

    private func ids(_ tier: RecommendationTier, _ list: [ServiceRecommendation]) -> [ConnectionID] { Self.ids(tier, in: list) }

    @Test func noneAnswersOnlyYieldMore() {
        let list = Self.recommend(Self.answers(rides: [.none], extras: [.none]))
        #expect(list.allSatisfy { $0.tier == .more })
        #expect(list.count == 7)
    }

    // MARK: T2–T5 (MyWhoosh und Mac-Brücke)

    @Test func t2_sabineMyWhooshOnMac() {
        let list = Self.recommend(Self.answers(rides: [.myWhoosh], device: .mac, extras: [.none]))
        #expect(ids(.recommended, list) == [.myWhoosh, .macBridge])
        #expect(Self.entry(.myWhoosh, in: list)?.reasons == [.myWhooshPlansAndRides])
        #expect(Self.entry(.macBridge, in: list)?.reasons == [.bridgeMac])
    }

    @Test func t3_noBridgeDownloadHidesTheBridgeEverywhere() {
        let availability = ServiceAvailability(intervalsOAuth: true, bridgeDownload: false, health: true)
        let answers = Self.answers(rides: [.myWhoosh], device: .mac)
        let list = Self.recommend(answers, availability)
        #expect(Self.entry(.macBridge, in: list) == nil)
        #expect(!ServiceRecommender.asksDevice(answers, availability))
    }

    @Test func t4_unknownDeviceMakesTheBridgeOptional() {
        for device in [nil, RideDevice.unknown] {
            let list = Self.recommend(Self.answers(rides: [.myWhoosh], device: device))
            #expect(Self.tier(.macBridge, in: list) == .optional)
            #expect(Self.entry(.macBridge, in: list)?.reasons == [.bridgeMaybeMac])
        }
    }

    @Test(arguments: [RideDevice.windows, .tablet, .appleTV, .phone])
    func t5_otherDevicesNeverRecommendTheBridge(device: RideDevice) {
        let list = Self.recommend(Self.answers(rides: [.myWhoosh], device: device, extras: [.appleWatch]))
        #expect(ids(.recommended, list) == [.myWhoosh, .appleHealth])
        #expect(Self.tier(.macBridge, in: list) == .more)
        #expect(Self.entry(.macBridge, in: list)?.reasons == [.catalog])
    }

    // MARK: T6–T8 (intervals.icu)

    @Test func t6_tobiasZwiftWithStrava() throws {
        let list = Self.recommend(Self.answers(rides: [.zwift], extras: [.strava]))
        let intervals = try #require(Self.entry(.intervalsICU, in: list))
        #expect(intervals.tier == .recommended && intervals.reasons == [.intervalsZwift])
        #expect(intervals.note?.contains("Zwift") == true && intervals.note?.contains("Strava") == true)
        let strava = try #require(Self.entry(.strava, in: list))
        #expect(strava.tier == .advanced && strava.reasons == [.stravaAdvanced] && strava.note == nil)
    }

    @Test func intervalsNoteOnlyForZwiftOrRouvyWithStrava() {
        let without = Self.recommend(Self.answers(rides: [.zwift]))
        #expect(Self.entry(.intervalsICU, in: without)?.note == nil)
        let rouvy = Self.recommend(Self.answers(rides: [.rouvy], extras: [.strava]))
        #expect(Self.entry(.intervalsICU, in: rouvy)?.note?.contains("Rouvy") == true)
        #expect(Self.entry(.intervalsICU, in: rouvy)?.note?.contains("Zwift") == false)
    }

    @Test func t7_zwiftWithoutOAuthFallsBackToFiles() {
        let availability = ServiceAvailability(intervalsOAuth: false, bridgeDownload: true, health: true)
        for rides in [Set<RideApp>([.zwift]), [.rouvy]] {
            let list = Self.recommend(Self.answers(rides: rides), availability)
            #expect(Self.entry(.intervalsICU, in: list) == nil)
            #expect(Self.tier(.fitImport, in: list) == .optional)
            #expect(Self.entry(.fitImport, in: list)?.reasons == [.fitNoIntervals])
        }
    }

    @Test func t8_zwiftRouvyAndGarminShareOneIntervalsEntry() throws {
        let list = Self.recommend(Self.answers(rides: [.zwift, .rouvy], extras: [.garminWahoo]))
        #expect(list.filter { $0.id == .intervalsICU }.count == 1)
        let intervals = try #require(Self.entry(.intervalsICU, in: list))
        #expect(intervals.tier == .recommended)
        #expect(intervals.reasons == [.intervalsZwift, .intervalsRouvy, .intervalsDevice])
        #expect(intervals.benefit == "Damit landen deine Einheiten automatisch in Zwift, in Rouvy und auf deinem Garmin- oder Wahoo-Radcomputer.")
    }

    @Test func intervalsSentenceUsesOnlyTheNamedTargets() throws {
        let zwiftGarmin = Self.recommend(Self.answers(rides: [.zwift], extras: [.garminWahoo]))
        #expect(Self.entry(.intervalsICU, in: zwiftGarmin)?.benefit
                == "Damit landen deine Einheiten automatisch in Zwift und auf deinem Garmin- oder Wahoo-Radcomputer.")
        let zwiftOnly = Self.recommend(Self.answers(rides: [.zwift]))
        #expect(Self.entry(.intervalsICU, in: zwiftOnly)?.benefit == "Damit landen deine Einheiten automatisch in Zwift.")
    }

    // MARK: T9, T10 (Personen)

    @Test func t9_claudiaWithoutAnApp() throws {
        let list = Self.recommend(Self.answers(rides: [.none], extras: [.garminWahoo, .heartStrap, .strava]))
        #expect(ids(.recommended, list) == [.appleHealth, .strap])
        #expect(Self.entry(.appleHealth, in: list)?.reasons == [.healthGarmin])
        let intervals = try #require(Self.entry(.intervalsICU, in: list))
        #expect(intervals.tier == .optional && intervals.reasons == [.intervalsDevice])
        #expect(Self.tier(.strava, in: list) == .advanced)
    }

    @Test func t10_murat() {
        let list = Self.recommend(Self.answers(rides: [.none], extras: [.heartStrap]))
        #expect(ids(.recommended, list) == [.strap])
        #expect(ids(.optional, list).isEmpty && ids(.advanced, list).isEmpty)
        #expect(ids(.more, list).count == list.count - 1)
    }

    // MARK: T11 (alle Dienste zeigen)

    @Test func t11_showAllIgnoresAnswers() {
        let list = Self.recommend(Self.answers(rides: [.myWhoosh], device: .mac, extras: [.strava, .heartStrap], showAll: true))
        #expect(ids(.recommended, list).isEmpty)
        #expect(Set(ids(.optional, list)) == [.myWhoosh, .intervalsICU, .macBridge, .appleHealth, .strap, .fitImport])
        #expect(ids(.advanced, list) == [.strava])
        #expect(ids(.more, list).isEmpty)
        #expect(list.filter { $0.tier == .optional }.allSatisfy { $0.reasons == [.catalog] })
        #expect(Self.entry(.strava, in: list)?.reasons == [.stravaAdvanced])
    }

    @Test func showAllRespectsAvailability() {
        let availability = ServiceAvailability(intervalsOAuth: false, bridgeDownload: false, health: false)
        let list = Self.recommend(Self.answers(showAll: true), availability)
        #expect(Set(list.map(\.id)) == [.myWhoosh, .strap, .fitImport, .strava])
    }

    // MARK: T12, T13 (Normalisierung)

    @Test func t12_noneIsDroppedNextToConcreteAnswers() {
        let mixed = Self.answers(rides: [.none, .zwift], extras: [.none, .heartStrap])
        let normalized = ServiceRecommender.normalized(mixed)
        #expect(normalized.rideApps == [.zwift] && normalized.extras == [.heartStrap])
        let a = Self.recommend(mixed)
        let b = Self.recommend(Self.answers(rides: [.zwift], extras: [.heartStrap]))
        #expect(a == b)
    }

    @Test func noneAloneStaysNone() {
        let normalized = ServiceRecommender.normalized(Self.answers(rides: [.none], extras: [.none]))
        #expect(normalized.rideApps == [.none] && normalized.extras == [.none])
    }

    @Test func t13_deviceWithoutMyWhooshIsDropped() {
        #expect(ServiceRecommender.normalized(Self.answers(device: .mac)).myWhooshDevice == nil)
        #expect(ServiceRecommender.normalized(Self.answers(rides: [.zwift], device: .mac)).myWhooshDevice == nil)
        #expect(ServiceRecommender.normalized(Self.answers(rides: [.myWhoosh, .zwift], device: .mac)).myWhooshDevice == .mac)
        // Ein veralteter Wert ändert die Empfehlung nicht.
        #expect(Self.recommend(Self.answers(rides: [.zwift], device: .mac)) == Self.recommend(Self.answers(rides: [.zwift])))
    }

    @Test func showAllKeepsTheAnswersStored() {
        let answers = Self.answers(rides: [.zwift], extras: [.strava], showAll: true)
        #expect(ServiceRecommender.normalized(answers) == answers)
    }

    // MARK: T14 (Obergrenze)

    @Test func t14_atMostFourRecommendations() {
        let list = Self.recommend(Self.answers(rides: [.myWhoosh, .zwift], device: .mac, extras: [.appleWatch, .heartStrap]))
        #expect(ServiceRecommender.maxRecommended == 4)
        #expect(ids(.recommended, list) == [.myWhoosh, .intervalsICU, .macBridge, .appleHealth])
        #expect(Self.tier(.strap, in: list) == .optional)
        #expect(Self.entry(.strap, in: list)?.reasons == [.strapPulse])
    }

    @Test func fitImportIsNeverRecommended() {
        let availability = ServiceAvailability(intervalsOAuth: false, bridgeDownload: true, health: true)
        let list = Self.recommend(Self.answers(rides: [.zwift, .rouvy, .other]), availability)
        #expect(Self.tier(.fitImport, in: list) == .optional)
    }

    // MARK: T15, T16

    @Test func t15_noHealthMeansNoHealthEntry() {
        let availability = ServiceAvailability(intervalsOAuth: true, bridgeDownload: true, health: false)
        let list = Self.recommend(Self.answers(extras: [.appleWatch, .garminWahoo]), availability)
        #expect(Self.entry(.appleHealth, in: list) == nil)
        #expect(Self.recommend(Self.answers(showAll: true), availability).allSatisfy { $0.id != .appleHealth })
    }

    @Test func t16_otherApp() {
        let list = Self.recommend(Self.answers(rides: [.other]))
        #expect(Self.entry(.intervalsICU, in: list)?.tier == .optional)
        #expect(Self.entry(.intervalsICU, in: list)?.reasons == [.intervalsOther])
        #expect(Self.entry(.fitImport, in: list)?.tier == .optional)
        #expect(Self.entry(.fitImport, in: list)?.reasons == [.fitOther])
        #expect(ids(.recommended, list).isEmpty)
    }

    @Test func healthWatchAndGarminAreMergedIntoOneSentence() throws {
        let both = Self.recommend(Self.answers(extras: [.appleWatch, .garminWahoo]))
        let entry = try #require(Self.entry(.appleHealth, in: both))
        #expect(entry.reasons == [.healthWatch, .healthGarmin])
        #expect(entry.benefit.contains("Apple Watch") && entry.benefit.contains("Garmin Connect"))
        #expect(entry.benefit != Self.entry(.appleHealth, in: Self.recommend(Self.answers(extras: [.appleWatch])))?.benefit)
    }

    // MARK: T17 (Sortierung)

    @Test func t17_outputIsSortedByTierThenOrderWithoutDuplicates() {
        let samples: [ServiceAnswers] = [
            Self.answers(), Self.answers(rides: [.myWhoosh, .zwift, .rouvy, .other], device: .mac,
                                         extras: [.appleWatch, .garminWahoo, .heartStrap, .strava]),
            Self.answers(rides: [.other], extras: [.strava]), Self.answers(showAll: true),
            Self.answers(rides: [.myWhoosh], device: .tablet, extras: [.heartStrap])
        ]
        let availabilities = [Self.all, ServiceAvailability(intervalsOAuth: false, bridgeDownload: false, health: false)]
        for answers in samples {
            for availability in availabilities {
                let list = Self.recommend(answers, availability)
                #expect(Set(list.map(\.id)).count == list.count)
                let keys = list.map { $0.tier.rawValue * 100 + Self.order.firstIndex(of: $0.id)! }
                #expect(keys == keys.sorted())
                #expect(list.filter { $0.tier == .recommended }.count <= ServiceRecommender.maxRecommended)
                for entry in list { #expect(Set(entry.reasons).count == entry.reasons.count && !entry.reasons.isEmpty) }
            }
        }
    }

    @Test func tierIsComparable() {
        #expect(RecommendationTier.recommended < .optional && .optional < .advanced && .advanced < .more)
    }

    // MARK: T18 (germanList)

    @Test(arguments: [([String](), ""), (["A"], "A"), (["A", "B"], "A und B"), (["A", "B", "C"], "A, B und C"),
                      (["A", "B", "C", "D"], "A, B, C und D")])
    func t18_germanList(items: [String], expected: String) {
        #expect(Formatters.germanList(items) == expected)
    }

    // MARK: T19 (Texte)

    /// Jede mögliche Kombination liefert genau einen Satz ohne Fachwörter.
    @Test func t19_everyBenefitIsOneSentenceWithoutJargon() {
        let rideSets: [Set<RideApp>] = [[], [.none], [.myWhoosh], [.zwift], [.rouvy], [.other], [.zwift, .rouvy], [.myWhoosh, .zwift, .other]]
        let extraSets: [Set<ExtraGear>] = [[], [.none], [.appleWatch], [.garminWahoo], [.heartStrap], [.strava],
                                           [.appleWatch, .garminWahoo, .heartStrap, .strava]]
        let availabilities = [Self.all, ServiceAvailability(intervalsOAuth: false, bridgeDownload: true, health: true)]
        var checked = 0
        for rides in rideSets {
            for extras in extraSets {
                for showAll in [false, true] {
                    for availability in availabilities {
                        let answers = Self.answers(rides: rides, device: .mac, extras: extras, showAll: showAll)
                        for entry in Self.recommend(answers, availability) {
                            assertOneSentence(entry.benefit)
                            if let note = entry.note { assertOneSentence(note, allowsLeadIn: true) }
                            checked += 1
                        }
                    }
                }
            }
        }
        #expect(checked > 100)
    }

    private func assertOneSentence(_ text: String, allowsLeadIn: Bool = false) {
        #expect(text.hasSuffix("."), "\(text)")
        // Abkürzungen („z. B.“) zählen nicht als Satzende.
        let body = text.replacingOccurrences(of: "z. B.", with: "zB").dropLast()
        if !allowsLeadIn { #expect(!body.contains(". ") && !body.contains("!") && !body.contains("?"), "\(text)") }
        for word in ["API", "OAuth", "FIT", "Token", "Client"] { #expect(!text.contains(word), "\(text) enthält \(word)") }
    }

    @Test func benefitsAreGermanAndStartWithACapital() {
        for entry in Self.recommend(Self.answers(showAll: true)) {
            #expect(entry.benefit.first?.isUppercase == true)
            #expect(entry.benefit.count > 20 && entry.benefit.count < 200)
        }
    }

    // MARK: T20 (asksDevice)

    @Test func t20_asksDeviceOnlyForMyWhooshWithBridge() {
        let noBridge = ServiceAvailability(intervalsOAuth: true, bridgeDownload: false, health: true)
        let cases: [(ServiceAnswers, ServiceAvailability, Bool)] = [
            (Self.answers(rides: [.myWhoosh]), Self.all, true),
            (Self.answers(rides: [.myWhoosh, .zwift]), Self.all, true),
            (Self.answers(rides: [.myWhoosh]), noBridge, false),
            (Self.answers(rides: [.myWhoosh], showAll: true), Self.all, false),
            (Self.answers(rides: [.zwift]), Self.all, false),
            (Self.answers(rides: [.rouvy, .other]), Self.all, false),
            (Self.answers(rides: [.none]), Self.all, false),
            (Self.answers(), Self.all, false)
        ]
        for (answers, availability, expected) in cases {
            #expect(ServiceRecommender.asksDevice(answers, availability) == expected)
        }
    }

    // MARK: Weitere Randfälle (§5.6)

    @Test func inconsistentStoredAnswersBehaveLikeNormalized() {
        let stored = Self.answers(rides: [.none, .myWhoosh], device: .mac, extras: [.none, .appleWatch])
        #expect(Self.recommend(stored) == Self.recommend(ServiceRecommender.normalized(stored)))
        #expect(ids(.recommended, Self.recommend(stored)) == [.myWhoosh, .macBridge, .appleHealth])
    }

    @Test func stravaAloneIsAdvancedNeverRecommended() {
        let list = Self.recommend(Self.answers(extras: [.strava]))
        #expect(Self.tier(.strava, in: list) == .advanced)
        #expect(ids(.recommended, list).isEmpty)
        #expect(Self.tier(.strava, in: Self.recommend(Self.answers(extras: [.strava], showAll: true))) == .advanced)
    }

    @Test func healthWatchPlusMyWhooshAndNoHealthShowsNoError() {
        let availability = ServiceAvailability(intervalsOAuth: true, bridgeDownload: true, health: false)
        let list = Self.recommend(Self.answers(rides: [.myWhoosh], device: .mac, extras: [.appleWatch]), availability)
        #expect(ids(.recommended, list) == [.myWhoosh, .macBridge])
    }

    @Test func answersAreCodable() throws {
        let answers = Self.answers(rides: [.myWhoosh, .zwift], device: .mac, extras: [.appleWatch, .heartStrap], showAll: true)
        let decoded = try JSONDecoder().decode(ServiceAnswers.self, from: JSONEncoder().encode(answers))
        #expect(decoded == answers)
    }

    @Test func connectionIDIsCodable() throws {
        let data = try JSONEncoder().encode(ConnectionID.macBridge)
        #expect(String(decoding: data, as: UTF8.self) == "\"macBridge\"")
        #expect(try JSONDecoder().decode(Set<ConnectionID>.self, from: JSONEncoder().encode(Set(ConnectionID.allCases))) == Set(ConnectionID.allCases))
    }
}
