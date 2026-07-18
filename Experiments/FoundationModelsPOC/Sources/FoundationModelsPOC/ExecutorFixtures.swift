import Foundation

/// Structural representation of the Foundation Models generation channel. It is used
/// by offline fixture tests; live probes may only write scrubbed instances of this type.
public enum ExecutorEvent: Codable, Equatable, Sendable {
    case response(text: String)
    case reasoning(text: String, signature: String?, metadata: [String: String])
    case toolCall(id: String, name: String, argumentsFragment: String, metadata: [String: String])
    case usage(input: Int, output: Int)
}

public enum OpenAICompatibleFixtureParser {
    public static func events(from lines: [String]) throws -> [ExecutorEvent] {
        try lines.compactMap { line in
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { return nil }
            let object = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any] ?? [:]
            let choice = (object["choices"] as? [[String: Any]])?.first
            let delta = choice?["delta"] as? [String: Any] ?? [:]
            if let content = delta["content"] as? String { return .response(text: content) }
            if let reasoning = (delta["reasoning_content"] ?? delta["reasoning"]) as? String {
                return .reasoning(text: reasoning, signature: delta["thought_signature"] as? String, metadata: [:])
            }
            if let call = (delta["tool_calls"] as? [[String: Any]])?.first {
                let function = call["function"] as? [String: Any] ?? [:]
                return .toolCall(id: call["id"] as? String ?? "", name: function["name"] as? String ?? "", argumentsFragment: function["arguments"] as? String ?? "", metadata: [:])
            }
            return nil
        }
    }
}

public enum AnthropicFixtureParser {
    public static func events(from lines: [String]) throws -> [ExecutorEvent] {
        try lines.compactMap { line in
            guard line.hasPrefix("data: ") else { return nil }
            let object = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any] ?? [:]
            let delta = object["delta"] as? [String: Any] ?? [:]
            switch delta["type"] as? String {
            case "text_delta": return .response(text: delta["text"] as? String ?? "")
            case "thinking_delta": return .reasoning(text: delta["thinking"] as? String ?? "", signature: nil, metadata: [:])
            case "input_json_delta": return .toolCall(id: object["index"].map { "block-\($0)" } ?? "", name: "", argumentsFragment: delta["partial_json"] as? String ?? "", metadata: [:])
            default: return nil
            }
        }
    }
}
