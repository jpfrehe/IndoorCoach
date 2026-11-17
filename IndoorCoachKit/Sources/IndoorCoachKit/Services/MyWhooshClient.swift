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
    public var Id: String
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
    public static func workout(for d: WorkoutDefinition, id: String, ftp: Int) -> MyWhooshWorkout {
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

public enum MyWhooshError: Error, Equatable, LocalizedError {
    case notConnected, loginFailed, sessionExpired, http(Int), unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case .notConnected: "MyWhoosh ist nicht verbunden – melde dich im Profil an."
        case .loginFailed: "MyWhoosh-Anmeldung fehlgeschlagen – E-Mail und Passwort prüfen."
        case .sessionExpired: "MyWhoosh-Anmeldung abgelaufen – bitte im Profil neu anmelden."
        case .http(let code): "MyWhoosh antwortet mit Fehler \(code). Die inoffizielle Schnittstelle hat sich evtl. geändert – nutze solange die .zwo-Datei."
        case .unexpectedResponse: "Unerwartete Antwort von MyWhoosh – nutze solange die .zwo-Datei."
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
        guard (200..<300).contains(response.statusCode) else {
            throw response.statusCode == 401 || response.statusCode == 403 ? MyWhooshError.loginFailed : MyWhooshError.http(response.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["Success"] as? Bool == true,
              let whooshId = json["WhooshId"] as? String, let access = json["AccessToken"] as? String else {
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

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.data(for: request)
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403:
            store.saveSession(nil)
            throw MyWhooshError.sessionExpired
        default: throw MyWhooshError.http(response.statusCode)
        }
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
