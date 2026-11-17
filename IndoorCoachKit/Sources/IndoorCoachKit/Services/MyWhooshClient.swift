import Foundation

// MyWhoosh direct upload (backlog B21) based on the community documentation
// https://github.com/mywhoosh-community/mywhoosh-api (MIT, unofficial – may change without notice).
// Field names below mirror that documentation exactly, hence the non-Swift casing.

// MARK: - Payload

public struct MyWhooshMessage: Codable, Hashable, Sendable {
    public var Id: Int
    public var Time: Int
    public var Message: String
}

public struct MyWhooshStep: Codable, Hashable, Sendable {
    public var Id: Int
    public var Pace = 1
    public var IntervalId = 0
    public var WorkoutMessage: [MyWhooshMessage] = []
    public var Rpm = 0
    public var StepType: String
    public var Power: Double = 0
    public var StartPower: Double = 0
    public var EndPower: Double = 0
    public var Time: Int
    public var IsManualGrade = false
    public var ManualGradeValue = 0
    public var ShowAveragePower = false
    public var FlatRoad = 0
}

public struct MyWhooshWorkout: Codable, Hashable, Sendable {
    /// MyWhoosh validates this as a number (device log, Nov 2026: "WorkoutsData.0.Id must be a number").
    public var Id: Int
    public var Name: String
    public var Description: String
    public var Mode = "E_Ride"
    public var ERGMode = "E_OFF"
    public var IsRecovery = false
    public var IsIntervals = false
    public var FTPMode = "E_NoFTP"
    public var IsTT = false
    public var IsTSS = false
    public var IsIF = false
    public var FTPMultiplier = 0
    public var StressPoint = 0
    public var Time: Int
    public var CustomTagDescription = ""
    public var CategoryId = 1
    public var SubcategoryId = 0
    public var `Type` = "E_Custom"
    public var DisplayType = "E_byWatts"
    public var StepCount: Int
    public var IsFavorite = false
    public var CompletedCount = 0
    public var WorkoutStepsArray: [MyWhooshStep]
    public var AuthorName = "IndoorCoach"
    public var WorkoutSteps: [String: String] = [:]
    public var WorkoutstepsTMap: [String] = []
    public var WokoutAssociationId = 0
    public var IF: Double
    public var TSS: Int
    public var KJ: Int
    public var IsVODAvailable = false
}

/// Maps IndoorCoach segments onto MyWhoosh steps. Power stays a fraction of FTP (MyWhoosh scales with the rider's FTP).
public enum MyWhooshMapper {
    /// Stable positive 31-bit id per app workout, so a re-send replaces the same MyWhoosh workout.
    public static func workoutID(for uuid: UUID) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325                 // FNV-1a
        for byte in uuid.uuidString.lowercased().utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return Int(hash % 2_000_000_000) + 1
    }

    public static func workout(for d: WorkoutDefinition, id: Int, ftp: Int) -> MyWhooshWorkout {
        var steps: [MyWhooshStep] = []
        func add(_ type: String, time: Int, power: Double = 0, start: Double = 0, end: Double = 0,
                 rpm: Int? = nil, text: String? = nil) {
            guard time > 0 else { return }
            var step = MyWhooshStep(Id: steps.count + 1, StepType: type, Time: time)
            step.Power = power; step.StartPower = start; step.EndPower = end
            step.Rpm = rpm ?? 0
            if let text, !text.isEmpty { step.WorkoutMessage = [MyWhooshMessage(Id: 0, Time: 0, Message: String(text.prefix(60)))] }
            steps.append(step)
        }
        for s in d.segments {
            switch s.kind {
            case .warmup:
                add("E_WarmUp", time: s.duration, start: s.powerLow ?? 0.45, end: s.powerHigh ?? 0.75, rpm: s.cadence, text: s.text)
            case .cooldown:
                // Stored semantically high → low (see ZWOExporter); MyWhoosh wants start → end.
                add("E_CoolDown", time: s.duration, start: s.powerHigh ?? 0.65, end: s.powerLow ?? 0.4, rpm: s.cadence, text: s.text)
            case .ramp:
                let low = s.powerLow ?? 0.5, high = s.powerHigh ?? 0.8
                add(high >= low ? "E_WarmUp" : "E_CoolDown", time: s.duration, start: low, end: high, rpm: s.cadence, text: s.text)
            case .steady:
                add("E_Normal", time: s.duration, power: s.power ?? 0.6, rpm: s.cadence, text: s.text)
            case .intervals:
                for i in 0..<(s.repeatCount ?? 1) {
                    add("E_Normal", time: s.onDuration ?? 60, power: s.onPower ?? 1.0, rpm: s.cadence, text: i == 0 ? s.text : nil)
                    add("E_Normal", time: s.offDuration ?? 60, power: s.offPower ?? 0.5)
                }
            case .freeRide:
                add("E_FreeRide", time: s.duration, text: s.text)
            }
        }
        let avg = d.steps.reduce(0.0) { $0 + $1.averagePower * Double($1.duration) } / Double(max(1, d.totalDuration))
        var w = MyWhooshWorkout(Id: id, Name: String(d.title.prefix(60)), Description: d.summary, Time: steps.reduce(0) { $0 + $1.Time },
                                StepCount: steps.count, WorkoutStepsArray: steps,
                                IF: (d.intensityFactor * 100).rounded() / 100, TSS: Int(d.estimatedTSS.rounded()),
                                KJ: Int((avg * Double(ftp) * Double(d.totalDuration) / 1000).rounded()))
        w.IsIntervals = d.segments.contains { $0.kind == .intervals }
        w.IsRecovery = d.type == .recovery
        return w
    }
}

// MARK: - Session

public struct MyWhooshSession: Codable, Equatable, Sendable {
    public var username: String
    public var whooshId: String
    public var accessToken: String
    public var refreshToken: String

    /// `exp` from the JWT payload; nil if it cannot be read.
    public var expiresAt: Date? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    public var isExpired: Bool { expiresAt.map { $0 <= Date().addingTimeInterval(30) } ?? false }
}

public protocol MyWhooshSessionStore: Sendable {
    func loadSession() -> MyWhooshSession?
    func saveSession(_ session: MyWhooshSession?)
}

public struct KeychainMyWhooshSessionStore: MyWhooshSessionStore {
    let keychain: Keychain
    public init(keychain: Keychain = Keychain()) { self.keychain = keychain }
    public func loadSession() -> MyWhooshSession? {
        keychain.data(.myWhooshSession).flatMap { try? JSONDecoder().decode(MyWhooshSession.self, from: $0) }
    }
    public func saveSession(_ session: MyWhooshSession?) {
        keychain.set(session.flatMap { try? JSONEncoder().encode($0) }, for: .myWhooshSession)
    }
}

/// For previews and snapshots (no Keychain).
public final class InMemoryMyWhooshSessionStore: MyWhooshSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: MyWhooshSession?
    public init() {}
    public func loadSession() -> MyWhooshSession? { lock.withLock { session } }
    public func saveSession(_ session: MyWhooshSession?) { lock.withLock { self.session = session } }
}

/// One past ride as listed by MyWhoosh. Field names are not documented, so several spellings are accepted.
public struct MyWhooshActivity: Sendable, Equatable {
    public var id: String
    public var name: String?
    public var date: Date?
    public var fitURL: URL?
    /// Key of the ride file on MyWhoosh's storage (`activityFileId`), when no direct URL is given.
    public var fileKey: String?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var averageWatts: Double?
    public var averageHeartrate: Double?

    static func list(from data: Data) -> MyWhooshClient.ActivityList? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let listKeys = ["activities", "data", "rides", "rideHistory", "items", "results", "list"]
        func findList(_ value: Any, depth: Int) -> [[String: Any]]? {
            if let array = value as? [[String: Any]] { return array }
            if let array = value as? [Any], array.isEmpty { return [] }
            guard depth < 2, let dict = value as? [String: Any] else { return nil }
            for key in listKeys { if let v = dict[key], let found = findList(v, depth: depth + 1) { return found } }
            return nil
        }
        guard let items = findList(json, depth: 0) else { return nil }
        return MyWhooshClient.ActivityList(activities: items.compactMap(MyWhooshActivity.init(json:)),
                                           responseKeys: ((json as? [String: Any])?.keys).map { $0.sorted() } ?? ["<Liste>"],
                                           itemKeys: items.first.map { $0.keys.sorted() } ?? [],
                                           sample: items.first.map(sample) ?? "–")
    }

    /// Shape of one entry for the log: types and values of the measurement fields only (no names or routes),
    /// the file key reduced to its length and extension.
    static func sample(_ item: [String: Any]) -> String {
        let fields = ["date", "startDatetime", "createdAt", "rideDuration", "distance", "elevation", "watt",
                      "heartrate", "type", "sportType", "totalWorkout"]
        var parts = fields.compactMap { key -> String? in
            guard let v = item[key] else { return nil }
            let text = v is NSNull ? "null" : String("\(v)".prefix(40))
            return "\(key)=\(type(of: v)):\(text)"
        }
        if let key = item["activityFileId"] {
            let s = "\(key)"
            parts.append("activityFileId=\(type(of: key)):\(s.count) Zeichen, Endung=\((s as NSString).pathExtension.isEmpty ? "–" : (s as NSString).pathExtension), URL=\(s.hasPrefix("http"))")
        }
        return parts.joined(separator: ", ")
    }

    init?(json: [String: Any]) {
        func value(_ keys: [String]) -> Any? {
            for key in keys { if let v = json[key], !(v is NSNull) { return v } }
            return nil
        }
        func string(_ keys: [String]) -> String? {
            switch value(keys) {
            case let s as String where !s.isEmpty: s
            case let n as NSNumber: n.stringValue
            default: nil
            }
        }
        func number(_ keys: [String]) -> Double? {
            switch value(keys) {
            case let n as NSNumber: n.doubleValue
            case let s as String: Double(s)
            default: nil
            }
        }
        guard let id = string(["id", "_id", "activityId", "ActivityId", "rideId", "RideId", "Id"]) else { return nil }
        self.id = id
        name = string(["name", "title", "Name", "activityName", "routeName", "RouteName"])
        date = Self.date(value(["startDatetime", "startTime", "StartTime", "date", "rideDate", "startDate", "createdAt"]))
        let fileValue = string(["downloadUrl", "fitFileUrl", "fileUrl", "s3Url", "fitFile", "FitFileUrl", "fitUrl",
                                "activityFileUrl", "activityFileId", "fileKey", "fitFileKey"])
        if let fileValue, fileValue.hasPrefix("https://") { fitURL = URL(string: fileValue) }
        else if let fileValue, !fileValue.hasPrefix("http") { fileKey = fileValue }
        durationSeconds = Self.seconds(value(["rideDuration", "duration", "rideTime", "totalTime", "movingTime",
                                              "elapsedTime", "TotalRideTime"]))
        // MyWhoosh shows kilometres; values below 1000 are taken as km.
        distanceMeters = number(["distance", "totalDistance"]).map { $0 < 1000 ? $0 * 1000 : $0 }
        averageWatts = number(["watt", "avgPower", "averagePower", "avgWatts", "AveragePower"]).flatMap { $0 > 0 ? $0 : nil }
        averageHeartrate = number(["heartrate", "heartRate", "avgHeartRate", "averageHeartRate", "avgHr", "AverageHeartRate"])
            .flatMap { $0 > 0 ? $0 : nil }
    }

    /// Seconds from a number (seconds; values below 400 are taken as minutes) or "H:MM:SS" / "MM:SS".
    static func seconds(_ raw: Any?) -> Int? {
        switch raw {
        case let n as NSNumber:
            let v = n.doubleValue
            guard v > 0 else { return nil }
            return Int(v < 400 ? v * 60 : v)
        case let s as String:
            let parts = s.split(separator: ":").compactMap { Double($0) }
            if parts.count >= 2 { return Int(parts.reduce(0) { $0 * 60 + $1 }) }
            return Double(s).flatMap { seconds(NSNumber(value: $0)) }
        default:
            return nil
        }
    }

    static func date(_ raw: Any?) -> Date? {
        switch raw {
        case let n as NSNumber:
            let v = n.doubleValue
            return Date(timeIntervalSince1970: v > 100_000_000_000 ? v / 1000 : v)   // ms or s
        case let s as String:
            if let v = Double(s) { return date(NSNumber(value: v)) }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.date(from: s)
        default:
            return nil
        }
    }
}

public enum MyWhooshError: Error, Equatable, LocalizedError {
    case notConnected, loginFailed, sessionExpired, http(Int), unexpectedResponse, historyUnavailable

    public var errorDescription: String? {
        switch self {
        case .notConnected: "MyWhoosh ist nicht verbunden – melde dich im Profil an."
        case .loginFailed: "MyWhoosh-Anmeldung fehlgeschlagen – E-Mail und Passwort prüfen."
        case .sessionExpired: "MyWhoosh-Anmeldung abgelaufen – bitte im Profil neu anmelden."
        case .http(let code): "MyWhoosh antwortet mit Fehler \(code). Die inoffizielle Schnittstelle hat sich evtl. geändert – nutze solange die .zwo-Datei."
        case .unexpectedResponse: "Unerwartete Antwort von MyWhoosh – nutze solange die .zwo-Datei."
        case .historyUnavailable: "MyWhoosh liefert die Fahrtenliste nicht wie erwartet. Importiere deine Fahrten solange als FIT-Dateien (Profil → MyWhoosh)."
        }
    }
}

// MARK: - Client

public actor MyWhooshClient {
    static let loginURL = URL(string: "https://services.mywhoosh.com/http-service/api/login")!
    static let coachingBase = URL(string: "https://coaching.mywhoosh.com/api/v2")!
    static let taskBase = URL(string: "https://service14.mywhoosh.com/v1")!

    let store: MyWhooshSessionStore
    let transport: HTTPTransport

    public init(store: MyWhooshSessionStore, transport: HTTPTransport = URLSessionTransport()) {
        self.store = store
        self.transport = transport
    }

    /// Logs in and stores only the session (tokens + WhooshId). The password is never persisted.
    public func login(username: String, password: String) async throws {
        var request = URLRequest(url: Self.loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // "Platform" uses the documented value; other values are untested against the unofficial API.
        let body: [String: Any] = ["Username": username, "Password": password, "Platform": "Android", "Action": 1001,
                                   "CorrelationId": UUID().uuidString, "DeviceId": Self.deviceID, "Authorization": ""]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        // Diagnostics: status, success flag, server message and field names – never the password or tokens.
        Log.notice(.mywhoosh, "Login: HTTP \(response.statusCode), Success=\(json?["Success"].map { "\($0)" } ?? "–"), "
                   + "Meldung=\(Self.serverMessage(json) ?? "–"), Felder=\(json.map { $0.keys.sorted() } ?? ["<kein JSON: \(data.count) Bytes>"]), "
                   + "WhooshId-Typ=\(json?["WhooshId"].map { "\(type(of: $0))" } ?? "–")")
        guard (200..<300).contains(response.statusCode) else {
            throw response.statusCode == 401 || response.statusCode == 403 ? MyWhooshError.loginFailed : MyWhooshError.http(response.statusCode)
        }
        let success = (json?["Success"] as? Bool) ?? ((json?["Success"] as? String)?.lowercased() == "true")
        // WhooshId may come as a string or a number.
        let whooshId = (json?["WhooshId"] as? String) ?? (json?["WhooshId"] as? NSNumber)?.stringValue
        guard let json, success, let whooshId, !whooshId.isEmpty, let access = json["AccessToken"] as? String, !access.isEmpty else {
            throw MyWhooshError.loginFailed
        }
        store.saveSession(MyWhooshSession(username: username, whooshId: whooshId, accessToken: access,
                                          refreshToken: json["RefreshToken"] as? String ?? ""))
    }

    public func logout() { store.saveSession(nil) }

    public func upload(_ workouts: [MyWhooshWorkout]) async throws {
        let session = try validSession()
        let payload = UploadBody(UserId: session.whooshId, WorkoutsData: workouts)
        var request = authorized(URLRequest(url: Self.coachingBase.appendingPathComponent("client/custom-workout-upload")), session)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        _ = try await send(request)
    }

    public func delete(workoutID: String) async throws {
        let session = try validSession()
        let url = Self.coachingBase.appendingPathComponent("client/custom-workout-upload/\(session.whooshId)/\(workoutID)")
        var request = authorized(URLRequest(url: url), session)
        request.httpMethod = "DELETE"
        _ = try await send(request)
    }

    /// Puts an uploaded workout on a day in the MyWhoosh calendar. Returns the task id if MyWhoosh reports one.
    @discardableResult
    public func schedule(workoutID: String, name: String, description: String, start: Date,
                         durationSeconds: Int, tss: Int) async throws -> String? {
        let session = try validSession()
        var request = authorized(URLRequest(url: Self.taskBase.appendingPathComponent("task/create")), session)
        request.httpMethod = "POST"
        let startEpoch = Int(start.timeIntervalSince1970)
        let body: [String: Any] = ["TaskId": "", "TaskType": "E_Simple_Workout", "TaskStartedTimeEpoc": startEpoch,
                                   "TaskTypeId": workoutID, "CurDayId": "", "TaskState": "E_NotStarted", "DayNo": 0,
                                   "TaskEndEpochTime": startEpoch + durationSeconds, "MapId": 0,
                                   "TaskName": String(name.prefix(60)), "TaskDescription": String(description.prefix(200)),
                                   "TotalKilometers": 0, "TotalElevation": 0, "TSS": tss, "SportMode": "E_Cycling"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(request)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["data"] as? [String: Any])?["id"] as? String
    }

    public func deleteTask(_ taskID: String) async throws {
        let session = try validSession()
        var request = authorized(URLRequest(url: Self.taskBase.appendingPathComponent("task/\(taskID)")), session)
        request.httpMethod = "DELETE"
        _ = try await send(request)
    }

    // MARK: Ride history (undocumented endpoint, used by community tools – response format is guessed tolerantly)

    public struct ActivityList: Sendable {
        public var activities: [MyWhooshActivity]
        /// Field names (no values) of the response and of the first item – logged for diagnostics.
        public var responseKeys: [String]
        public var itemKeys: [String]
        /// See `MyWhooshActivity.sample`.
        public var sample = "–"
    }

    /// Lists the rider's past activities. Tries the request bodies community tools use, in order.
    public func activities(limit: Int = 50, notBefore: Date? = nil, maxPages: Int = 10) async throws -> ActivityList {
        let session = try validSession()
        // The endpoint validates its body (device logs, Nov 2026): `page` ≥ 1 and `sortDate` ASC/DESC are required;
        // an unknown `offset` field is answered with 403. Newest first, page by page until `notBefore`.
        var collected: [MyWhooshActivity] = []
        var responseKeys: [String] = []
        var itemKeys: [String] = []
        var seen = Set<String>()
        var withLimit = true                                  // falls back to page + sortDate only
        var page = 1
        while page <= maxPages {
            var body: [String: Any] = ["page": page, "sortDate": "DESC"]
            if withLimit { body["limit"] = limit }
            var request = authorized(URLRequest(url: Self.activitiesURL), session)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let data: Data
            do {
                data = try await send(request, label: "Fahrtenliste S. \(page)", endsSessionOnAuthError: false)
            } catch MyWhooshError.http(let code) where page == 1 && withLimit && code == 400 {
                withLimit = false                             // maybe `limit` is not accepted – retry without it
                continue
            } catch MyWhooshError.http(let code) where page > 1 {
                Log.error(.sync, "MyWhoosh-Fahrtenliste: Seite \(page) mit HTTP \(code) abgebrochen, \(collected.count) Einträge behalten")
                break
            } catch MyWhooshError.http(let code) {
                Log.error(.sync, "MyWhoosh-Fahrtenliste nicht lesbar: HTTP \(code)")
                throw MyWhooshError.historyUnavailable
            }
            guard let list = MyWhooshActivity.list(from: data) else {
                Log.error(.sync, "MyWhoosh-Fahrtenliste S. \(page): unbekanntes Format, Antwort=\(Self.bodyExcerpt(data))")
                if page == 1 { throw MyWhooshError.historyUnavailable }
                break
            }
            if page == 1 {
                responseKeys = list.responseKeys; itemKeys = list.itemKeys
                Log.notice(.mywhoosh, "Fahrtenliste Beispiel: \(list.sample)")
            }
            let new = list.activities.filter { seen.insert($0.id).inserted }
            collected += new
            // Stop on an empty/repeated page or once the page reaches back past `notBefore`.
            if new.isEmpty { break }
            if let notBefore, let oldest = new.compactMap(\.date).min(), oldest < notBefore { break }
            page += 1
        }
        return ActivityList(activities: collected, responseKeys: responseKeys, itemKeys: itemKeys)
    }

    /// The ride file of a listed activity: its URL, or – with only a file key – MyWhoosh's ride storage
    /// (path as used by community tools; tried with and without ".fit").
    public func downloadFIT(for activity: MyWhooshActivity) async throws -> Data {
        if let url = activity.fitURL { return try await downloadFIT(url) }
        guard let key = activity.fileKey, let session = store.loadSession() else { throw MyWhooshError.unexpectedResponse }
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let base = "https://mywhooshprod.s3.eu-west-1.amazonaws.com/ride/\(session.whooshId)/\(safeKey)"
        var candidates = [base]
        if (key as NSString).pathExtension.isEmpty { candidates.append(base + ".fit") }
        var lastError: Error = MyWhooshError.unexpectedResponse
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            do { return try await downloadFIT(url) } catch { lastError = error }
        }
        throw lastError
    }

    /// Downloads an activity's FIT file. Only https URLs are followed; the token goes only to MyWhoosh hosts
    /// (S3 links are pre-signed).
    public func downloadFIT(_ url: URL) async throws -> Data {
        guard url.scheme == "https", let host = url.host() else { throw MyWhooshError.unexpectedResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if host == "mywhoosh.com" || host.hasSuffix(".mywhoosh.com") {
            request = authorized(request, try validSession())
        }
        return try await send(request, label: "FIT-Download", endsSessionOnAuthError: false)
    }

    static let activitiesURL = URL(string: "https://service14.mywhoosh.com/v2/rider/profile/activities")!

    // MARK: Helpers

    private struct UploadBody: Encodable {
        let UserId: String
        let WorkoutsData: [MyWhooshWorkout]
    }

    private func validSession() throws -> MyWhooshSession {
        guard let session = store.loadSession() else { throw MyWhooshError.notConnected }
        // No refresh endpoint is documented: an expired token means "log in again".
        guard !session.isExpired else { throw MyWhooshError.sessionExpired }
        return session
    }

    private func authorized(_ request: URLRequest, _ session: MyWhooshSession) -> URLRequest {
        var r = request
        r.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = 30
        return r
    }

    /// `endsSessionOnAuthError`: 401/403 means "log in again" for the documented endpoints. For the undocumented
    /// history endpoints it only means "not allowed there" and must not sign the user out.
    private func send(_ request: URLRequest, label: String? = nil, endsSessionOnAuthError: Bool = true) async throws -> Data {
        let (data, response) = try await transport.data(for: request)
        let name = label ?? "\(request.httpMethod ?? "GET") \(request.url?.host() ?? "?")/\(request.url?.pathComponents.dropFirst().prefix(3).joined(separator: "/") ?? "")"
        if !(200..<300).contains(response.statusCode) {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            Log.error(.mywhoosh, "\(name): HTTP \(response.statusCode), Meldung=\(Self.serverMessage(json) ?? "–"), \(data.count) Bytes, Antwort=\(Self.bodyExcerpt(data))")
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403 where endsSessionOnAuthError:
            store.saveSession(nil)
            throw MyWhooshError.sessionExpired
        default: throw MyWhooshError.http(response.statusCode)
        }
    }

    /// Error body for the log: one line, at most 300 characters; `Log` redacts tokens, e-mails and long hex ids.
    static func bodyExcerpt(_ data: Data) -> String {
        guard !data.isEmpty else { return "–" }
        let text = String(decoding: data.prefix(2_000), as: UTF8.self)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(text.prefix(1_000))
    }

    /// Short server message for the log (MyWhoosh uses `Message` or `message`).
    static func serverMessage(_ json: [String: Any]?) -> String? {
        guard let text = (json?["Message"] ?? json?["message"] ?? json?["error"]) as? String else { return nil }
        return String(text.prefix(160))
    }

    /// Stable per-install id (not hardware-bound).
    static var deviceID: String {
        let key = "mywhoosh.deviceId"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
