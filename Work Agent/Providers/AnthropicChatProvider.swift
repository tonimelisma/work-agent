//
//  AnthropicChatProvider.swift
//  Work Agent
//
//  Streaming chat for Anthropic's Messages API — the one curated provider that
//  doesn't speak the OpenAI wire format. Confirmed live 2026-07-16.
//

import Foundation

nonisolated struct AnthropicChatProvider: ChatProvider {
    let baseURL: URL
    let session: URLSession

    /// Anthropic requires max_tokens; this is the per-reply ceiling for chat.
    private let maxTokens = 4096

    func stream(messages: [ChatMessage], model: String, apiKey: String)
        -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Anthropic takes `system` separately and only user/assistant turns
                    // in `messages`.
                    let system = messages.filter { $0.role == .system }
                        .map(\.text).joined(separator: "\n\n")
                    let turns = messages.filter { $0.role != .system }
                        .map { RequestBody.Message(role: $0.role == .assistant ? "assistant" : "user",
                                                   content: $0.text) }

                    var request = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(
                        RequestBody(model: model, maxTokens: maxTokens, stream: true,
                                    system: system.isEmpty ? nil : system, messages: turns)
                    )

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ChatError.badResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        throw ChatError.from(status: http.statusCode)
                    }

                    for try await line in bytes.lines {
                        guard let payload = SSE.payload(from: line),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: payload) else { continue }
                        if event.type == "error" { throw ChatError.badResponse }
                        guard event.type == "content_block_delta", let delta = event.delta else { continue }
                        switch delta.type {
                        case "text_delta":
                            if let text = delta.text, !text.isEmpty { continuation.yield(.text(text)) }
                        case "thinking_delta":
                            if let thinking = delta.thinking, !thinking.isEmpty { continuation.yield(.reasoning(thinking)) }
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as ChatError {
                    continuation.finish(throwing: error)
                } catch let urlError as URLError {
                    continuation.finish(throwing: ChatError.unreachable(urlError.localizedDescription))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Wire types

    private struct RequestBody: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let maxTokens: Int
        let stream: Bool
        let system: String?
        let messages: [Message]
        enum CodingKeys: String, CodingKey {
            case model, stream, system, messages
            case maxTokens = "max_tokens"
        }
    }

    struct StreamEvent: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let thinking: String?
        }
        let type: String
        let delta: Delta?
    }
}
