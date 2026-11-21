import CryptoKit
import Compression
import Foundation
import Security

// intervals.icu (docs/19-PLAN-PLATTFORM-ANBINDUNGEN.md, Abschnitt 6): Pläne senden, Fahrten lesen.
// Öffentlicher OAuth-Client mit PKCE – es gibt kein Client-Secret, weder in der App noch im Repository.
// Alle Anfragen gehen ausschließlich an https://intervals.icu.

// MARK: - Configuration

public struct IntervalsConfig: Sendable, Equatable {
    /// Öffentliche Client-ID (Info.plist `IntervalsClientID`); leer, bis die App bei intervals.icu freigegeben ist.
    public var clientID: String
    /// Muss bei intervals.icu exakt so eingetragen sein.
    public var redirectURI: String
    public static let callbackScheme = "indoorcoach"
    public static let defaultRedirectURI = "indoorcoach://localhost/intervals"
    /// Nur was die App braucht: Fahrten lesen, Pläne in den Kalender schreiben.
    public static let scope = "ACTIVITY:READ,CALENDAR:WRITE"
    static let requiredScopes: Set<String> = ["ACTIVITY:READ", "CALENDAR:WRITE"]
    static let origin = "https://intervals.icu"

    public init(clientID: String = AppConfig.intervalsClientID, redirectURI: String = IntervalsConfig.defaultRedirectURI) {
        self.clientID = clientID
        self.redirectURI = redirectURI
    }

    var trimmedClientID: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Ohne Client-ID bleibt nur der API-Key.
    public var isOAuthAvailable: Bool { !trimmedClientID.isEmpty }

    /// Web-Anmeldung für ASWebAuthenticationSession.
    public func authorizeURL(state: String, codeChallenge: String) -> URL {
        var c = URLComponents(string: "\(Self.origin)/oauth/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: trimmedClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return c.url!
    }
}

// MARK: - PKCE (RFC 7636)

public enum IntervalsPKCE {
    /// 64 Zufallsbytes → 86 Zeichen base64url (erlaubt sind 43–128 aus dem „unreserved“-Zeichensatz).
    public static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max, using: &generator) }
        }
        return base64URL(Data(bytes))
    }

    /// `BASE64URL(SHA256(verifier))` ohne Auffüllzeichen.
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Credential & store

public enum IntervalsCredential: Codable, Equatable, Sendable {
    case oauth(accessToken: String, athleteID: String?, athleteName: String?)
    /// Persönlicher API-Key des eigenen Kontos (Übergangsweg vor der OAuth-Freigabe).
    case apiKey(String)

    /// `Bearer <Token>` bzw. `Basic base64("API_KEY:<Key>")`.
    public var authorizationHeader: String {
        switch self {
        case .oauth(let token, _, _): "Bearer \(token)"
        case .apiKey(let key): "Basic " + Data("API_KEY:\(key)".utf8).base64EncodedString()
        }
    }

    /// Alles, was in einer Fehlermeldung nicht auftauchen darf.
    var secrets: [String] {
        switch self {
        case .oauth(let token, _, _): [token]
        case .apiKey(let key): [key, Data("API_KEY:\(key)".utf8).base64EncodedString()]
        }
    }

    public var athleteName: String? {
        if case .oauth(_, _, let name) = self { return name }
        return nil
    }
}

public protocol IntervalsCredentialStore: Sendable {
    func loadCredential() -> IntervalsCredential?
    /// `nil` löscht. Liefert false, wenn das Speichern nicht geklappt hat (z. B. Schlüsselbund gesperrt).
    @discardableResult
    func saveCredential(_ credential: IntervalsCredential?) -> Bool
}

/// Schlüsselbund (über den `SecretStore` der App) – der Zugang liegt als JSON unter `.intervalsCredential`.
public struct SecretIntervalsCredentialStore: IntervalsCredentialStore {
    let secrets: SecretStore
    public init(secrets: SecretStore) { self.secrets = secrets }

    public func loadCredential() -> IntervalsCredential? {
        secrets.secret(.intervalsCredential)
            .flatMap { try? JSONDecoder().decode(IntervalsCredential.self, from: Data($0.utf8)) }
    }

    @discardableResult
    public func saveCredential(_ credential: IntervalsCredential?) -> Bool {
        let json = credential.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        secrets.setSecret(json, for: .intervalsCredential)
        return loadCredential() == credential   // zurücklesen: `setSecret` meldet keinen Fehler
    }
}

/// Für Vorschauen und Tests (kein Schlüsselbund).
public final class InMemoryIntervalsCredentialStore: IntervalsCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: IntervalsCredential?
    public init(_ credential: IntervalsCredential? = nil) { stored = credential }
    public var credential: IntervalsCredential? { lock.withLock { stored } }
    public func loadCredential() -> IntervalsCredential? { credential }
    @discardableResult
    public func saveCredential(_ credential: IntervalsCredential?) -> Bool { lock.withLock { stored = credential }; return true }
}

// MARK: - Errors

public enum IntervalsError: LocalizedError, Equatable {
    case notConfigured
    case notConnected
    case invalidAPIKey
    /// HTTP 403: der Zugang gilt, aber die Berechtigung fehlt.
    case forbidden
    /// Der Token-Austausch wurde abgelehnt (Code ungültig, abgelaufen oder schon benutzt).
    case authorizationFailed
    case keychainFailed
    case authorizationDenied
    case stateMismatch
    case missingScope
    case http(Int, String)
    case rateLimited(retryAfter: TimeInterval?)
    /// HTTP 5xx, auch nach dem einen Wiederholungsversuch.
    case unavailable(Int)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "intervals.icu-Anmeldung ist in dieser Version noch nicht freigeschaltet – verbinde dich vorerst mit deinem API-Key."
        case .notConnected: "intervals.icu-Zugang abgelaufen – bitte neu verbinden."
        case .invalidAPIKey: "Der intervals.icu-API-Key wurde abgelehnt – prüfe ihn unter Einstellungen → Entwicklereinstellungen auf intervals.icu."
        case .forbidden: "intervals.icu verweigert den Zugriff – prüfe die Berechtigungen."
        case .authorizationFailed: "intervals.icu hat die Anmeldung nicht angenommen – bitte noch einmal verbinden."
        case .keychainFailed: "Zugang konnte nicht im Schlüsselbund gespeichert werden."
        case .authorizationDenied: "intervals.icu-Anmeldung abgebrochen oder verweigert."
        case .stateMismatch: "Ungültige intervals.icu-Antwort (state stimmt nicht)."
        case .missingScope: "Bitte bei intervals.icu das Lesen der Aktivitäten und das Schreiben in den Kalender erlauben."
        case let .rateLimited(retryAfter): Self.rateLimitMessage(retryAfter: retryAfter)
        case let .unavailable(code): "intervals.icu ist gerade nicht erreichbar (Fehler \(code)) – bitte später erneut versuchen."
        case let .http(code, message): "intervals.icu-Fehler \(code): \(message)"
        }
    }

    static func rateLimitMessage(retryAfter: TimeInterval?) -> String {
        guard let retryAfter else { return "intervals.icu-Limit erreicht – bitte gleich noch einmal versuchen." }
        let minutes = max(1, Int((max(retryAfter, 0) / 60).rounded(.up)))
        return "intervals.icu-Limit erreicht – bitte in ca. \(minutes) \(minutes == 1 ? "Minute" : "Minuten") erneut versuchen."
    }
}

// MARK: - Payloads

/// Eine geplante Einheit für den intervals.icu-Kalender.
public struct IntervalsPlannedWorkout: Sendable, Equatable {
    /// Workout-UUID der App: damit ersetzt ein erneutes Senden denselben Termin und Löschen findet ihn wieder.
    public var externalID: String
    public var name: String
    /// Beginn in Ortszeit (intervals.icu bekommt Datum und Uhrzeit ohne Zeitzone).
    public var start: Date
    public var fileName: String
    /// ZWO-XML (`ZWOExporter`).
    public var zwo: String
    /// Dauer in Sekunden.
    public var movingTime: Int

    public init(externalID: String, name: String, start: Date, fileName: String, zwo: String, movingTime: Int) {
        self.externalID = externalID
        self.name = name
        self.start = start
        self.fileName = fileName
        self.zwo = zwo
        self.movingTime = movingTime
    }
}

/// Eine Aktivität aus der Liste von intervals.icu. Alle Felder sind optional und werden nachsichtig gelesen:
/// ein unbekanntes oder falsch typisiertes Feld darf nie die ganze Liste kippen.
public struct IntervalsActivity: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let type: String?
    public let startDate: Date?
    public let startDateLocal: Date?
    public let movingTime: Double?
    public let elapsedTime: Double?
    public let distance: Double?
    public let averageWatts: Double?
    public let weightedAverageWatts: Double?
    public let joules: Double?
    public let averageHeartrate: Double?
    public let maxHeartrate: Double?
    public let trainer: Bool?
    public let source: String?
    public let fileType: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, type, start_date, start_date_local, moving_time, elapsed_time, distance, icu_average_watts,
             icu_weighted_avg_watts, icu_joules, average_heartrate, max_heartrate, trainer, source, file_type
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func lenient<T: Decodable>(_ key: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil }
        guard let rawID = (try? c.decodeIfPresent(FlexibleString.self, forKey: .id)) ?? nil, !rawID.value.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "id fehlt"))
        }
        id = rawID.value
        name = lenient(.name)
        type = lenient(.type)
        startDate = (lenient(.start_date) as String?).flatMap(Self.parseUTC)
        startDateLocal = (lenient(.start_date_local) as String?).flatMap(Self.parseLocal)
        movingTime = lenient(.moving_time)
        elapsedTime = lenient(.elapsed_time)
        distance = lenient(.distance)
        averageWatts = lenient(.icu_average_watts)
        weightedAverageWatts = lenient(.icu_weighted_avg_watts)
        joules = lenient(.icu_joules)
        averageHeartrate = lenient(.average_heartrate)
        maxHeartrate = lenient(.max_heartrate)
        trainer = lenient(.trainer)
        source = lenient(.source)
        fileType = lenient(.file_type)
    }

    /// Fahrten (Rad-Typen wie bei Strava); Läufe usw. gehören nicht in die Radbelastung.
    public var isRide: Bool { type.map(StravaActivityDTO.rideTypes.contains) ?? false }

    /// Strava-Aktivitäten liefert die intervals.icu-API nicht mit Daten aus.
    public var isFromStrava: Bool { source?.uppercased() == "STRAVA" }

    /// Die Werte der Liste als Fahrt; nil ohne verwertbaren Start oder ohne Dauer.
    public func rideSummary(id rideID: Int) -> RideSummary? {
        guard let start = startDate ?? startDateLocal else { return nil }
        // Unsinnige Zahlen (1e300, NaN) zählen als fehlend – nie ein Absturz.
        func whole(_ v: Double?) -> Int? {
            guard let v, v.isFinite, abs(v) < 1e9, let i = Int(exactly: v.rounded()), i > 0 else { return nil }
            return i
        }
        guard let seconds = whole(movingTime) ?? whole(elapsedTime) else { return nil }
        func positive(_ v: Double?) -> Double? { v.flatMap { $0 > 0 ? $0 : nil } }
        let sport = type ?? "Ride"
        return RideSummary(id: rideID, name: name ?? "intervals.icu-Fahrt", sportType: sport, startDate: start, movingTime: seconds,
                           distance: max(distance ?? 0, 0), averageWatts: positive(averageWatts),
                           weightedAverageWatts: positive(weightedAverageWatts), kilojoules: positive(joules).map { $0 / 1000 },
                           averageHeartrate: positive(averageHeartrate), maxHeartrate: positive(maxHeartrate),
                           trainer: trainer ?? (sport == "VirtualRide"))
    }

    static func parseUTC(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    static func parseLocal(_ text: String) -> Date? { IntervalsClient.localTimeFormatter().date(from: text) }
}

/// Liest einen String oder eine Zahl als String (intervals.icu-IDs sind mal `"i123"`, mal `123`).
struct FlexibleString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self), d.isFinite, let i = Int(exactly: d) { value = String(i) }
        else { throw DecodingError.typeMismatch(String.self, .init(codingPath: c.codingPath, debugDescription: "kein String/Zahl")) }
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private struct IntervalsTokenResponse: Decodable {
    let accessToken: String
    let scope: String?
    let athleteID: String?
    let athleteName: String?

    private enum CodingKeys: String, CodingKey { case access_token, scope, athlete }
    private struct Athlete: Decodable {
        let id: String?
        let name: String?
        private enum CodingKeys: String, CodingKey { case id, name }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = ((try? c.decodeIfPresent(FlexibleString.self, forKey: .id)) ?? nil)?.value
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .access_token)
        scope = (try? c.decodeIfPresent(String.self, forKey: .scope)) ?? nil
        let athlete = (try? c.decodeIfPresent(Athlete.self, forKey: .athlete)) ?? nil
        athleteID = athlete?.id
        athleteName = athlete?.name
    }
}

/// `GET /athlete/0`: nur `id` und `name`, flach oder unter `athlete`.
private struct IntervalsAthleteResponse: Decodable {
    let name: String?

    private enum CodingKeys: String, CodingKey { case name, athlete }
    private struct Nested: Decodable { let name: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let flat = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        let nested = ((try? c.decodeIfPresent(Nested.self, forKey: .athlete)) ?? nil)?.name
        name = [flat, nested].compactMap { $0 }.first { !$0.isEmpty }
    }
}

private struct PlannedEvent: Encodable {
    let category = "WORKOUT"
    let type = "Ride"
    let start_date_local: String
    let name: String
    let filename: String
    let file_contents: String
    let external_id: String
    let moving_time: Int
}

// MARK: - gzip

/// Kleiner gunzip über Apples Compression-Framework (`COMPRESSION_ZLIB` ist rohes Deflate), streamend mit laufender Obergrenze.
public enum Gzip {
    public enum Failure: Error, Equatable { case malformed, tooLarge }
    /// Obergrenze für die entpackte Größe (ein 24-Stunden-FIT hat rund 10 MB).
    public static let defaultMaxOutput = 128 * 1024 * 1024

    /// Entpackt gzip; alles andere (kein `1f 8b` am Anfang) kommt unverändert zurück.
    public static func decompressIfNeeded(_ data: Data, maxOutput: Int = defaultMaxOutput) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 2, bytes[0] == 0x1f, bytes[1] == 0x8b else { return data }
        // Kopf (10) + mindestens ein Byte Deflate + Trailer (8).
        guard bytes.count >= 19, bytes[2] == 8 else { throw Failure.malformed }
        let flags = bytes[3]
        var position = 10
        if flags & 0x04 != 0 {                                   // FEXTRA: 2 Byte Länge + Daten
            guard position + 2 <= bytes.count else { throw Failure.malformed }
            position += 2 + Int(bytes[position]) + (Int(bytes[position + 1]) << 8)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 { // FNAME, FCOMMENT: nullterminiert
            guard position < bytes.count, let end = bytes[position...].firstIndex(of: 0) else { throw Failure.malformed }
            position = end + 1
        }
        if flags & 0x02 != 0 { position += 2 }                   // FHCRC
        let trailer = bytes.count - 8
        guard position < trailer else { throw Failure.malformed }
        let size = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[trailer + 4 + $1]) << (8 * UInt32($1)) }
        let out = try inflate(Array(bytes[position..<trailer]), maxOutput: maxOutput)
        guard UInt32(truncatingIfNeeded: out.count) == size else { throw Failure.malformed }
        return out
    }

    /// Rohes Deflate in 64-KB-Stücken; bricht ab, sobald mehr als `maxOutput` Byte entstehen (kein Vertrauen in ISIZE).
    private static func inflate(_ input: [UInt8], maxOutput: Int) throws -> Data {
        let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { scratch.deallocate() }
        var stream = compression_stream(dst_ptr: scratch, dst_size: 0, src_ptr: UnsafePointer(scratch), src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { throw Failure.malformed }
        defer { compression_stream_destroy(&stream) }
        let chunk = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunk)
        var out = Data()
        return try input.withUnsafeBufferPointer { source in
            stream.src_ptr = source.baseAddress!
            stream.src_size = source.count
            while true {
                let status: compression_status = buffer.withUnsafeMutableBufferPointer { target in
                    stream.dst_ptr = target.baseAddress!
                    stream.dst_size = chunk
                    return compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                }
                let produced = chunk - stream.dst_size
                if out.count + produced > maxOutput { throw Failure.tooLarge }
                out.append(contentsOf: buffer[0..<produced])
                switch status {
                case COMPRESSION_STATUS_END: return out
                case COMPRESSION_STATUS_OK: if produced == 0 { throw Failure.malformed }
                default: throw Failure.malformed
                }
            }
        }
    }
}

// MARK: - Redirect-sicherer Transport

/// Folgt Weiterleitungen nur innerhalb von https://intervals.icu – Zugangsdaten gehen nie an einen anderen Host.
public final class RestrictedRedirectTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!
    public override init() {
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    /// Reine Entscheidung: die neue Anfrage, wenn sie https, Host `intervals.icu` und Standard-Port hat, sonst nil (Abbruch).
    static func redirectDecision(original: URLRequest?, new: URLRequest) -> URLRequest? {
        guard let url = new.url, url.scheme == "https", url.host == "intervals.icu", url.port == nil, url.user == nil else { return nil }
        return new
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Self.redirectDecision(original: task.originalRequest, new: request))
    }
}

// MARK: - Client

public actor IntervalsClient {
    private let config: IntervalsConfig
    private let store: IntervalsCredentialStore
    private let transport: HTTPTransport
    private let sleep: @Sendable (Duration) async throws -> Void

    /// Wartezeit vor dem einen Wiederholungsversuch nach einem 5xx.
    static let serverErrorBackoff: Duration = .seconds(2)
    /// „Trennen“ ist Best Effort und darf nicht hängen.
    /// Größer als das ist keine Fahrt (komprimiert).
    public static let maxDownloadBytes = 32 * 1024 * 1024
    static let disconnectTimeout: TimeInterval = 10

    public init(config: IntervalsConfig, store: IntervalsCredentialStore, transport: HTTPTransport = RestrictedRedirectTransport(),
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.config = config
        self.store = store
        self.transport = transport
        self.sleep = sleep
    }

    // MARK: Anmelden

    /// Tauscht den Code aus der Rückleitung (PKCE, ohne Client-Secret) gegen das Zugriffstoken und speichert es.
    @discardableResult
    public func completeAuthorization(callbackURL: URL, expectedState: String, codeVerifier: String) async throws -> IntervalsCredential {
        guard config.isOAuthAvailable else { throw IntervalsError.notConfigured }
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if value("error") != nil { Log.error(.intervals, "OAuth: Zugriff verweigert"); throw IntervalsError.authorizationDenied }
        guard value("state") == expectedState else { Log.error(.intervals, "OAuth: state stimmt nicht"); throw IntervalsError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { Log.error(.intervals, "OAuth: kein Code im Callback"); throw IntervalsError.authorizationDenied }

        var request = URLRequest(url: URL(string: "\(IntervalsConfig.origin)/api/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = StravaClient.formEncode(["client_id": config.trimmedClientID, "code": code, "code_verifier": codeVerifier,
                                                    "grant_type": "authorization_code", "redirect_uri": config.redirectURI])
            .data(using: .utf8)
        // Der Code gilt nur einmal: kein Wiederholungsversuch.
        let data: Data
        do { (data, _) = try await send(request, retryServerErrors: false, redacting: [codeVerifier, code]) }
        catch IntervalsError.notConnected { throw IntervalsError.authorizationFailed }
        catch IntervalsError.forbidden { throw IntervalsError.authorizationFailed }
        catch IntervalsError.http(400, _) { throw IntervalsError.authorizationFailed }
        let token = try decode(IntervalsTokenResponse.self, from: data)
        if let scope = token.scope {
            let granted = Set(scope.split(whereSeparator: { $0 == "," || $0 == " " }).map { $0.uppercased() })
            guard IntervalsConfig.requiredScopes.isSubset(of: granted) else {
                Log.error(.intervals, "OAuth: Scope unvollständig")
                await revoke(.oauth(accessToken: token.accessToken, athleteID: nil, athleteName: nil)) // Best Effort
                throw IntervalsError.missingScope
            }
        }
        let credential = IntervalsCredential.oauth(accessToken: token.accessToken, athleteID: token.athleteID, athleteName: token.athleteName)
        guard store.saveCredential(credential) else {
            await revoke(credential)
            throw IntervalsError.keychainFailed
        }
        Log.notice(.intervals, "OAuth: Token-Austausch erfolgreich")
        return credential
    }

    /// Prüft den persönlichen API-Key mit `GET /athlete/0`, speichert ihn und liefert den Namen des Kontos.
    @discardableResult
    public func connect(apiKey: String) async throws -> String? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw IntervalsError.invalidAPIKey }
        let credential = IntervalsCredential.apiKey(key)
        var request = URLRequest(url: URL(string: "\(IntervalsConfig.origin)/api/v1/athlete/0")!)
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        let data: Data
        do { (data, _) = try await send(request, retryServerErrors: true, redacting: credential.secrets) }
        catch IntervalsError.notConnected { Log.error(.intervals, "API-Key abgelehnt"); throw IntervalsError.invalidAPIKey }
        catch IntervalsError.forbidden { Log.error(.intervals, "API-Key abgelehnt (403)"); throw IntervalsError.invalidAPIKey }
        let athlete = try decode(IntervalsAthleteResponse.self, from: data)
        guard store.saveCredential(credential) else { throw IntervalsError.keychainFailed }
        Log.notice(.intervals, "API-Key geprüft und gespeichert")
        return athlete.name
    }

    /// Der Zugang ist zuerst lokal weg (auch wenn die App mitten im Widerruf beendet wird), danach Best Effort bei OAuth
    /// `DELETE /disconnect-app` mit dem gemerkten Token.
    public func disconnect() async {
        let credential = store.loadCredential()
        store.saveCredential(nil)
        if let credential { await revoke(credential) }
    }

    /// Widerruft die OAuth-Freigabe (Best Effort, Fehler werden nur protokolliert). API-Keys kennen keinen Widerruf.
    private func revoke(_ credential: IntervalsCredential) async {
        guard case .oauth = credential else { return }
        var request = URLRequest(url: URL(string: "\(IntervalsConfig.origin)/api/v1/disconnect-app")!)
        request.httpMethod = "DELETE"
        request.timeoutInterval = Self.disconnectTimeout
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        do { _ = try await send(request, retryServerErrors: false, redacting: credential.secrets) }
        catch { Log.error(.intervals, "Widerruf bei intervals.icu nicht bestätigt: \(type(of: error))") }
    }

    // MARK: Pläne

    /// Legt die Einheiten im Kalender an oder ersetzt sie (`external_id` = Workout-UUID, `upsert=true`).
    /// Ein 5xx wird einmal wiederholt: der Upsert ist idempotent, ein doppelter Versuch erzeugt keinen zweiten Termin.
    public func upsertWorkouts(_ workouts: [IntervalsPlannedWorkout]) async throws {
        guard !workouts.isEmpty else { return }
        let formatter = Self.localTimeFormatter()
        let events = workouts.map {
            PlannedEvent(start_date_local: formatter.string(from: $0.start), name: $0.name, filename: $0.fileName,
                         file_contents: $0.zwo, external_id: $0.externalID, moving_time: $0.movingTime)
        }
        var request = URLRequest(url: URL(string: "\(IntervalsConfig.origin)/api/v1/athlete/0/events/bulk?upsert=true&upsertOnUid=false&updatePlanApplied=false")!)
        request.httpMethod = "POST"
        request.httpBody = try Self.jsonEncoder.encode(events)
        _ = try await authorizedSend(request, retryServerErrors: true)
        Log.notice(.intervals, "Plan gesendet: \(workouts.count) Einheiten")
    }

    /// Entfernt Termine anhand der `external_id`. Unbekannte werden von intervals.icu ignoriert (idempotent, also mit Wiederholung).
    public func deleteWorkouts(externalIDs: [String]) async throws {
        guard !externalIDs.isEmpty else { return }
        var request = URLRequest(url: URL(string: "\(IntervalsConfig.origin)/api/v1/athlete/0/events/bulk-delete")!)
        request.httpMethod = "PUT"
        request.httpBody = try Self.jsonEncoder.encode(externalIDs.map { ["external_id": $0] })
        _ = try await authorizedSend(request, retryServerErrors: true)
        Log.notice(.intervals, "Termine gelöscht: \(externalIDs.count)")
    }

    // MARK: Fahrten

    /// Aktivitäten im Zeitraum (Tage in Ortszeit, `newest` eingeschlossen). Ohne Strava-Einträge (die API liefert dazu keine Daten),
    /// ohne Nicht-Rad-Typen und ohne Einträge ohne ID.
    public func activities(oldest: Date, newest: Date) async throws -> [IntervalsActivity] {
        var c = URLComponents(string: "\(IntervalsConfig.origin)/api/v1/athlete/0/activities")!
        let day = Self.dayFormatter()
        c.queryItems = [URLQueryItem(name: "oldest", value: day.string(from: oldest)),
                        URLQueryItem(name: "newest", value: day.string(from: newest))]
        let (data, response) = try await authorizedSend(URLRequest(url: c.url!), retryServerErrors: true)
        let all = try decode([Lossy<IntervalsActivity>].self, from: data).compactMap(\.value)
        let kept = all.filter { !$0.isFromStrava && $0.isRide }
        Log.notice(.intervals, "Aktivitäten: HTTP \(response.statusCode), \(all.count) gelistet, \(kept.count) Fahrten, \(all.filter(\.isFromStrava).count) von Strava übersprungen")
        return kept
    }

    /// Originaldatei der Aktivität (meist gzip-komprimiert FIT); entpackt.
    public func downloadFIT(activityID: String, maxCompressedBytes: Int = IntervalsClient.maxDownloadBytes) async throws -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let escaped = activityID.addingPercentEncoding(withAllowedCharacters: allowed) ?? activityID
        guard let url = URL(string: "\(IntervalsConfig.origin)/api/v1/activity/\(escaped)/file") else { throw IntervalsError.http(400, "Ungültige Aktivität") }
        let (data, _) = try await authorizedSend(URLRequest(url: url), retryServerErrors: true)
        guard data.count <= maxCompressedBytes else { throw IntervalsError.http(200, "Datei zu groß") }
        do { return try Gzip.decompressIfNeeded(data) }
        catch { throw IntervalsError.http(200, "Datei nicht lesbar") }
    }

    // MARK: Anfragen

    private func authorizedSend(_ request: URLRequest, retryServerErrors: Bool) async throws -> (Data, HTTPURLResponse) {
        guard let credential = store.loadCredential() else { throw IntervalsError.notConnected }
        var request = request
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try await send(request, retryServerErrors: retryServerErrors, redacting: credential.secrets)
    }

    private func send(_ request: URLRequest, retryServerErrors: Bool, redacting secrets: [String]) async throws -> (Data, HTTPURLResponse) {
        // Zugangsdaten verlassen nie intervals.icu (auch nicht durch einen Fehler beim Zusammensetzen der URL).
        guard request.url?.scheme == "https", request.url?.host == "intervals.icu" else { throw IntervalsError.http(400, "Ungültige Adresse") }
        var result = try await transport.data(for: request)
        if retryServerErrors, (500...599).contains(result.1.statusCode) {
            try await sleep(Self.serverErrorBackoff)
            result = try await transport.data(for: request)
        }
        try Self.check(result.1, result.0, redacting: secrets)
        return result
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            Log.error(.intervals, "Antwort nicht lesbar: \(Swift.type(of: error))")
            throw IntervalsError.http(200, "Antwort nicht lesbar")
        }
    }

    /// Übersetzt HTTP-Fehler. Serverantworten werden geschwärzt (bekannte Geheimnisse, Schlüssel-Muster) und gekürzt.
    static func check(_ response: HTTPURLResponse, _ data: Data, redacting secrets: [String] = [], now: Date = .now) throws {
        if !(200..<300).contains(response.statusCode) { Log.error(.intervals, "HTTP \(response.statusCode) \(response.url?.path ?? "")") }
        switch response.statusCode {
        case 200..<300: return
        case 401: throw IntervalsError.notConnected
        case 403: throw IntervalsError.forbidden
        case 429: throw IntervalsError.rateLimited(retryAfter: StravaClient.retryAfter(from: response, now: now))
        case 500...599: throw IntervalsError.unavailable(response.statusCode)
        default:
            let text = Redactor.scrub(String(decoding: data.prefix(1_000), as: UTF8.self), knownSecrets: secrets)
            throw IntervalsError.http(response.statusCode, text.count > 200 ? String(text.prefix(199)) + "…" : text)
        }
    }

    // MARK: Formate

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    /// `yyyy-MM-dd'T'HH:mm:ss` in Ortszeit (ohne Zeitzone, wie `start_date_local`).
    static func localTimeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }

    static func dayFormatter() -> DateFormatter {
        let f = localTimeFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
