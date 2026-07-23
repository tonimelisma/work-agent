import Foundation
import FoundationModels
import ToolVocabulary

// REQ: our own Anthropic executor (the vendor package is beta/BYOK-hostile —
// see ENGINEERING.md "Three executors, not eleven"). Migrated from the pre-pivot
// Foundation Models POC's AnthropicLiveExecutor, proven live (increment 3).
public struct AnthropicModel: LanguageModel {
    public typealias Executor = AnthropicExecutor

    public let capabilities = LanguageModelCapabilities([.reasoning, .toolCalling])
    public let executorConfiguration: AnthropicExecutor.Configuration

    public init(
        model: String,
        apiKey: String,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        providerID: String = "anthropic"
    ) {
        executorConfiguration = .init(
            model: model, apiKey: apiKey, endpoint: endpoint, providerID: providerID
        )
    }
}

public struct AnthropicExecutor: LanguageModelExecutor {
    public struct Configuration: Hashable, Sendable {
        public var model: String
        public var apiKey: String
        public var endpoint: URL
        public var providerID: String

        public init(
            model: String,
            apiKey: String,
            endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
            providerID: String = "anthropic"
        ) {
            self.model = model
            self.apiKey = apiKey
            self.endpoint = endpoint
            self.providerID = providerID
        }
    }

    public typealias Model = AnthropicModel
    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: AnthropicModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = try AnthropicExecutor.requestBody(
            model: configuration.model, request: request, providerID: configuration.providerID
        )
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        let httpResponse = try await ExecutorRequestEncoding.validate(
            response: response, bytes: bytes, providerID: configuration.providerID
        )
        try await ExecutorRequestEncoding.assertEventStream(
            response: httpResponse, bytes: bytes, providerID: configuration.providerID
        )

        var parser = AnthropicStreamParser(providerID: configuration.providerID)
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

    /// Maps Apple's `ContextOptions.ReasoningLevel` (verified against the OS 27
    /// swiftinterface: `.light`/`.moderate`/`.deep`/`.custom(String)` — not the
    /// low/medium/high names this mapping was first guessed at) to Anthropic's
    /// `output_config.effort` string. `.custom` passes its value straight through;
    /// an unrecognized future case falls back to the nearest named level.
    static func effort(for level: ContextOptions.ReasoningLevel) -> String {
        switch level {
        case .light: "low"
        case .moderate: "medium"
        case .deep: "high"
        case let .custom(value): value
        @unknown default: "medium"
        }
    }

    /// Pure request-body construction, pulled out of `respond` so the
    /// `output_config`/`reasoningLevel` mapping is testable without a network stub.
    static func requestBody(
        model: String,
        request: LanguageModelExecutorGenerationRequest,
        providerID: String = "anthropic"
    ) throws -> [String: Any] {
        let encoded = try ExecutorRequestEncoding.anthropicMessages(
            from: request.transcript, providerID: providerID
        )
        var body: [String: Any] = [
            "model": model,
            "max_tokens": request.generationOptions.maximumResponseTokens ?? 4_096,
            "messages": encoded.messages,
            "tools": try ExecutorRequestEncoding.anthropicTools(request.enabledToolDefinitions),
            "thinking": ["type": "adaptive"],
            "stream": true,
        ]
        // `output_config.effort` is omitted entirely (provider default) unless the
        // caller asked for a specific level — every request no longer pays for max
        // effort unconditionally.
        if let level = request.contextOptions.reasoningLevel {
            body["output_config"] = ["effort": effort(for: level)]
        }
        if !encoded.system.isEmpty { body["system"] = encoded.system }
        if request.generationOptions.toolCallingMode == .required {
            body["tool_choice"] = ["type": "any"]
        } else if request.generationOptions.toolCallingMode == .disallowed {
            body["tools"] = []
        } else {
            body["tool_choice"] = ["type": "auto"]
        }
        return body
    }
}

public enum LiveExecutorError: LocalizedError, Equatable, Sendable {
    case invalidHTTPResponse(provider: String)
    case httpFailure(provider: String, status: Int, message: String)
    case unsupportedTranscriptSegment(entryID: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidHTTPResponse(provider):
            "\(provider) returned a non-HTTP response"
        case let .httpFailure(provider, status, message):
            "\(provider) returned HTTP \(status): \(message)"
        case let .unsupportedTranscriptSegment(entryID):
            "Cannot translate non-text transcript segment in entry \(entryID)"
        }
    }
}

enum ExecutorRequestEncoding {
    struct AnthropicRequest {
        var system: String
        var messages: [[String: Any]]
    }

    /// On a non-2xx response, drains up to 16 KB of the body so the provider's own
    /// error text (rate limit reason, validation message, etc.) survives into the
    /// error description instead of being discarded along with the response.
    @discardableResult
    static func validate(
        response: URLResponse, bytes: URLSession.AsyncBytes, providerID: String
    ) async throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else {
            throw LiveExecutorError.invalidHTTPResponse(provider: providerID)
        }
        guard 200 ..< 300 ~= response.statusCode else {
            let prefix = try await drainPrefix(of: bytes, maximumBytes: 16_384)
            throw LiveExecutorError.httpFailure(provider: providerID, status: response.statusCode, message: prefix)
        }
        return response
    }

    /// A 200 with a non-SSE body (a provider's plain-JSON error page, say) must not
    /// read as a silent empty reply: check Content-Type first so the diagnostic names
    /// what actually came back, draining a bounded prefix for the error message.
    static func assertEventStream(
        response: HTTPURLResponse, bytes: URLSession.AsyncBytes, providerID: String
    ) async throws {
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard contentType.contains("text/event-stream") else {
            let prefix = try await drainPrefix(of: bytes, maximumBytes: 16_384)
            throw ProviderStreamError.event(provider: providerID, type: "non_sse_response", message: prefix)
        }
    }

    /// Belt-and-braces to `assertEventStream`: a correctly-labeled SSE response that
    /// still produces zero events (an empty body, or a stream of blank keep-alives)
    /// must not read as a silent empty reply either.
    static func consumeEventStream(
        bytes: URLSession.AsyncBytes,
        providerID: String,
        parseLine: (String, Int) throws -> [ExecutorEvent],
        onEvent: (ExecutorEvent) async -> Void
    ) async throws {
        var lineNumber = 0
        var producedAnyEvent = false
        for try await line in bytes.lines {
            lineNumber += 1
            let events = try parseLine(line, lineNumber)
            if !events.isEmpty { producedAnyEvent = true }
            for event in events { await onEvent(event) }
        }
        guard producedAnyEvent else {
            throw ProviderStreamError.event(provider: providerID, type: "non_sse_response", message: "empty stream")
        }
    }

    private static func drainPrefix(of bytes: URLSession.AsyncBytes, maximumBytes: Int) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= maximumBytes { break }
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func openAITools(_ definitions: [Transcript.ToolDefinition]) throws -> [[String: Any]] {
        try definitions.map { definition in
            [
                "type": "function",
                "function": [
                    "name": definition.name,
                    "description": definition.description,
                    "parameters": try schemaObject(definition.parameters),
                ],
            ]
        }
    }

    static func anthropicTools(_ definitions: [Transcript.ToolDefinition]) throws -> [[String: Any]] {
        try definitions.map { definition in
            [
                "name": definition.name,
                "description": definition.description,
                "input_schema": try schemaObject(definition.parameters),
            ]
        }
    }

    static func openAIMessages(from transcript: Transcript, providerID: String) throws -> [[String: Any]] {
        var messages: [[String: Any]] = []
        var assistantContent = ""
        var assistantReasoning = ""
        var assistantMetadata: [String: Any] = [:]
        var assistantTools: [[String: Any]] = []

        func flushAssistant() {
            guard !assistantContent.isEmpty || !assistantReasoning.isEmpty || !assistantTools.isEmpty else {
                return
            }
            var message: [String: Any] = ["role": "assistant"]
            message["content"] = assistantContent.isEmpty ? NSNull() : assistantContent
            if !assistantReasoning.isEmpty { message["reasoning_content"] = assistantReasoning }
            if !assistantTools.isEmpty { message["tool_calls"] = assistantTools }
            for (key, value) in assistantMetadata { message[key] = value }
            messages.append(message)
            assistantContent = ""
            assistantReasoning = ""
            assistantMetadata = [:]
            assistantTools = []
        }

        for entry in transcript {
            switch entry {
            case let .instructions(instructions):
                flushAssistant()
                let text = try text(from: instructions.segments, entryID: instructions.id)
                if !text.isEmpty { messages.append(["role": "system", "content": text]) }

            case let .prompt(prompt):
                flushAssistant()
                messages.append([
                    "role": "user",
                    "content": try text(from: prompt.segments, entryID: prompt.id),
                ])

            case let .reasoning(reasoning):
                let owner = reasoning.metadata[TranscriptMetadataKeys.signatureProvider] as? String
                guard owner == providerID else { continue }
                assistantReasoning += try text(from: reasoning.segments, entryID: reasoning.id)
                if let signature = reasoning.metadata["google.thought_signature"] as? String {
                    assistantMetadata["extra_content"] = ["google": ["thought_signature": signature]]
                }

            case let .toolCalls(calls):
                for call in calls {
                    var encoded: [String: Any] = [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.toolName,
                            "arguments": toolCallArguments(call.arguments.jsonString),
                        ],
                    ]
                    if let signature = call.metadata["google.thought_signature"] as? String {
                        encoded["extra_content"] = ["google": ["thought_signature": signature]]
                    }
                    assistantTools.append(encoded)
                }

            case let .toolOutput(output):
                flushAssistant()
                messages.append([
                    "role": "tool",
                    "tool_call_id": output.id,
                    "content": try text(from: output.segments, entryID: output.id),
                ])

            case let .response(response):
                assistantContent += try text(from: response.segments, entryID: response.id)

            @unknown default:
                throw LiveExecutorError.unsupportedTranscriptSegment(entryID: entry.id)
            }
        }
        flushAssistant()
        return messages
    }

    struct OpenAIResponsesRequest {
        var instructions: String
        var items: [[String: Any]]
    }

    /// REQ: FR-085 — the Responses API declares tools flat, not nested under a
    /// `function` object the way Chat Completions does. Verified live 2026-07-21.
    static func openAIResponsesTools(_ definitions: [Transcript.ToolDefinition]) throws -> [[String: Any]] {
        try definitions.map { definition in
            [
                "type": "function",
                "name": definition.name,
                "description": definition.description,
                "parameters": try schemaObject(definition.parameters),
            ]
        }
    }

    /// REQ: FR-085 — the Responses API takes a flat list of conversation *items*,
    /// not role-keyed messages: a tool call is a `function_call` item and its result
    /// a sibling `function_call_output`, never an assistant message with a
    /// `tool_calls` array. Reasoning items replay verbatim from the metadata the
    /// parser stored, which is what makes a reasoning model's follow-up turn work
    /// under `store: false`.
    static func openAIResponsesInput(from transcript: Transcript) throws -> OpenAIResponsesRequest {
        var instructionParts: [String] = []
        var items: [[String: Any]] = []

        for entry in transcript {
            switch entry {
            case let .instructions(instructions):
                let value = try text(from: instructions.segments, entryID: instructions.id)
                if !value.isEmpty { instructionParts.append(value) }

            case let .prompt(prompt):
                items.append([
                    "role": "user",
                    "content": try text(from: prompt.segments, entryID: prompt.id),
                ])

            case let .reasoning(reasoning):
                guard reasoning.metadata[TranscriptMetadataKeys.signatureProvider] as? String == "openai",
                      let raw = reasoning.metadata["openai.reasoning_item"] as? String,
                      let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
                else { continue }
                items.append(object)

            case let .toolCalls(calls):
                for call in calls {
                    items.append([
                        "type": "function_call",
                        "call_id": call.id,
                        "name": call.toolName,
                        "arguments": toolCallArguments(call.arguments.jsonString),
                    ])
                }

            case let .toolOutput(output):
                items.append([
                    "type": "function_call_output",
                    "call_id": output.id,
                    "output": try text(from: output.segments, entryID: output.id),
                ])

            case let .response(response):
                let value = try text(from: response.segments, entryID: response.id)
                if !value.isEmpty {
                    items.append([
                        "role": "assistant",
                        "content": [["type": "output_text", "text": value]],
                    ])
                }

            @unknown default:
                throw LiveExecutorError.unsupportedTranscriptSegment(entryID: entry.id)
            }
        }
        return OpenAIResponsesRequest(
            instructions: instructionParts.joined(separator: "\n\n"), items: items
        )
    }

    static func anthropicMessages(
        from transcript: Transcript, providerID: String = "anthropic"
    ) throws -> AnthropicRequest {
        var systemParts: [String] = []
        var messages: [[String: Any]] = []
        var assistantBlocks: [[String: Any]] = []

        func flushAssistant() {
            guard !assistantBlocks.isEmpty else { return }
            messages.append(["role": "assistant", "content": assistantBlocks])
            assistantBlocks = []
        }

        for entry in transcript {
            switch entry {
            case let .instructions(instructions):
                let value = try text(from: instructions.segments, entryID: instructions.id)
                if !value.isEmpty { systemParts.append(value) }

            case let .prompt(prompt):
                flushAssistant()
                messages.append([
                    "role": "user",
                    "content": try text(from: prompt.segments, entryID: prompt.id),
                ])

            case let .reasoning(reasoning):
                let owner = reasoning.metadata[TranscriptMetadataKeys.signatureProvider] as? String
                guard owner == providerID else { continue }
                // redacted_thinking blocks round-trip independently of a signed
                // thinking block — a response can carry either or both. Ordered
                // before the thinking block: an approximation of arrival order,
                // since Anthropic validates block presence/content, not exact
                // interleaving with the signed block.
                if let redactedJSON = reasoning.metadata["anthropic.redacted_thinking"] as? String {
                    for value in decodedRedactedThinking(redactedJSON) {
                        assistantBlocks.append(["type": "redacted_thinking", "data": value])
                    }
                }
                if let signatureData = reasoning.signature,
                   let signature = String(data: signatureData, encoding: .utf8) {
                    assistantBlocks.append([
                        "type": "thinking",
                        "thinking": try text(from: reasoning.segments, entryID: reasoning.id),
                        "signature": signature,
                    ])
                }

            case let .toolCalls(calls):
                for call in calls {
                    assistantBlocks.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.toolName,
                        "input": try JSONSerialization.jsonObject(
                            with: Data(toolCallArguments(call.arguments.jsonString).utf8)
                        ),
                    ])
                }

            case let .toolOutput(output):
                flushAssistant()
                messages.append([
                    "role": "user",
                    "content": [[
                        "type": "tool_result",
                        "tool_use_id": output.id,
                        "content": try text(from: output.segments, entryID: output.id),
                    ]],
                ])

            case let .response(response):
                let value = try text(from: response.segments, entryID: response.id)
                if !value.isEmpty { assistantBlocks.append(["type": "text", "text": value]) }

            @unknown default:
                throw LiveExecutorError.unsupportedTranscriptSegment(entryID: entry.id)
            }
        }
        flushAssistant()
        return AnthropicRequest(system: systemParts.joined(separator: "\n\n"), messages: messages)
    }

    /// The bridge writes this key as a JSON array, but a value written by any other
    /// path — a hand-built transcript, a future non-bridge writer — must not drop
    /// silently: an undecodable value is treated as one opaque blob.
    static func decodedRedactedThinking(_ value: String) -> [String] {
        guard !value.isEmpty else { return [] }
        if let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        return [value]
    }

    /// A provider can emit a tool call with no arguments at all (Meta streams
    /// `"arguments": ""` when the model passes none). Replaying that verbatim is
    /// rejected — Meta's own API answers HTTP 400 `arguments must be valid JSON`,
    /// and `anthropicMessages` would throw parsing it — so the empty case becomes
    /// the empty object it means.
    static func toolCallArguments(_ jsonString: String) -> String {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "{}" : trimmed
    }

    private static func schemaObject(_ schema: GenerationSchema) throws -> Any {
        let data = try JSONEncoder().encode(schema)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func text(from segments: [Transcript.Segment], entryID: String) throws -> String {
        try segments.map { segment in
            guard case let .text(text) = segment else {
                throw LiveExecutorError.unsupportedTranscriptSegment(entryID: entryID)
            }
            return text.content
        }.joined()
    }
}

struct ExecutorChannelBridge {
    private let responseEntryID: String
    private let reasoningEntryID: String
    private let toolCallsEntryID: String
    private let providerID: String
    private let toolCallsPossible: Bool
    private var sawResponse = false
    private var sawReasoning = false
    private var sawToolCall = false
    private var lastFinishReason: String?
    // REQ: FR-084 — assistant text is held here instead of streamed while a tool
    // call is still possible; see `completionEvents()` for why it cannot be sent
    // eagerly.
    private var pendingResponseText = ""
    // Usage is deferred to `completionEvents()` for the same reason: which entry
    // it belongs to is only knowable once the whole stream has been seen, and an
    // `updateUsage` must not land on an entry the buffer has not created yet.
    private var pendingUsage: (input: Int, output: Int)?
    // Multiple redacted_thinking blocks can arrive per response; each metadata
    // update replaces the key, so the running set is kept here and re-encoded
    // as a JSON array on every reasoning event, not just appended in place.
    private var redactedThinkingData: [String] = []

    /// - Parameter toolCallsPossible: whether this generation has any tool enabled.
    ///   When it doesn't, no tool call can arrive and response text streams
    ///   immediately, exactly as a plain chat turn always has.
    init(requestID: UUID, providerID: String, toolCallsPossible: Bool) {
        responseEntryID = "response-\(requestID.uuidString)"
        reasoningEntryID = "reasoning-\(requestID.uuidString)"
        toolCallsEntryID = "tool-calls-\(requestID.uuidString)"
        self.providerID = providerID
        self.toolCallsPossible = toolCallsPossible
    }

    mutating func channelEvents(
        for event: ExecutorEvent
    ) -> [LanguageModelExecutorGenerationChannel.Event] {
        switch event {
        case let .response(text):
            guard !text.isEmpty else { return [] }
            sawResponse = true
            guard toolCallsPossible else {
                return [.response(
                    entryID: responseEntryID,
                    action: .appendText(text, tokenCount: estimatedTokens(text))
                )]
            }
            pendingResponseText += text
            return []

        case let .reasoning(text, signature, metadata):
            sawReasoning = true
            var events: [LanguageModelExecutorGenerationChannel.Event] = []
            if !text.isEmpty {
                events.append(.reasoning(
                    entryID: reasoningEntryID,
                    action: .appendText(text, tokenCount: estimatedTokens(text))
                ))
            }
            if let signature, !signature.isEmpty {
                events.append(.reasoning(
                    entryID: reasoningEntryID,
                    action: .updateSignature(Data(signature.utf8), tokenCount: 1)
                ))
            }
            var values: [String: any Sendable & Codable & Equatable] = metadata
            if let redacted = metadata["anthropic.redacted_thinking"] {
                let (updated, json) = Self.accumulatedRedactedThinkingJSON(
                    appending: redacted, to: redactedThinkingData
                )
                redactedThinkingData = updated
                values["anthropic.redacted_thinking"] = json
            } else if !redactedThinkingData.isEmpty {
                // A redacted block arrives at index 0, ahead of the thinking block's
                // own deltas and its terminal signature_delta — every one of which
                // produces a metadata update that does *not* carry the redacted key.
                // Apple's `updateMetadata` merge-vs-replace semantics are
                // undocumented and unobservable from outside the framework, so the
                // accumulated array is restated on every update: a no-op if it
                // merges, and the difference between working and silently losing
                // the blocks if it replaces.
                values["anthropic.redacted_thinking"] = Self.redactedThinkingJSON(redactedThinkingData)
            }
            values[TranscriptMetadataKeys.signatureProvider] = providerID
            events.append(.reasoning(entryID: reasoningEntryID, action: .updateMetadata(values)))
            return events

        case let .toolCall(_, id, name, argumentsFragment, metadata):
            sawToolCall = true
            var events: [LanguageModelExecutorGenerationChannel.Event] = [
                .toolCalls(
                    entryID: toolCallsEntryID,
                    action: .toolCall(
                        id: id, name: name,
                        action: .appendArguments(
                            argumentsFragment,
                            tokenCount: argumentsFragment.isEmpty ? 0 : estimatedTokens(argumentsFragment)
                        )
                    )
                ),
            ]
            if !metadata.isEmpty {
                events.append(.toolCalls(
                    entryID: toolCallsEntryID,
                    action: .toolCall(id: id, name: name, action: .updateMetadata(metadata))
                ))
            }
            return events

        case let .usage(input, output):
            pendingUsage = (input, output)
            return []

        case let .finish(reason):
            lastFinishReason = reason
            return []
        }
    }

    // REQ: FR-084 — Apple's session throws "Session ended without producing a
    // response" if one generation yields both a Response entry and a ToolCalls
    // entry, in either order, and the channel exposes no way to remove an entry
    // once created (`replaceTextSegment("")` leaves it in place — measured, OS 27).
    // So a provider that narrates before calling a tool — MiniMax streams its
    // `<think>` block through `delta.content`, Meta a plain preamble, Anthropic
    // routinely emits text before `tool_use` — can only be handled by withholding
    // the text until the stream proves no tool call is coming.
    //
    // REQ: NFR-011 — and a stream that produced nothing at all fails here, named,
    // rather than surfacing as Apple's opaque session error.
    mutating func completionEvents() throws -> [LanguageModelExecutorGenerationChannel.Event] {
        var events: [LanguageModelExecutorGenerationChannel.Event] = []
        // The buffered preamble is deliberately dropped on a tool-call turn: it is
        // the model narrating its intent, not the answer, and the answer arrives in
        // the follow-up generation after the tool result.
        if !sawToolCall, !pendingResponseText.isEmpty {
            events.append(.response(
                entryID: responseEntryID,
                action: .appendText(pendingResponseText, tokenCount: estimatedTokens(pendingResponseText))
            ))
        }
        guard sawToolCall || sawResponse || sawReasoning else {
            throw ProviderStreamError.event(
                provider: providerID,
                type: "empty_generation",
                message: "stream ended with no content, tool call, or reasoning"
                    + (lastFinishReason.map { " (finish_reason: \($0))" } ?? "")
            )
        }
        if let pendingUsage {
            let inputUsage = LanguageModelExecutorGenerationChannel.Usage.Input(
                totalTokenCount: pendingUsage.input, cachedTokenCount: 0
            )
            let outputUsage = LanguageModelExecutorGenerationChannel.Usage.Output(
                totalTokenCount: pendingUsage.output, reasoningTokenCount: 0
            )
            if sawToolCall {
                events.append(.toolCalls(
                    entryID: toolCallsEntryID,
                    action: .updateUsage(input: inputUsage, output: outputUsage)
                ))
            } else if sawResponse {
                events.append(.response(
                    entryID: responseEntryID,
                    action: .updateUsage(input: inputUsage, output: outputUsage)
                ))
            } else if sawReasoning {
                events.append(.reasoning(
                    entryID: reasoningEntryID,
                    action: .updateUsage(input: inputUsage, output: outputUsage)
                ))
            }
        }
        return events
    }

    private func estimatedTokens(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }

    /// Pure accumulation step, pulled out of `channelEvents` so it's testable without
    /// Apple's opaque `LanguageModelExecutorGenerationChannel.Event`/`Action` types,
    /// which expose no way to inspect a produced event's contents from outside the
    /// framework's own session machinery.
    static func accumulatedRedactedThinkingJSON(
        appending value: String, to existing: [String]
    ) -> (updated: [String], json: String) {
        let updated = existing + [value]
        return (updated, redactedThinkingJSON(updated, fallback: value))
    }

    static func redactedThinkingJSON(_ values: [String], fallback: String = "") -> String {
        (try? JSONEncoder().encode(values)).map { String(decoding: $0, as: UTF8.self) } ?? fallback
    }
}
