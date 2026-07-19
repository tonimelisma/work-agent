//
//  ProviderVerifier.swift
//  Work Agent
//
//  Checks a credential against the live provider before we claim it works.
//

import Foundation

/// Why a credential didn't verify — in words a non-developer can act on.
// REQ: PRODUCT.md §2 — no status codes, no header names, no provider jargon in these strings.
nonisolated enum VerificationFailure: LocalizedError, Equatable {
    case rejected
    case forbidden
    case rateLimited
    case unreachable(String)
    case unsupportedProvider
    case unexpected(Int)

    var errorDescription: String? {
        switch self {
        case .rejected:
            "That key was rejected. Check you copied all of it."
        case .forbidden:
            "That key is valid but doesn't have access. Check the plan or permissions on your account."
        case .rateLimited:
            "The provider is rate limiting right now. Try again in a moment."
        case .unreachable(let detail):
            "Couldn't reach the provider: \(detail)"
        case .unsupportedProvider:
            "This provider can't be reached automatically yet."
        case .unexpected(let code):
            "The provider responded unexpectedly (\(code))."
        }
    }
}

/// The outcome of checking a credential.
nonisolated enum VerificationResult: Equatable {
    case verified
    case failed(VerificationFailure)
}

/// Verifies provider credentials by making the cheapest authenticated call available.
// REQ: FR-056 — verify a credential against the provider before reporting it usable.
nonisolated struct ProviderVerifier {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func verify(provider: RegistryProvider, key: String) async -> VerificationResult {
        guard var request = ProviderCatalog.verificationRequest(for: provider, key: key) else {
            return .failed(.unsupportedProvider)
        }
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(.unexpected(0))
            }

            switch http.statusCode {
            case 200...299:
                return .verified
            case 401:
                return .failed(.rejected)
            case 403:
                return .failed(.forbidden)
            case 429:
                // The key reached the account, which is what we're testing. Being rate
                // limited says nothing about validity, so don't call it invalid.
                return .failed(.rateLimited)
            default:
                return .failed(.unexpected(http.statusCode))
            }
        } catch {
            return .failed(.unreachable(error.localizedDescription))
        }
    }
}
