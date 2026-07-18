//
//  OpenAICompatibleChatProvider.swift
//  Work Agent
//
//  Streaming chat for every curated provider that speaks OpenAI's wire format.
//  Confirmed live 2026-07-16 for openai, google, moonshotai, deepseek, alibaba, minimax.
//

import Foundation

// REQ: FR-001 — one adapter, many providers. Anthropic is the only curated exception.
nonisolated struct OpenAICompatibleChatProvider: ChatProvider {
    let baseURL: URL
    let session: URLSession

    func stream(messages: [ChatMessage], model: String, apiKey: String)
        -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(
                        RequestBody(
                            model: model,
                            stream: true,
                            messages: messages.map { .init(role: $0.role.rawValue, content: $0.text) }
                        )
                    )

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ChatError.badResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        throw ChatError.from(status: http.statusCode)
                    }

                    for try await line in bytes.lines {
                        guard let payload = SSE.payload(from: line),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: payload),
                              let delta = chunk.choices.first?.delta else { continue }
                        // Reasoning field name varies by provider: DeepSeek/Alibaba use
                        // `reasoning_content`, others `reasoning`. Accept either.
                        if let reasoning = delta.reasoningContent ?? delta.reasoning, !reasoning.isEmpty {
                            continuation.yield(.reasoning(reasoning))
                        }
                        if let content = delta.content, !content.isEmpty {
                            continuation.yield(.text(content))
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
        let stream: Bool
        let messages: [Message]
    }

    struct StreamChunk: Decodable {
        struct Choice: Decodable { let delta: Delta? }
        struct Delta: Decodable {
            let content: String?
            let reasoning: String?
            let reasoningContent: String?
            enum CodingKeys: String, CodingKey {
                case content, reasoning
                case reasoningContent = "reasoning_content"
            }
        }
        let choices: [Choice]
    }
}
