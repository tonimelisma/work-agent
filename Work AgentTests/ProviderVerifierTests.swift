//
//  ProviderVerifierTests.swift
//  Work AgentTests
//

import Foundation
import Testing
@testable import Work_Agent

/// Stubs URLSession so verification is tested without touching the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func session(status: Int) -> URLSession {
        handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data())
        }
        return makeSession()
    }

    static func failing(_ error: Error) -> URLSession {
        handler = { _ in throw error }
        return makeSession()
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private func anthropic() throws -> RegistryProvider {
    let json = """
    {"anthropic": {"id": "anthropic", "name": "Anthropic", "env": [],
                   "models": {"m": {"id": "m", "name": "M", "tool_call": true}}}}
    """
    return try #require(try JSONDecoder().decode(ModelRegistry.self, from: Data(json.utf8)).providers.first)
}

private func unreachableProvider() throws -> RegistryProvider {
    let json = """
    {"nowhere": {"id": "nowhere", "name": "Nowhere", "env": [],
                 "models": {"m": {"id": "m", "name": "M", "tool_call": true}}}}
    """
    return try #require(try JSONDecoder().decode(ModelRegistry.self, from: Data(json.utf8)).providers.first)
}

@Suite("Credential verification", .serialized)
struct ProviderVerifierTests {

    @Test("FR-056: a working key verifies")
    func validKeySucceeds() async throws {
        let verifier = ProviderVerifier(session: StubURLProtocol.session(status: 200))
        let result = await verifier.verify(provider: try anthropic(), key: "good")
        #expect(result == .verified)
    }

    @Test("FR-056: a rejected key reports as rejected")
    func unauthorizedIsRejected() async throws {
        let verifier = ProviderVerifier(session: StubURLProtocol.session(status: 401))
        let result = await verifier.verify(provider: try anthropic(), key: "bad")
        #expect(result == .failed(.rejected))
    }

    @Test("FR-056: a valid key without access is distinguished from a bad key")
    func forbiddenIsNotRejected() async throws {
        // "Your key is wrong" and "your account lacks access" need different actions
        // from the user, so they must not collapse into one message.
        let verifier = ProviderVerifier(session: StubURLProtocol.session(status: 403))
        let result = await verifier.verify(provider: try anthropic(), key: "valid-no-access")
        #expect(result == .failed(.forbidden))
    }

    @Test("FR-056: rate limiting is not reported as an invalid key")
    func rateLimitedIsNotRejection() async throws {
        // A 429 means the key reached the account — it says nothing about validity.
        // Calling it invalid would send the user to regenerate a working key.
        let verifier = ProviderVerifier(session: StubURLProtocol.session(status: 429))
        let result = await verifier.verify(provider: try anthropic(), key: "fine")
        #expect(result == .failed(.rateLimited))
    }

    @Test("FR-056: a network failure is reported as unreachable, not as a bad key")
    func networkFailureIsUnreachable() async throws {
        let verifier = ProviderVerifier(session: StubURLProtocol.failing(URLError(.notConnectedToInternet)))
        let result = await verifier.verify(provider: try anthropic(), key: "fine")

        guard case .failed(.unreachable) = result else {
            Issue.record("Offline should read as unreachable, got \(result)")
            return
        }
    }

    @Test("FR-056: a provider we can't reach fails before any request")
    func unsupportedProvider() async throws {
        let verifier = ProviderVerifier(session: StubURLProtocol.session(status: 200))
        let result = await verifier.verify(provider: try unreachableProvider(), key: "k")
        #expect(result == .failed(.unsupportedProvider))
    }

    @Test("PRODUCT.md §2: verification failures are explained without jargon")
    func failuresAreHumanReadable() {
        let jargon = ["401", "403", "HTTP", "status", "header", "x-api-key", "Bearer", "nil", "URLError"]

        for failure: VerificationFailure in [.rejected, .forbidden, .rateLimited, .unsupportedProvider] {
            let message = failure.errorDescription ?? ""
            #expect(!message.isEmpty)
            for term in jargon {
                #expect(!message.contains(term), "\"\(message)\" leaks implementation vocabulary: \(term)")
            }
        }
    }
}
