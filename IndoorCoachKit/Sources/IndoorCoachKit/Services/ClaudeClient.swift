import Foundation

public enum ClaudeError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case overloaded
    case refusal(String?)
    case truncated
    case badResponse(String)
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Kein Claude-API-Key hinterlegt (Profil → Claude)."
        case .invalidAPIKey: "Der Claude-API-Key wurde abgelehnt. Bitte in der Claude Console prüfen."
        case .rateLimited: "Claude-Ratenlimit erreicht – bitte kurz warten."
        case .overloaded: "Claude ist gerade überlastet – bitte gleich erneut versuchen."
        case let .refusal(reason): "Claude hat die Anfrage abgelehnt\(reason.map { " (\($0))" } ?? "")."
        case .truncated: "Die Antwort von Claude war unvollständig. Bitte erneut versuchen oder den Zeitraum verkürzen."
        case let .badResponse(detail): "Unerwartete Antwort von Claude: \(detail)"
        case let .http(code, message): "Claude-Fehler \(code): \(message)"
        }
    }
}

/// Minimal Messages API client (raw HTTP – there is no official Swift SDK).
public struct ClaudeClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2026-10-21"
    /// Server-side refusal fallback (routes a refused request to a suitable fallback model).
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    let apiKey: String
    let model: String
    let transport: HTTPTransport

    public init(apiKey: String, model: String = ClaudeModel.default.rawValue, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.model = model
        self.transport = transport
    }

    public struct Usage: Decodable, Sendable, Equatable {
        public let input_tokens: Int
        public let output_tokens: Int
    }

    public struct Result: Sendable {
        public let text: String
        public let usage: Usage?
        public let model: String?
    }

    /// Builds the request body; exposed for tests.
    func requestBody(system: String, user: String, schema: [String: Any], effort: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema]
            ],
            "fallbacks": "default"
        ]
    }

    func makeRequest(body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300 // planning with adaptive thinking can take a while
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// Sends one structured-output request and returns the JSON text. Retries once on 429/529.
    public func structuredJSON(system: String, user: String, schema: [String: Any], effort: String = "medium") async throws -> Result {
        guard !apiKey.isEmpty else { throw ClaudeError.missingAPIKey }
        var body = requestBody(system: system, user: user, schema: schema, effort: effort)
        var request = try makeRequest(body: body)
        var attempt = 0
        var usedFallbackFeature = true
        while true {
            attempt += 1
            let (data, response) = try await transport.data(for: request)
            switch response.statusCode {
            case 200..<300:
                return try Self.parseResponse(data)
            case 401, 403:
                throw ClaudeError.invalidAPIKey
            case 400 where usedFallbackFeature && Self.errorMessage(from: data).lowercased().contains("fallback"):
                // Safety net: if the refusal-fallback beta is not available for this key/model, retry without it.
                usedFallbackFeature = false
                body["fallbacks"] = nil
                request = try makeRequest(body: body)
                request.setValue(nil, forHTTPHeaderField: "anthropic-beta")
                continue
            case 429, 529:
                if attempt < 2 {
                    let wait = Double(response.value(forHTTPHeaderField: "retry-after") ?? "") ?? 5
                    try await Task.sleep(for: .seconds(min(wait, 20)))
                    continue
                }
                throw response.statusCode == 429 ? ClaudeError.rateLimited : ClaudeError.overloaded
            default:
                throw ClaudeError.http(response.statusCode, Self.errorMessage(from: data))
            }
        }
    }

    struct MessageResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        struct StopDetails: Decodable { let category: String?; let explanation: String? }
        let content: [Block]
        let stop_reason: String?
        let stop_details: StopDetails?
        let usage: Usage?
        let model: String?
    }

    static func parseResponse(_ data: Data) throws -> Result {
        let message: MessageResponse
        do { message = try JSONDecoder().decode(MessageResponse.self, from: data) }
        catch { throw ClaudeError.badResponse("JSON nicht lesbar") }
        switch message.stop_reason {
        case "refusal": throw ClaudeError.refusal(message.stop_details?.category)
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw ClaudeError.badResponse("kein Text") }
        return Result(text: text, usage: message.usage, model: message.model)
    }

    static func errorMessage(from data: Data) -> String {
        struct APIError: Decodable { struct Inner: Decodable { let message: String }; let error: Inner }
        let raw = (try? JSONDecoder().decode(APIError.self, from: data))?.error.message
            ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
        return redact(raw)
    }

    /// Strips anything that looks like an API key and truncates – server text ends up in the UI.
    public static func redact(_ text: String) -> String {
        let redacted = text.replacingOccurrences(of: #"sk-ant-[A-Za-z0-9_\-]+"#, with: "sk-ant-…", options: .regularExpression)
        return redacted.count > 200 ? String(redacted.prefix(199)) + "…" : redacted
    }
}

/// Produces training plans – either via Claude or the offline demo planner.
public protocol Coach: Sendable {
    func plan(_ context: PlanContext) async throws -> PlanProposal
}

public struct ClaudeCoach: Coach {
    let client: ClaudeClient
    public init(client: ClaudeClient) { self.client = client }

    public func plan(_ context: PlanContext) async throws -> PlanProposal {
        let result = try await client.structuredJSON(system: PlanPrompt.system,
                                                     user: PlanPrompt.userMessage(context),
                                                     schema: PlanPrompt.schema)
        do {
            return try PlanPrompt.parse(result.text, context: context)
        } catch {
            throw ClaudeError.badResponse("Plan konnte nicht gelesen werden")
        }
    }
}
