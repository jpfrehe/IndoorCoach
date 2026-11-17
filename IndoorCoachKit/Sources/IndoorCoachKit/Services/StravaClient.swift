import Foundation

// MARK: - Configuration & tokens

public struct StravaConfig: Sendable, Equatable {
    public var clientID: String
    public var clientSecret: String
    /// Must match the "Authorization Callback Domain" of the Strava API app (`localhost` is whitelisted by Strava).
    public var redirectURI: String
    public static let callbackScheme = "indoorcoach"
    public static let defaultRedirectURI = "indoorcoach://localhost/strava"

    public init(clientID: String, clientSecret: String, redirectURI: String = StravaConfig.defaultRedirectURI) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
    }

    public var isComplete: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    /// Web authorize URL for ASWebAuthenticationSession.
    public func authorizeURL(state: String) -> URL {
        var c = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "read,activity:read_all"),
            URLQueryItem(name: "state", value: state)
        ]
        return c.url!
    }
}

public struct StravaTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var athleteName: String?
    public var scope: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, athleteName: String? = nil, scope: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.athleteName = athleteName
        self.scope = scope
    }

    /// Refresh a few minutes early so requests never race the expiry.
    public func needsRefresh(now: Date = .now) -> Bool { expiresAt.timeIntervalSince(now) < 300 }
}

public enum StravaError: LocalizedError, Equatable {
    case notConfigured
    case notConnected
    case authorizationDenied
    case stateMismatch
    case missingScope
    case http(Int, String)
    /// HTTP 429. `retryAfter` (seconds) comes from `Retry-After` or Strava's `X-RateLimit-*` headers, nil if unknown.
    case rateLimited(retryAfter: TimeInterval?)
    /// HTTP 5xx that persisted after one retry.
    case unavailable(Int)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "Strava Client-ID und Client-Secret fehlen (Profil → Strava)."
        case .notConnected: "Strava ist nicht verbunden."
        case .authorizationDenied: "Strava-Anmeldung abgebrochen oder verweigert."
        case .stateMismatch: "Ungültige Strava-Antwort (state stimmt nicht)."
        case .missingScope: "Bitte bei Strava den Zugriff auf alle Aktivitäten erlauben."
        case let .rateLimited(retryAfter): Self.rateLimitMessage(retryAfter: retryAfter)
        case let .unavailable(code): "Strava ist gerade nicht erreichbar (Fehler \(code)) – bitte später erneut synchronisieren."
        case let .http(code, message): "Strava-Fehler \(code): \(message)"
        }
    }

    static func rateLimitMessage(retryAfter: TimeInterval?) -> String {
        // Strava's short-term window is 15 minutes; without headers that is the best guess.
        let minutes = max(1, Int((max(retryAfter ?? 15 * 60, 0) / 60).rounded(.up)))
        if minutes > 90 {
            let hours = Int((Double(minutes) / 60).rounded(.up))
            return "Strava-Tageslimit erreicht – bitte in ca. \(hours) Stunden erneut synchronisieren."
        }
        return "Strava-Limit erreicht – bitte in ca. \(minutes) \(minutes == 1 ? "Minute" : "Minuten") erneut synchronisieren."
    }
}

// MARK: - DTOs

struct StravaTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_at: TimeInterval
    let scope: String?
    let athlete: Athlete?
    struct Athlete: Decodable { let firstname: String?; let lastname: String? }
}

public struct StravaActivityDTO: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let sport_type: String?
    public let type: String?
    public let start_date: Date
    public let moving_time: Int
    public let distance: Double
    public let average_watts: Double?
    public let weighted_average_watts: Double?
    public let kilojoules: Double?
    public let average_heartrate: Double?
    public let max_heartrate: Double?
    public let trainer: Bool?
    public let device_watts: Bool?
    /// Strava Relative Effort (only present for some athletes/activities).
    public let suffer_score: Double?

    public static let rideTypes: Set<String> = ["Ride", "VirtualRide", "GravelRide", "MountainBikeRide", "EBikeRide", "EMountainBikeRide"]

    public var effectiveSportType: String { sport_type ?? type ?? "Unknown" }
    public var isRide: Bool { Self.rideTypes.contains(effectiveSportType) }

    public var summary: RideSummary {
        var r = RideSummary(id: id, name: name, sportType: effectiveSportType, startDate: start_date, movingTime: moving_time,
                            distance: distance, averageWatts: average_watts, weightedAverageWatts: weighted_average_watts,
                            kilojoules: kilojoules, averageHeartrate: average_heartrate, maxHeartrate: max_heartrate,
                            trainer: trainer ?? false)
        r.stravaRelativeEffort = suffer_score.flatMap { $0 > 0 ? $0 : nil }
        return r
    }

    public static func decodeList(_ data: Data) throws -> [StravaActivityDTO] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([StravaActivityDTO].self, from: data)
    }
}

// MARK: - Token storage abstraction

public protocol StravaTokenStore: Sendable {
    func loadTokens() -> StravaTokens?
    func saveTokens(_ tokens: StravaTokens?)
}

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

// MARK: - Client

public actor StravaClient {
    private let config: StravaConfig
    private let store: StravaTokenStore
    private let transport: HTTPTransport
    private let sleep: @Sendable (Duration) async throws -> Void

    /// Backoff before the single retry of a 5xx response.
    static let serverErrorBackoff: Duration = .seconds(2)

    public init(config: StravaConfig, store: StravaTokenStore, transport: HTTPTransport = URLSessionTransport(),
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.config = config
        self.store = store
        self.transport = transport
        self.sleep = sleep
    }

    /// Exchanges the authorization code from the OAuth callback URL for tokens.
    public func completeAuthorization(callbackURL: URL, expectedState: String) async throws -> StravaTokens {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if value("error") != nil { Log.error(.strava, "OAuth: Zugriff verweigert"); throw StravaError.authorizationDenied }
        guard value("state") == expectedState else { Log.error(.strava, "OAuth: state stimmt nicht"); throw StravaError.stateMismatch }
        guard let code = value("code") else { Log.error(.strava, "OAuth: kein Code im Callback"); throw StravaError.authorizationDenied }
        if let scope = value("scope"), !scope.contains("activity:read") { Log.error(.strava, "OAuth: Scope activity:read fehlt"); throw StravaError.missingScope }
        let tokens = try await tokenRequest(["grant_type": "authorization_code", "code": code])
        store.saveTokens(tokens)
        Log.notice(.strava, "OAuth: Token-Austausch erfolgreich")
        return tokens
    }

    public func disconnect() {
        store.saveTokens(nil)
    }

    /// Returns a valid access token, refreshing (and persisting the rotated refresh token) when needed.
    public func validAccessToken(now: Date = .now) async throws -> String {
        guard config.isComplete else { throw StravaError.notConfigured }
        guard let tokens = store.loadTokens() else { throw StravaError.notConnected }
        if !tokens.needsRefresh(now: now) { return tokens.accessToken }
        Log.notice(.strava, "Access-Token läuft ab – wird erneuert")
        var refreshed = try await tokenRequest(["grant_type": "refresh_token", "refresh_token": tokens.refreshToken])
        refreshed.athleteName = refreshed.athleteName ?? tokens.athleteName
        store.saveTokens(refreshed)
        return refreshed.accessToken
    }

    /// Loads all rides after `after`, following pagination (max `maxPages` × 100 activities).
    public func fetchRides(after: Date, maxPages: Int = 10) async throws -> [RideSummary] {
        var rides: [RideSummary] = []
        for page in 1...maxPages {
            let token = try await validAccessToken()
            var c = URLComponents(string: "https://www.strava.com/api/v3/athlete/activities")!
            c.queryItems = [
                URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970))),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page))
            ]
            var request = URLRequest(url: c.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await sendRetryingServerErrors(request)
            try Self.check(response, data, redacting: [token])
            let list = try StravaActivityDTO.decodeList(data)
            rides += list.filter(\.isRide).map(\.summary)
            Log.notice(.strava, "Aktivitäten Seite \(page): HTTP \(response.statusCode), \(list.count) Aktivitäten, davon \(list.filter(\.isRide).count) Fahrten")
            if list.count < 100 { break }
        }
        return rides
    }

    /// GET requests are idempotent: retry a 5xx exactly once after a short backoff. 429 is never retried here –
    /// Strava's window lasts up to 15 minutes, so the user gets a message instead.
    private func sendRetryingServerErrors(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let first = try await transport.data(for: request)
        guard (500...599).contains(first.1.statusCode) else { return first }
        try await sleep(Self.serverErrorBackoff)
        return try await transport.data(for: request)
    }

    private func tokenRequest(_ params: [String: String]) async throws -> StravaTokens {
        guard config.isComplete else { throw StravaError.notConfigured }
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var all = params
        all["client_id"] = config.clientID
        all["client_secret"] = config.clientSecret
        request.httpBody = Self.formEncode(all).data(using: .utf8)
        let (data, response) = try await transport.data(for: request)
        try Self.check(response, data)
        let decoded = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        let name = [decoded.athlete?.firstname, decoded.athlete?.lastname].compactMap { $0 }.joined(separator: " ")
        return StravaTokens(accessToken: decoded.access_token, refreshToken: decoded.refresh_token,
                            expiresAt: Date(timeIntervalSince1970: decoded.expires_at),
                            athleteName: name.isEmpty ? nil : name, scope: decoded.scope)
    }

    static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return params.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }

    /// Maps HTTP errors; server messages are redacted (Claude keys and the given secrets, e.g. the access token).
    static func check(_ response: HTTPURLResponse, _ data: Data, redacting secrets: [String] = [], now: Date = .now) throws {
        if !(200..<300).contains(response.statusCode) { Log.error(.strava, "HTTP \(response.statusCode) \(response.url?.path ?? "")") }
        switch response.statusCode {
        case 200..<300: return
        case 429: throw StravaError.rateLimited(retryAfter: retryAfter(from: response, now: now))
        case 500...599: throw StravaError.unavailable(response.statusCode)
        case 401: throw StravaError.notConnected
        default:
            struct Fault: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(Fault.self, from: data))?.message
                ?? String(data: data.prefix(200), encoding: .utf8) ?? ""
            let redacted = secrets.filter { !$0.isEmpty }
                .reduce(ClaudeClient.redact(message)) { $0.replacingOccurrences(of: $1, with: "…") }
            throw StravaError.http(response.statusCode, redacted)
        }
    }

    /// Seconds until a request may succeed again: `Retry-After` (seconds or HTTP date) wins; otherwise Strava's
    /// `X-ReadRateLimit-*` / `X-RateLimit-*` headers ("15-min,daily"). The 15-minute window resets at :00/:15/:30/:45,
    /// the daily one at midnight UTC.
    static func retryAfter(from response: HTTPURLResponse, now: Date) -> TimeInterval? {
        if let raw = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) {
            if let seconds = TimeInterval(raw) { return max(0, seconds) }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: raw) { return max(0, date.timeIntervalSince(now)) }
        }
        func pair(_ name: String) -> [Int]? {
            let values = response.value(forHTTPHeaderField: name)?.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return values?.count == 2 ? values : nil
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var waits: [TimeInterval] = []
        for prefix in ["X-ReadRateLimit", "X-RateLimit"] {
            guard let limit = pair("\(prefix)-Limit"), let usage = pair("\(prefix)-Usage") else { continue }
            if usage[1] >= limit[1],
               let midnight = utc.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                           matchingPolicy: .nextTime) {
                waits.append(midnight.timeIntervalSince(now))
            } else if usage[0] >= limit[0] {
                let c = utc.dateComponents([.minute, .second], from: now)
                waits.append(TimeInterval(15 * 60 - ((c.minute ?? 0) % 15 * 60 + (c.second ?? 0))))
            }
        }
        return waits.max()
    }
}
