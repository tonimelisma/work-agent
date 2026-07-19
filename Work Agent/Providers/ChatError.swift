//
//  ChatError.swift
//  Work Agent
//
//  A chat failure, in words a non-developer can act on.
//

import Foundation

// REQ: PRODUCT.md §2 — no status codes or protocol vocabulary in these messages.
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
