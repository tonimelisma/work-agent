import Foundation
import Testing
@testable import Executors

// REQ: GLM's JWT auth (research/provider-chat-endpoints.md "The Zhipu/GLM wrinkle") is
// pure given an injected clock, so it's verified against an exact expected token string
// offline rather than only through the live gated matrix.

@Suite("Zhipu JWT construction")
struct ZhipuJWTTests {
    @Test("A fixed clock and key produce the exact expected token")
    func exactTokenForFixedInputs() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let token = try ZhipuJWT.token(apiKey: "testid.testsecret", now: fixedNow)
        #expect(token == "eyJhbGciOiJIUzI1NiIsInNpZ25fdHlwZSI6IlNJR04ifQ" +
            ".eyJhcGlfa2V5IjoidGVzdGlkIiwiZXhwIjoxNzAwMDAzNjAwMDAwLCJ0aW1lc3RhbXAiOjE3MDAwMDAwMDAwMDB9" +
            ".06JllEoEQIy99XA2xnHIWswGLJYthZCcYv_bw3b1gWE")
    }

    @Test("A key with no '.' separator is rejected")
    func rejectsMalformedKey() {
        #expect(throws: ZhipuAuthError.malformedAPIKey) {
            try ZhipuJWT.token(apiKey: "no-separator-here")
        }
    }

    @Test("A key with an empty id or secret half is rejected")
    func rejectsEmptyHalves() {
        #expect(throws: ZhipuAuthError.malformedAPIKey) {
            try ZhipuJWT.token(apiKey: ".secretonly")
        }
        #expect(throws: ZhipuAuthError.malformedAPIKey) {
            try ZhipuJWT.token(apiKey: "idonly.")
        }
    }

    @Test("A secret containing '.' is preserved intact (split at the first '.' only)")
    func splitsOnlyAtFirstDot() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        // Same id, secret "testsecret" vs "test.secret" must sign differently.
        let plain = try ZhipuJWT.token(apiKey: "testid.testsecret", now: fixedNow)
        let dotted = try ZhipuJWT.token(apiKey: "testid.test.secret", now: fixedNow)
        #expect(plain != dotted)
    }
}
