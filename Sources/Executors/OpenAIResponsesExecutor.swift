import Foundation
import FoundationModels
import ToolVocabulary

// REQ: FR-085 — the third executor. `gpt-5.6` cannot tool-call on
// `/v1/chat/completions` at all (HTTP 400: "Function tools with reasoning_effort
// are not supported ... use /v1/responses or set reasoning_effort to 'none'"), and
// degrading reasoning to none to keep the old path would neuter the model. The
// Responses API is a genuinely different wire shape — flat tool declarations, an
// item list instead of `messages`, typed SSE events — so it earns its own executor,
// on the same rule ENGINEERING.md already applies to Anthropic: a distinct wire
// format earns a distinct executor, a shared one never does.
public struct OpenAIResponsesModel: LanguageModel {
    public typealias Executor = OpenAIResponsesExecutor

    public let capabilities = LanguageModelCapabilities([.reasoning, .toolCalling])
    public let executorConfiguration: OpenAIResponsesExecutor.Configuration

    public init(
        model: String,
        apiKey: String,
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        providerID: String = "openai"
    ) {
        executorConfiguration = .init(
            providerID: providerID, model: model, endpoint: endpoint, apiKey: apiKey
        )
    }
}

public struct OpenAIResponsesExecutor: LanguageModelExecutor {
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

    public typealias Model = OpenAIResponsesModel
    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model _: OpenAIResponsesModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: Self.requestBody(model: configuration.model, request: request)
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        let httpResponse = try await ExecutorRequestEncoding.validate(
            response: response, bytes: bytes, providerID: configuration.providerID
        )
        try await ExecutorRequestEncoding.assertEventStream(
            response: httpResponse, bytes: bytes, providerID: configuration.providerID
        )

        var parser = OpenAIResponsesStreamParser()
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

    /// Pure request-body construction, pulled out of `respond` so the item encoding
    /// and the reasoning mapping are testable without a network stub — the same
    /// seam `AnthropicExecutor.requestBody` provides.
    static func requestBody(
        model: String, request: LanguageModelExecutorGenerationRequest
    ) throws -> [String: Any] {
        let encoded = try ExecutorRequestEncoding.openAIResponsesInput(from: request.transcript)
        var body: [String: Any] = [
            "model": model,
            "input": encoded.items,
            "tools": try ExecutorRequestEncoding.openAIResponsesTools(request.enabledToolDefinitions),
            "stream": true,
            // `store: false` keeps conversation state out of OpenAI's servers — this
            // package is local-first — which in turn makes replaying the encrypted
            // reasoning items on every follow-up request mandatory, not optional.
            "store": false,
            "include": ["reasoning.encrypted_content"],
        ]
        if !encoded.instructions.isEmpty { body["instructions"] = encoded.instructions }
        if let maximum = request.generationOptions.maximumResponseTokens {
            body["max_output_tokens"] = maximum
        }
        if let level = request.contextOptions.reasoningLevel {
            body["reasoning"] = ["effort": AnthropicExecutor.effort(for: level)]
        }
        switch request.generationOptions.toolCallingMode {
        case .required: body["tool_choice"] = "required"
        case .disallowed: body["tool_choice"] = "none"
        default: body["tool_choice"] = "auto"
        }
        return body
    }
}
