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

    public init(providerID: String, model: String, endpoint: URL, apiKey: String) {
        executorConfiguration = .init(
            providerID: providerID, model: model, endpoint: endpoint, apiKey: apiKey
        )
    }
}

public struct OpenAICompatibleExecutor: LanguageModelExecutor {
    public struct Configuration: Hashable, Sendable {
        public var providerID: String
        public var model: String
        public var endpoint: URL
        public var apiKey: String

        public init(providerID: String, model: String, endpoint: URL, apiKey: String) {
            self.providerID = providerID
            self.model = model
            self.endpoint = endpoint
            self.apiKey = apiKey
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
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
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
        var bridge = ExecutorChannelBridge(requestID: request.id, providerID: configuration.providerID)
        try await ExecutorRequestEncoding.consumeEventStream(
            bytes: bytes, providerID: configuration.providerID,
            parseLine: { line, lineNumber in try parser.consume(line, lineNumber: lineNumber) },
            onEvent: { event in
                for channelEvent in bridge.channelEvents(for: event) {
                    await channel.send(channelEvent)
                }
            }
        )
    }
}
