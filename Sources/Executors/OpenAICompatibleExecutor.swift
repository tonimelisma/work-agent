import CryptoKit
import Foundation
import FoundationModels
import ToolVocabulary

// REQ: NFR-001, NFR-010 — one executor serves all
// nine curated OpenAI-compatible providers (including Google's /v1beta/openai and
// MiniMax's /v1); adding a provider is a `Configuration` value, never a new type.
// Migrated from Experiments/FoundationModelsPOC's OpenAICompatibleLiveExecutor,
// proven live against DeepSeek and Google (increment 3).
public struct OpenAICompatibleModel: LanguageModel {
    public typealias Executor = OpenAICompatibleExecutor

    public let capabilities = LanguageModelCapabilities([.reasoning, .toolCalling])
    public let executorConfiguration: OpenAICompatibleExecutor.Configuration

    public init(
        providerID: String, model: String, endpoint: URL, apiKey: String,
        authStyle: OpenAICompatibleExecutor.Configuration.AuthStyle = .bearer
    ) {
        executorConfiguration = .init(
            providerID: providerID, model: model, endpoint: endpoint, apiKey: apiKey, authStyle: authStyle
        )
    }
}

public struct OpenAICompatibleExecutor: LanguageModelExecutor {
    public struct Configuration: Hashable, Sendable {
        // REQ: GLM (Zhipu) rejects a raw bearer token — see
        // research/provider-chat-endpoints.md "The Zhipu/GLM wrinkle" — and requires an
        // HS256 JWT signed from the `id.secret`-shaped API key instead. `.bearer` covers
        // every other curated provider unchanged.
        public enum AuthStyle: Hashable, Sendable {
            case bearer
            case zhipuJWT
        }

        public var providerID: String
        public var model: String
        public var endpoint: URL
        public var apiKey: String
        public var authStyle: AuthStyle

        public init(
            providerID: String, model: String, endpoint: URL, apiKey: String, authStyle: AuthStyle = .bearer
        ) {
            self.providerID = providerID
            self.model = model
            self.endpoint = endpoint
            self.apiKey = apiKey
            self.authStyle = authStyle
        }
    }

    public typealias Model = OpenAICompatibleModel
    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: OpenAICompatibleModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        switch configuration.authStyle {
        case .bearer:
            urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        case .zhipuJWT:
            let token = try ZhipuJWT.token(apiKey: configuration.apiKey)
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": configuration.model,
            "messages": try ExecutorRequestEncoding.openAIMessages(
                from: request.transcript,
                providerID: configuration.providerID
            ),
            "tools": try ExecutorRequestEncoding.openAITools(request.enabledToolDefinitions),
            "stream": true,
            "stream_options": ["include_usage": true],
        ]
        if request.generationOptions.toolCallingMode == .required {
            body["tool_choice"] = "required"
        } else if request.generationOptions.toolCallingMode == .disallowed {
            body["tool_choice"] = "none"
        } else {
            body["tool_choice"] = "auto"
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        let httpResponse = try await ExecutorRequestEncoding.validate(
            response: response, bytes: bytes, providerID: configuration.providerID
        )
        try await ExecutorRequestEncoding.assertEventStream(
            response: httpResponse, bytes: bytes, providerID: configuration.providerID
        )

        var parser = OpenAICompatibleStreamParser()
        var bridge = ExecutorChannelBridge(
            requestID: request.id, providerID: configuration.providerID,
            toolCallsPossible: !request.enabledToolDefinitions.isEmpty
        )
        try await ExecutorRequestEncoding.consumeEventStream(
            bytes: bytes, providerID: configuration.providerID,
            parseLine: { line, lineNumber in try parser.consume(line, lineNumber: lineNumber) },
            onEvent: { event in
                for channelEvent in bridge.channelEvents(for: event) {
                    await channel.send(channelEvent)
                }
            }
        )
        for channelEvent in try bridge.completionEvents() {
            await channel.send(channelEvent)
        }
    }
}

enum ZhipuAuthError: LocalizedError, Equatable, Sendable {
    case malformedAPIKey

    var errorDescription: String? {
        switch self {
        case .malformedAPIKey: "Zhipu API key is not in the expected \"id.secret\" format"
        }
    }
}

/// Zhipu/GLM rejects the raw `ZHIPU_API_KEY` as a bearer token at both `open.bigmodel.cn`
/// and `api.z.ai` (research/provider-chat-endpoints.md "The Zhipu/GLM wrinkle"); it wants
/// an HS256 JWT signed from the key's `id` half using the `secret` half. `now` is an
/// injected parameter (not `Date()` inline) so the exact token string is reproducible
/// under test.
enum ZhipuJWT {
    static func token(apiKey: String, now: Date = Date()) throws -> String {
        let parts = apiKey.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw ZhipuAuthError.malformedAPIKey
        }
        let id = String(parts[0])
        let secret = String(parts[1])

        let nowMilliseconds = Int(now.timeIntervalSince1970 * 1_000)
        let header: [String: Any] = ["alg": "HS256", "sign_type": "SIGN"]
        let payload: [String: Any] = [
            "api_key": id,
            "exp": nowMilliseconds + 3_600_000,
            "timestamp": nowMilliseconds,
        ]

        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let signingInput = "\(base64URL(headerData)).\(base64URL(payloadData))"

        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
        return "\(signingInput).\(base64URL(Data(signature)))"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
