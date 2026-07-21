import Foundation

// REQ: provider-neutral events the executors feed into Apple's generation
// channel. Migrated from the pre-pivot Foundation Models POC (see `git log`),
// proven live against DeepSeek, Google, and Anthropic (increment 3).
public enum ExecutorEvent: Codable, Equatable, Sendable {
    case response(text: String)
    case reasoning(text: String, signature: String?, metadata: [String: String])
    case toolCall(
        index: Int,
        id: String,
        name: String,
        argumentsFragment: String,
        metadata: [String: String]
    )
    case usage(input: Int, output: Int)
    case finish(reason: String)
}

public enum StreamParseError: LocalizedError, Equatable, Sendable {
    case invalidJSON(line: Int)
    case missingToolBlock(index: Int, line: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidJSON(line):
            "Invalid stream JSON on line \(line)"
        case let .missingToolBlock(index, line):
            "Anthropic tool fragment for block \(index) has no preceding content_block_start on line \(line)"
        }
    }
}

public enum ProviderStreamError: LocalizedError, Equatable, Sendable {
    case event(provider: String, type: String?, message: String?)

    public var errorDescription: String? {
        switch self {
        case let .event(provider, type, message):
            "\(provider) stream error \(type ?? "unknown"): \(message ?? "No message supplied")"
        }
    }
}

public struct OpenAICompatibleStreamParser: Sendable {
    private struct ToolState: Sendable {
        var id = ""
        var name = ""
    }

    private var tools: [Int: ToolState] = [:]

    public init() {}

    public mutating func consume(_ line: String, lineNumber: Int) throws -> [ExecutorEvent] {
        guard let object = try sseObject(from: line, lineNumber: lineNumber) else { return [] }
        var events: [ExecutorEvent] = []

        if let usage = object["usage"] as? [String: Any] {
            let input = (usage["prompt_tokens"] ?? usage["input_tokens"]) as? Int ?? 0
            let output = (usage["completion_tokens"] ?? usage["output_tokens"]) as? Int ?? 0
            events.append(.usage(input: input, output: output))
        }

        for choice in object["choices"] as? [[String: Any]] ?? [] {
            let delta = choice["delta"] as? [String: Any] ?? [:]

            if let reasoning = (delta["reasoning_content"] ?? delta["reasoning"]) as? String {
                let signature = Self.googleThoughtSignature(in: delta)
                var metadata: [String: String] = [:]
                if let signature { metadata["google.thought_signature"] = signature }
                events.append(.reasoning(text: reasoning, signature: signature, metadata: metadata))
            } else if let signature = Self.googleThoughtSignature(in: delta) {
                events.append(.reasoning(
                    text: "",
                    signature: signature,
                    metadata: ["google.thought_signature": signature]
                ))
            }

            if let content = delta["content"] as? String {
                events.append(.response(text: content))
            }

            for call in delta["tool_calls"] as? [[String: Any]] ?? [] {
                let index = call["index"] as? Int ?? 0
                let function = call["function"] as? [String: Any] ?? [:]
                var state = tools[index] ?? ToolState()
                if let id = call["id"] as? String, !id.isEmpty { state.id = id }
                if let name = function["name"] as? String, !name.isEmpty { state.name = name }
                tools[index] = state
                var metadata: [String: String] = [:]
                if let signature = Self.googleThoughtSignature(in: call) {
                    metadata["google.thought_signature"] = signature
                }
                events.append(.toolCall(
                    index: index,
                    id: state.id,
                    name: state.name,
                    argumentsFragment: function["arguments"] as? String ?? "",
                    metadata: metadata
                ))
            }

            if let finishReason = choice["finish_reason"] as? String {
                events.append(.finish(reason: finishReason))
            }
        }
        return events
    }

    private static func googleThoughtSignature(in delta: [String: Any]) -> String? {
        if let signature = delta["thought_signature"] as? String { return signature }
        let extraContent = delta["extra_content"] as? [String: Any]
        let google = extraContent?["google"] as? [String: Any]
        return google?["thought_signature"] as? String
    }
}

public struct AnthropicStreamParser: Sendable {
    private struct ToolState: Sendable {
        var id: String
        var name: String
    }

    private var tools: [Int: ToolState] = [:]
    private var inputTokens = 0

    public init() {}

    public mutating func consume(_ line: String, lineNumber: Int) throws -> [ExecutorEvent] {
        guard let object = try sseObject(from: line, lineNumber: lineNumber) else { return [] }
        let type = object["type"] as? String
        var events: [ExecutorEvent] = []

        switch type {
        case "error":
            let error = object["error"] as? [String: Any]
            throw ProviderStreamError.event(
                provider: "anthropic",
                type: error?["type"] as? String,
                message: error?["message"] as? String
            )

        case "message_start":
            let message = object["message"] as? [String: Any]
            let usage = message?["usage"] as? [String: Any]
            inputTokens = usage?["input_tokens"] as? Int ?? 0

        case "content_block_start":
            let index = object["index"] as? Int ?? 0
            let block = object["content_block"] as? [String: Any] ?? [:]
            guard block["type"] as? String == "tool_use" else { return [] }
            let state = ToolState(
                id: block["id"] as? String ?? "",
                name: block["name"] as? String ?? ""
            )
            tools[index] = state
            if let initialInput = block["input"] as? [String: Any], !initialInput.isEmpty {
                let data = try JSONSerialization.data(withJSONObject: initialInput, options: [.sortedKeys])
                events.append(.toolCall(
                    index: index,
                    id: state.id,
                    name: state.name,
                    argumentsFragment: String(decoding: data, as: UTF8.self),
                    metadata: [:]
                ))
            }

        case "content_block_delta":
            let index = object["index"] as? Int ?? 0
            let delta = object["delta"] as? [String: Any] ?? [:]
            switch delta["type"] as? String {
            case "text_delta":
                events.append(.response(text: delta["text"] as? String ?? ""))
            case "thinking_delta":
                events.append(.reasoning(
                    text: delta["thinking"] as? String ?? "",
                    signature: nil,
                    metadata: [:]
                ))
            case "signature_delta":
                let signature = delta["signature"] as? String ?? ""
                events.append(.reasoning(
                    text: "",
                    signature: signature,
                    metadata: ["anthropic.signature": signature]
                ))
            case "input_json_delta":
                guard let state = tools[index] else {
                    throw StreamParseError.missingToolBlock(index: index, line: lineNumber)
                }
                events.append(.toolCall(
                    index: index,
                    id: state.id,
                    name: state.name,
                    argumentsFragment: delta["partial_json"] as? String ?? "",
                    metadata: [:]
                ))
            default:
                break
            }

        case "message_delta":
            let delta = object["delta"] as? [String: Any] ?? [:]
            let usage = object["usage"] as? [String: Any] ?? [:]
            if let outputTokens = usage["output_tokens"] as? Int {
                events.append(.usage(input: inputTokens, output: outputTokens))
            }
            if let stopReason = delta["stop_reason"] as? String {
                events.append(.finish(reason: stopReason))
            }

        default:
            break
        }
        return events
    }
}

func sseObject(from line: String, lineNumber: Int) throws -> [String: Any]? {
    guard line.hasPrefix("data:") else { return nil }
    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
    guard payload != "[DONE]", !payload.isEmpty else { return nil }
    guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
        throw StreamParseError.invalidJSON(line: lineNumber)
    }
    return object
}
