import Foundation
import Observation
import SwiftData

/// Secret storage abstraction (Keychain on device, in-memory for previews/snapshots/tests).
public protocol SecretStore: AnyObject, Sendable {
    func secret(_ key: Keychain.Key) -> String?
    func setSecret(_ value: String?, for key: Keychain.Key)
    var tokenStore: StravaTokenStore { get }
}

public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    let keychain = Keychain()
    public init() {}
    public func secret(_ key: Keychain.Key) -> String? { keychain.string(key) }
    public func setSecret(_ value: String?, for key: Keychain.Key) { keychain.set(value, for: key) }
    public var tokenStore: StravaTokenStore { KeychainStravaTokenStore(keychain: keychain) }
}

public final class InMemorySecretStore: SecretStore, StravaTokenStore, @unchecked Sendable {
    private var values: [Keychain.Key: String] = [:]
    private var tokens: StravaTokens?
    private let lock = NSLock()
    public init() {}
    public func secret(_ key: Keychain.Key) -> String? { lock.withLock { values[key] } }
    public func setSecret(_ value: String?, for key: Keychain.Key) { lock.withLock { values[key] = value } }
    public var tokenStore: StravaTokenStore { self }
    public func loadTokens() -> StravaTokens? { lock.withLock { tokens } }
    public func saveTokens(_ tokens: StravaTokens?) { lock.withLock { self.tokens = tokens } }
}

public struct Banner: Identifiable, Equatable {
    public let id = UUID()
    public var message: String
    public var isError: Bool
}

@MainActor
@Observable
public final class AppModel {
    // MARK: Settings
    public var profile: AthleteProfile { didSet { persistProfile() } }
    public var stravaClientID: String { didSet { defaults.set(stravaClientID, forKey: Keys.stravaClientID) } }

    // MARK: State
    public private(set) var stravaAthleteName: String?
    public private(set) var isStravaConnected = false
    public private(set) var hasClaudeKey = false
    public private(set) var hasStravaSecret = false
    public private(set) var isSyncing = false
    public private(set) var isPlanning = false
    public private(set) var lastSync: Date?
    public var banner: Banner?
    public var proposal: PlanProposal?
    /// Set by "Plan erstellen" outside the Plan tab; PlanView opens the planner and resets it.
    public var plannerRequested = false
    /// Not observed: filled lazily from view bodies, must not trigger re-renders.
    @ObservationIgnored private var seriesCache: (key: Int, series: FitnessFreshness.Series)?
    public private(set) var proposalSource: WorkoutSource = .demo

    public let context: ModelContext
    let secrets: SecretStore
    let myWhooshStore: MyWhooshSessionStore
    let myWhoosh: MyWhooshClient
    /// Signed-in MyWhoosh account (e-mail) or nil.
    public private(set) var myWhooshUser: String?
    public private(set) var isSendingToMyWhoosh = false
    public var isMyWhooshConnected: Bool { myWhooshUser != nil }
    let defaults: UserDefaults
    let calendarService: CalendarService
    let transport: HTTPTransport

    enum Keys {
        static let profile = "profile.v1"
        static let stravaClientID = "strava.clientID"
        static let lastSync = "strava.lastSync"
    }

    public init(context: ModelContext, secrets: SecretStore, defaults: UserDefaults = .standard,
                transport: HTTPTransport = URLSessionTransport(),
                myWhooshStore: MyWhooshSessionStore = KeychainMyWhooshSessionStore()) {
        self.context = context
        self.secrets = secrets
        self.defaults = defaults
        self.transport = transport
        self.myWhooshStore = myWhooshStore
        self.myWhoosh = MyWhooshClient(store: myWhooshStore, transport: transport)
        self.calendarService = CalendarService()
        if let data = defaults.data(forKey: Keys.profile), let p = try? JSONDecoder().decode(AthleteProfile.self, from: data) {
            profile = p
        } else {
            profile = AthleteProfile()
        }
        stravaClientID = defaults.string(forKey: Keys.stravaClientID) ?? ""
        lastSync = defaults.object(forKey: Keys.lastSync) as? Date
        refreshCredentialState()
        // Exported .zwo files are only needed while the share sheet is open.
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("zwo"))
    }

    // MARK: - Credentials

    public func refreshCredentialState() {
        let tokens = secrets.tokenStore.loadTokens()
        isStravaConnected = tokens != nil
        stravaAthleteName = tokens?.athleteName
        hasClaudeKey = !(secrets.secret(.claudeAPIKey) ?? "").isEmpty
        hasStravaSecret = !(secrets.secret(.stravaClientSecret) ?? "").isEmpty
        myWhooshUser = myWhooshStore.loadSession()?.username
    }

    // MARK: - MyWhoosh (B21, unofficial API)

    /// Signs in; only the session is kept (Keychain), never the password.
    @discardableResult
    public func connectMyWhoosh(username: String, password: String) async -> Bool {
        do {
            try await myWhoosh.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
            refreshCredentialState()
            show("Mit MyWhoosh verbunden.", error: false)
            return true
        } catch {
            show(error.localizedDescription, error: true)
            return false
        }
    }

    public func disconnectMyWhoosh() async {
        await myWhoosh.logout()
        refreshCredentialState()
    }

    /// Uploads (or replaces) the workouts as MyWhoosh custom workouts and puts each on its day in the MyWhoosh calendar.
    public func sendToMyWhoosh(_ workouts: [StoredWorkout]) async {
        let ids = workouts.map(\.persistentModelID)
        guard !ids.isEmpty, !isSendingToMyWhoosh else { return }
        isSendingToMyWhoosh = true
        defer { isSendingToMyWhoosh = false; try? context.save() }
        do {
            var batch: [(id: PersistentIdentifier, payload: MyWhooshWorkout, start: Date, tss: Int, summary: String)] = []
            for id in ids {
                guard let w = context.model(for: id) as? StoredWorkout, !w.isDeleted else { continue }
                // Replace an earlier upload instead of creating duplicates.
                if let old = w.myWhooshWorkoutID { try? await myWhoosh.delete(workoutID: old) }
                if let task = w.myWhooshTaskID { try? await myWhoosh.deleteTask(task) }
                let payload = MyWhooshMapper.workout(for: w.definition, id: "ic-\(w.id.uuidString.lowercased())", ftp: profile.ftp)
                batch.append((id, payload, startDate(for: w), payload.TSS, w.summary))
            }
            try await myWhoosh.upload(batch.map(\.payload))
            var scheduled = 0
            for item in batch {
                let taskID = try? await myWhoosh.schedule(workoutID: item.payload.Id, name: item.payload.Name, description: item.summary,
                                                         start: item.start, durationSeconds: item.payload.Time, tss: item.tss)
                if let w = context.model(for: item.id) as? StoredWorkout, !w.isDeleted {
                    w.myWhooshWorkoutID = item.payload.Id
                    w.myWhooshTaskID = taskID
                    w.myWhooshSentAt = .now
                    if taskID != nil { scheduled += 1 }
                }
            }
            let what = batch.count == 1 ? "Einheit" : "\(batch.count) Einheiten"
            show(scheduled == batch.count ? "\(what) an MyWhoosh gesendet und im MyWhoosh-Kalender eingetragen."
                                          : "\(what) an MyWhoosh gesendet (unter „Custom Workouts“).", error: false)
        } catch {
            refreshCredentialState()
            show(error.localizedDescription, error: true)
        }
    }

    public func setClaudeAPIKey(_ key: String) {
        secrets.setSecret(key, for: .claudeAPIKey)
        refreshCredentialState()
    }

    public func setStravaClientSecret(_ secret: String) {
        secrets.setSecret(secret, for: .stravaClientSecret)
        refreshCredentialState()
    }

    public var isDemoMode: Bool { !isStravaConnected }

    var stravaConfig: StravaConfig {
        StravaConfig(clientID: stravaClientID.trimmingCharacters(in: .whitespaces),
                     clientSecret: secrets.secret(.stravaClientSecret) ?? "")
    }

    var stravaClient: StravaClient {
        StravaClient(config: stravaConfig, store: secrets.tokenStore, transport: transport)
    }

    // MARK: - Demo data

    /// Seeds demo rides (and a demo plan) when nothing is connected, so every screen has content.
    public func bootstrap() {
        #if DEBUG
        var rideDays = 84
        switch applyUITestSeed() {
        case "empty": return
        case "heavy": rideDays = 730
        default: break
        }
        #else
        let rideDays = 84
        #endif
        guard isDemoMode else { return }
        let count = (try? context.fetchCount(FetchDescriptor<StoredRide>())) ?? 0
        guard count == 0 else { return }
        for ride in DemoData.rides(days: rideDays, ftp: profile.ftp) {
            context.insert(StoredRide(ride, isDemo: true))
        }
        let ctx = planContext(wish: "", startToday: true)
        let plan = DemoCoach.makePlan(ctx)
        for w in plan.workouts {
            context.insert(StoredWorkout(proposal: w, source: .demo, weekFocus: plan.weekFocus))
        }
        try? context.save()
    }

    #if DEBUG
    private var uiSeedApplied = false

    /// UI-audit hook (Debug only): launch with `-uiSeed demo|empty|heavy` to wipe the store and profile
    /// and start from a known state. Returns the applied seed, or nil.
    private func applyUITestSeed() -> String? {
        guard !uiSeedApplied, let seed = UserDefaults.standard.string(forKey: "uiSeed") else { return nil }
        uiSeedApplied = true
        try? context.delete(model: StoredRide.self)
        try? context.delete(model: StoredWorkout.self)
        try? context.save()
        profile = AthleteProfile()
        stravaClientID = ""
        // Debug-only: start without Claude key / Strava secret (Strava tokens are left untouched).
        secrets.setSecret(nil, for: .claudeAPIKey)
        secrets.setSecret(nil, for: .stravaClientSecret)
        refreshCredentialState()
        return seed
    }
    #endif

    /// Removes the seeded demo rides and demo plan. Real rides and workouts the user accepted stay
    /// (accepted DemoCoach plans are stored as `.manual`, see `acceptProposal`).
    public func resetDemoData() {
        deleteDemoData()
        try? context.save()
    }

    private func deleteDemoData() {
        try? context.delete(model: StoredRide.self, where: #Predicate { $0.isDemo })
        try? context.delete(model: StoredWorkout.self, where: #Predicate { $0.sourceRaw == "demo" })
    }

    // MARK: - Strava

    /// Runs OAuth via the provided web-auth closure (ASWebAuthenticationSession in the UI layer).
    public func connectStrava(authenticate: (URL) async throws -> URL) async {
        let config = stravaConfig
        guard config.isComplete else {
            show(StravaError.notConfigured.localizedDescription, error: true); return
        }
        let state = UUID().uuidString
        do {
            let callback = try await authenticate(config.authorizeURL(state: state))
            let tokens = try await stravaClient.completeAuthorization(callbackURL: callback, expectedState: state)
            refreshCredentialState()
            show("Mit Strava verbunden\(tokens.athleteName.map { " als \($0)" } ?? "").", error: false)
            resetDemoData()
            await syncStrava(full: true)
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    public func disconnectStrava() async {
        await stravaClient.disconnect()
        try? context.delete(model: StoredRide.self)
        try? context.save()
        defaults.removeObject(forKey: Keys.lastSync)
        lastSync = nil
        refreshCredentialState()
        bootstrap()
        show("Strava getrennt – Demo-Daten aktiv.", error: false)
    }

    /// Incremental sync (overlap of 2 days to catch edits); full sync loads 120 days.
    public func syncStrava(full: Bool = false) async {
        guard isStravaConnected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let since: Date
        if !full, let lastSync {
            since = lastSync.addingTimeInterval(-7 * 86_400) // late uploads; upsert makes overlap cheap
        } else {
            // 210 days so the 42-day fitness average is warmed up before the visible 90-day window.
            since = Calendar.current.date(byAdding: .day, value: -210, to: .now)!
        }
        do {
            let rides = try await stravaClient.fetchRides(after: since)
            // Leftover demo data (e.g. tokens restored without the connect flow) goes with the first real sync.
            if try context.fetchCount(FetchDescriptor<StoredRide>(predicate: #Predicate { $0.isDemo })) > 0 {
                deleteDemoData()
            }
            let existing = try context.fetch(FetchDescriptor<StoredRide>())
            var byID = Dictionary(existing.map { ($0.stravaID, $0) }, uniquingKeysWith: { first, _ in first })
            for ride in rides {
                if let stored = byID[ride.id] { stored.update(from: ride) }
                else {
                    let stored = StoredRide(ride)
                    context.insert(stored)
                    byID[ride.id] = stored
                }
            }
            linkCompletedWorkouts()
            try context.save()
            lastSync = .now
            defaults.set(lastSync, forKey: Keys.lastSync)
            show(rides.isEmpty ? "Strava: keine neuen Fahrten." : "Strava: \(rides.count) Fahrten synchronisiert.", error: false)
        } catch {
            refreshCredentialState()
            show(error.localizedDescription, error: true)
        }
    }

    /// Marks past planned workouts as done when a ride exists on the same day.
    func linkCompletedWorkouts() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let workouts = try? context.fetch(FetchDescriptor<StoredWorkout>()),
              let rides = try? context.fetch(FetchDescriptor<StoredRide>()) else { return }
        for w in workouts where w.status == .planned && w.date <= today {
            let sameDay = rides.filter { calendar.isDate($0.startDate, inSameDayAs: w.date) }
            if let ride = sameDay.first(where: { $0.summary.isIndoor }) ?? sameDay.first {
                w.status = .done
                w.linkedRideID = ride.stravaID
            }
        }
    }

    // MARK: - Data access

    public func allRides() -> [RideSummary] {
        let descriptor = FetchDescriptor<StoredRide>(sortBy: [SortDescriptor(\.startDate)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.summary)
    }

    /// Full Fitness & Freshness series (warmed up over all rides) – one model for Heute, the F&F screen,
    /// the Winter Arc and the coach.
    public func fitnessSeries(rides: [RideSummary], now: Date = .now) -> FitnessFreshness.Series {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: now)
        // Several views ask for the same series per render (and per scrub step) – cache on all inputs.
        var hasher = Hasher()
        hasher.combine(rides)
        hasher.combine(end)
        hasher.combine(profile.ftp)
        hasher.combine(profile.thresholdHeartRate)
        hasher.combine(profile.restingHeartRate)
        hasher.combine(profile.maxHeartRate)
        let key = hasher.finalize()
        if let cached = seriesCache, cached.key == key { return cached.series }
        let first = rides.map(\.startDate).min() ?? end
        let series = FitnessFreshness.series(rides: rides, ftp: profile.ftp, heartRate: profile.heartRateProfile,
                                             thresholdHeartRate: profile.thresholdHeartRate, from: min(first, end), to: end,
                                             calendar: calendar)
        seriesCache = (key, series)
        return series
    }

    public func loadSeries(rides: [RideSummary], days: Int = 90, now: Date = .now) -> [TrainingLoad.DayLoad] {
        fitnessSeries(rides: rides, now: now).points.suffix(days)
            .map { TrainingLoad.DayLoad(date: $0.date, tss: $0.load, ctl: $0.fitness, atl: $0.fatigue, tsb: $0.form) }
    }

    // MARK: - Relative Effort & Winter Arc

    public func relativeEffort(for ride: RideSummary) -> RelativeEffort.Estimate {
        RelativeEffort.estimate(for: ride, heartRate: profile.heartRateProfile)
    }

    public struct EffortWeek: Hashable, Sendable, Identifiable {
        public var weekStart: Date
        public var total: Double
        public var id: Date { weekStart }
    }

    /// Relative Effort per ISO week, oldest first, including the current week.
    public func effortWeeks(rides: [RideSummary], count: Int = 8, now: Date = .now) -> [EffortWeek] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: current) }
        var totals = Dictionary(uniqueKeysWithValues: starts.map { ($0, 0.0) })
        for ride in rides {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: ride.startDate)?.start, totals[week] != nil else { continue }
            totals[week]! += relativeEffort(for: ride).value ?? 0
        }
        return starts.map { EffortWeek(weekStart: $0, total: totals[$0] ?? 0) }
    }

    public func winterArc(rides: [RideSummary], now: Date = .now) -> WinterArc.Status? {
        let calendar = Calendar.current
        let season = WinterArc.defaultSeason(containing: now, calendar: calendar)
        let start = calendar.startOfDay(for: profile.arcStart ?? season.start)
        // The general goal date only counts when it is a plausible spring target for this arc (≤ 8 months);
        // a past or far-away race date would otherwise hide or stretch the arc.
        let latest = calendar.date(byAdding: .month, value: 8, to: start) ?? season.goal
        let goal = calendar.startOfDay(for: profile.goalDate.flatMap { $0 > start && $0 <= latest ? $0 : nil } ?? season.goal)
        guard goal > start else { return nil }
        let points = fitnessSeries(rides: rides, now: now).points
        let startCTL = points.last(where: { $0.date <= start })?.fitness ?? points.first?.fitness ?? 0
        let current = points.last?.fitness ?? 0
        let best = points.filter { $0.date >= start }.map(\.fitness).max() ?? current
        // Completed full weeks since the start: drop the running week and a partial first week.
        var weeks = TrainingLoad.weeks(rides: rides.filter { $0.startDate >= start }, ftp: profile.ftp,
                                       from: start, to: now, calendar: calendar)
        if !weeks.isEmpty { weeks.removeLast() }
        if let first = weeks.first, first.weekStart < start { weeks.removeFirst() }
        return WinterArc.status(start: start, goal: goal, today: now, startCTL: startCTL, currentCTL: current,
                                bestCTLSinceStart: best, targetCTL: profile.targetCTL,
                                weeklyHours: weeks.map { Double($0.seconds) / 3600 }, weeklyBudgetHours: profile.weeklyHours,
                                calendar: calendar)
    }

    /// Saves the athlete's Perceived Exertion for a ride (local only; a Strava sync never overwrites it).
    public func setPerceivedExertion(_ value: Int?, prefer: Bool, rideID: Int) {
        let descriptor = FetchDescriptor<StoredRide>(predicate: #Predicate { $0.stravaID == rideID })
        guard let ride = try? context.fetch(descriptor).first else { return }
        let preferValue = value != nil && prefer
        guard ride.perceivedExertion != value || ride.preferPerceivedExertion != preferValue else { return }
        ride.perceivedExertion = value
        ride.preferPerceivedExertion = value != nil && prefer
        try? context.save()
    }

    // MARK: - Planning

    public func planContext(wish: String, startToday: Bool, now: Date = .now) -> PlanContext {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = startToday ? today : calendar.date(byAdding: .day, value: 1, to: today)!
        let end = calendar.date(byAdding: .day, value: max(profile.planHorizonDays, 1) - 1, to: start)!
        let rides = allRides()
        let series = loadSeries(rides: rides, now: now)
        let weeks = TrainingLoad.weeks(rides: rides, ftp: profile.ftp, thresholdHeartRate: profile.thresholdHeartRate,
                                       from: calendar.date(byAdding: .day, value: -42, to: today)!, to: today)
        let recent = rides.filter { $0.startDate >= calendar.date(byAdding: .day, value: -21, to: today)! }
        let planned = ((try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? [])
            .filter { $0.status == .planned && $0.date >= start && $0.date <= end }
            .map(\.proposal)
        var result = PlanContext(profile: profile, today: today, horizonStart: start, horizonEnd: end,
                                 load: series.last, weeks: weeks, recentRides: recent, alreadyPlanned: planned, wish: wish)
        result.winterArc = winterArc(rides: rides, now: now)
        return result
    }

    public func generatePlan(wish: String, startToday: Bool) async {
        guard !isPlanning else { return }
        isPlanning = true
        defer { isPlanning = false }
        let ctx = planContext(wish: wish, startToday: startToday)
        let key = secrets.secret(.claudeAPIKey) ?? ""
        let coach: Coach = key.isEmpty
            ? DemoCoach()
            : ClaudeCoach(client: ClaudeClient(apiKey: key, model: profile.model, transport: transport))
        do {
            let plan = try await coach.plan(ctx)
            proposalSource = key.isEmpty ? .demo : .claude
            proposal = plan
            if plan.workouts.isEmpty {
                show("Der Coach hat für diesen Zeitraum keine Einheit vorgeschlagen.", error: false)
            }
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    public func acceptProposal(addToCalendar shouldAddToCalendar: Bool) async {
        guard let plan = proposal else { return }
        var created: [StoredWorkout] = []
        // `.demo` marks only the seeded demo plan; a DemoCoach plan the user accepts is theirs and survives
        // the demo cleanup when Strava gets connected.
        let source: WorkoutSource = proposalSource == .claude ? .claude : .manual
        for w in plan.workouts {
            let stored = StoredWorkout(proposal: w, source: source, weekFocus: plan.weekFocus)
            context.insert(stored)
            created.append(stored)
        }
        try? context.save()
        proposal = nil
        if shouldAddToCalendar {
            await addToCalendar(created)
        } else {
            show("\(created.count) Einheiten übernommen.", error: false)
        }
        if isMyWhooshConnected && profile.autoSendToMyWhoosh {
            await sendToMyWhoosh(created)
        }
    }

    public func discardProposal() { proposal = nil }

    // MARK: - Workouts

    public func startDate(for workout: StoredWorkout) -> Date {
        Calendar.current.date(bySettingHour: profile.preferredStartHour, minute: profile.preferredStartMinute,
                              second: 0, of: workout.date) ?? workout.date
    }

    public func calendarNotes(for workout: StoredWorkout) -> String {
        let d = workout.definition
        return """
        \(d.summary)

        \(d.plainTextDescription(ftp: profile.ftp))

        Dauer \(Formatters.duration(d.totalDuration)) · TSS ≈ \(Int(d.estimatedTSS.rounded())) · IF \(Formatters.decimal(d.intensityFactor, digits: 2))

        Warum: \(workout.rationale)

        MyWhoosh: .zwo aus IndoorCoach teilen → workout.mywhoosh.com → Upload → „Export to MyWhoosh“.
        """
    }

    public func addToCalendar(_ workouts: [StoredWorkout]) async {
        let ids = workouts.filter { $0.status == .planned }.map(\.persistentModelID)
        guard !ids.isEmpty else {
            show("Keine offenen Einheiten für den Kalender.", error: false); return
        }
        var count = 0
        defer { try? context.save() }
        do {
            for id in ids {
                // Re-resolve after every await – the workout may have been deleted meanwhile.
                guard let w = context.model(for: id) as? StoredWorkout, !w.isDeleted else { continue }
                let request = (eventID: w.calendarEventID, title: "🚴 \(w.title)", start: startDate(for: w),
                               duration: w.definition.totalDuration, notes: calendarNotes(for: w))
                let eventID = try await calendarService.upsert(eventID: request.eventID, title: request.title,
                                                               start: request.start, durationSeconds: request.duration,
                                                               notes: request.notes)
                if let w = context.model(for: id) as? StoredWorkout, !w.isDeleted {
                    w.calendarEventID = eventID
                    count += 1
                }
            }
            show(count == 1 ? "Im Kalender eingetragen." : "\(count) Einheiten im Kalender eingetragen.", error: false)
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    /// Deletes synchronously first (no awaits while holding the model), then cleans up the calendar.
    public func delete(_ workout: StoredWorkout) async {
        let eventID = workout.calendarEventID
        let whooshID = workout.myWhooshWorkoutID, whooshTask = workout.myWhooshTaskID
        context.delete(workout)
        try? context.save()
        if let eventID { try? await calendarService.remove(eventID: eventID) }
        // Best effort: keep MyWhoosh in sync, but never block local deletion on the unofficial API.
        if let whooshTask { try? await myWhoosh.deleteTask(whooshTask) }
        if let whooshID { try? await myWhoosh.delete(workoutID: whooshID) }
    }

    public func setStatus(_ status: WorkoutStatus, for workout: StoredWorkout) {
        workout.status = status
        try? context.save()
    }

    /// Writes the `.zwo` into a temporary file for the share sheet.
    public func zwoFile(for workout: StoredWorkout) throws -> URL {
        let d = workout.definition
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zwo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(ZWOExporter.fileName(for: d, date: workout.date))
        try ZWOExporter.xml(for: d).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Helpers

    public func show(_ message: String, error: Bool) {
        banner = Banner(message: message, isError: error)
    }

    private func persistProfile() {
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: Keys.profile) }
    }
}
