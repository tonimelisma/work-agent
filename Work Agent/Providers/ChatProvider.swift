//
//  ChatProvider.swift
//  Work Agent
//
//  The provider seam for streaming chat. FR-001 lives here.
//

import Foundation

// REQ: FR-001 — all inference goes through this abstraction; no feature depends on a
// specific vendor. Two adapters implement it (OpenAI-compatible + Anthropic); which one
// a provider uses is a routing detail, never visible above this line. (ADR-0006)

/// One streamed piece of a reply.
nonisolated enum ChatChunk: Sendable, Equatable {
    case text(String)
    /// Model reasoning (a.k.a. thinking). Shown separately and toggleable (FR-065/066).
    case reasoning(String)
}

/// A chat failure, in words a non-developer can act on.
// REQ: FR-040 — no status codes or protocol vocabulary in these messages.
nonisolated enum ChatError: LocalizedError, Equatable {
    case notConfigured
    case rejected
    case outOfCredit
    case rateLimited
    case unreachable(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No model is set up yet. Add one in Settings."
        case .rejected:
            "The key for this model was rejected. Re-add it in Settings."
        case .outOfCredit:
            "This account is out of credit with the provider."
        case .rateLimited:
            "The provider is busy right now. Try again in a moment."
        case .unreachable(let detail):
            "Couldn't reach the provider: \(detail)"
        case .badResponse:
            "The provider sent back something unexpected."
        }
    }

    /// Map an HTTP status to a user-facing failure.
    static func from(status: Int) -> ChatError {
        switch status {
        case 401, 403: .rejected
        case 402: .outOfCredit
        case 429: .rateLimited          // could be rate limit or quota; both "wait/att'n"
        default: .badResponse
        }
    }
}

/// Streams a model reply. One implementation per wire format.
nonisolated protocol ChatProvider: Sendable {
    /// Stream a reply to `messages` from `model`, authenticating with `apiKey`.
    /// Errors (including `ChatError`) surface by being thrown from the stream.
    func stream(messages: [ChatMessage], model: String, apiKey: String)
        -> AsyncThrowingStream<ChatChunk, Error>
}

/// Chooses the adapter for a provider.
// REQ: NFR-001 — a new provider is a routing entry here plus, at most, one adapter.
enum ChatProviderFactory {
    static func provider(for registryProvider: RegistryProvider,
                         session: URLSession = .shared) -> ChatProvider? {
        guard let base = ProviderCatalog.chatBaseURL(for: registryProvider) else { return nil }

        switch registryProvider.id {
        case "anthropic":
            return AnthropicChatProvider(baseURL: base, session: session)
        default:
            // Everything curated except Anthropic speaks the OpenAI wire format, including
            // Google (via its /v1beta/openai endpoint) and MiniMax (via /v1). Confirmed
            // live 2026-07-16 — see docs/research/provider-chat-endpoints.md.
            return OpenAICompatibleChatProvider(baseURL: base, session: session)
        }
    }
}

// MARK: - Shared SSE plumbing

nonisolated enum SSE {
    /// The JSON payload of an SSE `data:` line, or nil for lines to skip (comments,
    /// blank lines, `event:` lines, and the `[DONE]` sentinel).
    static func payload(from line: String) -> Data? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        return Data(payload.utf8)
    }
}
